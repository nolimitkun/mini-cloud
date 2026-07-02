# AWS landing-zone stack: composes the Tier-2 hub + workload spokes for one region.
# Run after policy/ (org guardrails) is in place.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # backend "s3" { ... }  # TODO: remote state (S3 + DynamoDB lock)
}

variable "region" {
  description = "AWS region for this landing zone (doc D3)."
  type        = string
  default     = "eu-west-1"
}

variable "dx_connection_id" {
  description = "Dedicated Direct Connect connection id (ordered out-of-band, doc 03 §3)."
  type        = string
}

provider "aws" {
  region = var.region
  # assume_role into the network account  # TODO
}

# Derive AZs from the target region so overriding var.region stays consistent
# with the subnets (avoids the hardcoded eu-west-1a/b module defaults).
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cloud_supernet = "10.16.0.0/12"
  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  tags           = { project = "hybrid-cloud", tier = "landing-zone", cloud = "aws" }
}

module "hub" {
  source           = "../../modules/aws-hub"
  region           = var.region
  cloud_supernet   = local.cloud_supernet
  hub_cidr         = "10.16.0.0/20"
  amazon_side_asn  = 65010
  dx_connection_id = var.dx_connection_id
  firewall_azs     = local.azs
  tags             = local.tags
}

# Workload spokes — one module instance per spoke (doc 02 §1.2).
module "spoke" {
  source = "../../modules/aws-spoke"
  for_each = {
    prod    = { private = "10.16.16.0/20", xcloud = "172.17.16.0/24" }
    nonprod = { private = "10.16.32.0/20", xcloud = "172.17.32.0/24" }
    shared  = { private = "10.16.48.0/20", xcloud = "172.17.48.0/24" }
  }
  name               = each.key
  spoke_cidr         = each.value.private
  crosscloud_cidr    = each.value.xcloud
  transit_gateway_id = module.hub.transit_gateway_id
  azs                = local.azs
  tags               = local.tags
}
