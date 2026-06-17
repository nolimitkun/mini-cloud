# AWS landing-zone stack: composes the Tier-2 hub + workload spokes for one region.
# Run after policy/ (org guardrails) is in place.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # backend "s3" { ... }  # TODO: remote state (S3 + DynamoDB lock)
}

provider "aws" {
  region = "eu-west-1"
  # assume_role into the network account  # TODO
}

variable "dx_connection_id" {
  description = "Dedicated Direct Connect connection id (ordered out-of-band, doc 03 §3)."
  type        = string
}

locals {
  cloud_supernet = "10.16.0.0/12"
  tags           = { project = "hybrid-cloud", tier = "landing-zone", cloud = "aws" }
}

module "hub" {
  source           = "../../modules/aws-hub"
  region           = "eu-west-1"
  cloud_supernet   = local.cloud_supernet
  hub_cidr         = "10.16.0.0/20"
  amazon_side_asn  = 65010
  dx_connection_id = var.dx_connection_id
  tags             = local.tags
}

# Workload spokes — one module instance per spoke (doc 02 §1.2).
module "spoke" {
  source             = "../../modules/aws-spoke"
  for_each           = {
    prod    = "10.16.16.0/20"
    nonprod = "10.16.32.0/20"
    shared  = "10.16.48.0/20"
  }
  name               = each.key
  spoke_cidr         = each.value
  transit_gateway_id = module.hub.transit_gateway_id
  tags               = local.tags
}
