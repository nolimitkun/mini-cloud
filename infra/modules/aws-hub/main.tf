# AWS Tier-2 cloud hub: Direct Connect Gateway -> Transit Gateway,
# inspection VPC with Network Firewall, Route 53 Resolver endpoints.
# Private-only: no IGW, no public subnets, no public VIF.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# --- Transit Gateway (Tier-2 hub) ---
resource "aws_ec2_transit_gateway" "hub" {
  description                     = "Hybrid cloud Tier-2 hub"
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable" # explicit route tables only
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags                            = merge(var.tags, { Name = "hub-tgw" })
}

# --- Direct Connect Gateway + association to TGW ---
resource "aws_dx_gateway" "this" {
  name            = "hub-dxgw"
  amazon_side_asn = var.amazon_side_asn
}

resource "aws_dx_gateway_association" "tgw" {
  dx_gateway_id         = aws_dx_gateway.this.id
  associated_gateway_id = aws_ec2_transit_gateway.hub.id
  allowed_prefixes      = [var.cloud_supernet] # advertise the /12 summary only (doc 02 §3.3)
}

# NOTE: the Transit VIF on var.dx_connection_id is created against the DX gateway.
# eBGP 65000 <-> amazon_side_asn comes up over the VIF; enable BFD on the on-prem side.
# resource "aws_dx_transit_virtual_interface" "primary" { ... }  # TODO per-circuit

# --- Inspection VPC (hub_cidr) with AWS Network Firewall ---
resource "aws_vpc" "inspection" {
  cidr_block           = var.hub_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "hub-inspection" })
}

# Deliberately NO aws_internet_gateway — egress is via on-prem only (C2).

# Firewall subnets, one per AZ, carved from the hub /20.
resource "aws_subnet" "firewall" {
  for_each          = { for i, az in var.firewall_azs : az => cidrsubnet(var.hub_cidr, 4, i) }
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = each.value
  availability_zone = each.key
  tags              = merge(var.tags, { Name = "hub-fw-${each.key}" })
}

resource "aws_networkfirewall_firewall" "hub" {
  name                = "hub-fw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.hub.arn
  vpc_id              = aws_vpc.inspection.id
  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "hub" {
  name = "hub-fw-policy"
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    # Stateful rule groups: default-deny egress, allow approved east-west prefixes (doc 02 §4)
  }
}

# --- TGW route table: on-prem + approved cross-cloud via DX; spokes -> firewall ---
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id
  tags               = merge(var.tags, { Name = "hub-rt" })
}

# Route 53 Resolver inbound/outbound endpoints live in the inspection VPC.
# resource "aws_route53_resolver_endpoint" "inbound"  { ... }  # TODO (doc 05)
# resource "aws_route53_resolver_endpoint" "outbound" { ... }  # TODO (doc 05)

# Cross-cloud-consumed PrivateLink endpoints go in the cross-cloud PaaS block
# 172.17.64.0/24 (doc 02 §1.2); intra-cloud/on-prem-only endpoints stay in 10.16.64.0/20.
