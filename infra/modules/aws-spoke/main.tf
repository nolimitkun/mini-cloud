# AWS workload spoke: private VPC attached to the Tier-2 hub TGW.
# No IGW, no public subnet, no public IP. Default route -> hub firewall (doc 02 §3.4).

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

resource "aws_vpc" "spoke" {
  cidr_block           = var.spoke_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "spoke-${var.name}" })
}

# Private subnets only (app + data tiers), one per AZ. No public subnets by design.
resource "aws_subnet" "private" {
  for_each          = { for i, az in var.azs : az => cidrsubnet(var.spoke_cidr, 4, i) }
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = each.value
  availability_zone = each.key
  # map_public_ip_on_launch deliberately omitted (defaults false); SCP denies public IPs anyway.
  tags = merge(var.tags, { Name = "spoke-${var.name}-${each.key}" })
}

# Attach the spoke to the Tier-2 hub.
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  subnet_ids         = [for s in aws_subnet.private : s.id]
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.spoke.id
  tags               = merge(var.tags, { Name = "spoke-${var.name}-attach" })
}

# Default route to the hub (egress + east-west forced through hub firewall).
resource "aws_route_table" "spoke" {
  vpc_id = aws_vpc.spoke.id
  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = var.transit_gateway_id
  }
  tags = merge(var.tags, { Name = "spoke-${var.name}-rt" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.spoke.id
}
