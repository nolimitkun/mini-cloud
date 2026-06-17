# AWS VPN PoC: Site-to-Site VPN (VGW) to an on-prem strongSwan peer, dynamic BGP.
# AWS provisions TWO tunnels (two outside IPs, two inside /30s) automatically.
# Private VPC, no IGW. Matches the GCP PoC pattern (doc 08).

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

resource "aws_vpc" "poc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "vpc-poc" }
}

resource "aws_subnet" "workload" {
  vpc_id     = aws_vpc.poc.id
  cidr_block = var.subnet_cidr
  tags       = { Name = "subnet-poc-workload" }
}

# Deliberately NO aws_internet_gateway — reachable only over the VPN.

resource "aws_vpn_gateway" "vgw" {
  amazon_side_asn = var.amazon_side_asn
  tags            = { Name = "vgw-poc" }
}

resource "aws_vpn_gateway_attachment" "att" {
  vpc_id         = aws_vpc.poc.id
  vpn_gateway_id = aws_vpn_gateway.vgw.id
}

resource "aws_customer_gateway" "cgw" {
  bgp_asn    = var.onprem_asn
  ip_address = var.onprem_public_ip
  type       = "ipsec.1"
  tags       = { Name = "cgw-onprem" }
}

resource "aws_vpn_connection" "conn" {
  vpn_gateway_id        = aws_vpn_gateway.vgw.id
  customer_gateway_id   = aws_customer_gateway.cgw.id
  type                  = "ipsec.1"
  static_routes_only    = false # dynamic BGP
  tunnel1_preshared_key = var.shared_secret
  tunnel2_preshared_key = var.shared_secret
  tags                  = { Name = "vpn-poc" }
}

# Route table with VGW route propagation (learns on-prem 192.168.1.0/24 via BGP).
resource "aws_route_table" "poc" {
  vpc_id = aws_vpc.poc.id
  tags   = { Name = "rt-poc" }
}

resource "aws_vpn_gateway_route_propagation" "poc" {
  vpn_gateway_id = aws_vpn_gateway.vgw.id
  route_table_id = aws_route_table.poc.id
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.poc.id
}

# Allow only on-prem LAN in; no public ingress.
resource "aws_security_group" "from_lan" {
  name        = "allow-from-onprem-lan"
  description = "Allow on-prem LAN over the VPN"
  vpc_id      = aws_vpc.poc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.onprem_lan_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
