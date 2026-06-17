# GCP landing-zone stack: Tier-2 hub (Shared VPC host) + workload service projects.
# Run after policy/.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  # backend "gcs" { ... }  # TODO: remote state
}

provider "google" {
  region = "us-east4"
  # credentials / impersonation for the host project  # TODO
}

variable "host_project_id" {
  description = "Shared VPC host project (the cloud hub)."
  type        = string
}
variable "prod_project_id" { type = string }
variable "nonprod_project_id" { type = string }
variable "shared_project_id" { type = string }
variable "interconnect_attachment_names" {
  description = "VLAN attachment names for the two Interconnect circuits (doc 03 §5)."
  type        = list(string)
  default     = ["ic-attach-a", "ic-attach-b"]
}

locals {
  region = "us-east4"
}

module "hub" {
  source                        = "../../modules/gcp-hub"
  project_id                    = var.host_project_id
  region                        = local.region
  hub_cidr                      = "10.48.0.0/20"
  interconnect_attachment_names = var.interconnect_attachment_names
}

module "spoke" {
  source   = "../../modules/gcp-spoke"
  for_each = {
    prod    = { project = var.prod_project_id, cidr = "10.48.16.0/20" }
    nonprod = { project = var.nonprod_project_id, cidr = "10.48.32.0/20" }
    shared  = { project = var.shared_project_id, cidr = "10.48.48.0/20" }
  }
  name               = each.key
  service_project_id = each.value.project
  host_project_id    = module.hub.host_project_id
  region             = local.region
  spoke_cidr         = each.value.cidr
}
