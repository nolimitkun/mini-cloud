# GCP VPN PoC stack. Local state is fine for a throwaway PoC.
# Fill terraform.tfvars, then: terraform init && terraform apply && terraform output

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
  # No remote backend — PoC uses local state. Add one if you keep it around.
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west1"
}
variable "onprem_public_ip" { type = string }
variable "onprem_lan_cidr" {
  type    = string
  default = "192.168.1.0/24"
}
variable "shared_secret" {
  type      = string
  sensitive = true
}
# VM-less by default — test via the Cloud Router BGP IP (169.254.0.1) + BGP session.
variable "enable_test_vm" {
  type    = bool
  default = false
}
variable "enable_crosscloud_test_vm" {
  type    = bool
  default = false
}
variable "crosscloud_cidr" {
  type    = string
  default = "192.168.50.0/24" # PoC choice (non-overlapping home-style); prod plan uses 172.19.x
}

# --- GCP hub-and-spoke: a separate spoke project peered to the hub VPC ---
variable "enable_spoke" {
  type    = bool
  default = false
}
variable "spoke_project_id" {
  type    = string
  default = "mini-cloud-lakehouse"
}
variable "billing_account" {
  type    = string
  default = ""
}
variable "spoke_cidr" {
  type    = string
  default = "10.48.16.0/24"
}
variable "org_id" {
  type    = string
  default = "" # set to the GCP org id (e.g. 1001419803488) to place the spoke under the org
}
variable "spoke_mode" {
  type    = string
  default = "peering" # "peering" (no org needed) or "shared_vpc" (needs org + compute.xpnAdmin)
  validation {
    condition     = contains(["peering", "shared_vpc"], var.spoke_mode)
    error_message = "spoke_mode must be 'peering' or 'shared_vpc'."
  }
}

module "vpn_poc" {
  source                    = "../../modules/gcp-vpn-poc"
  project_id                = var.project_id
  region                    = var.region
  onprem_public_ip          = var.onprem_public_ip
  onprem_lan_cidr           = var.onprem_lan_cidr
  shared_secret             = var.shared_secret
  crosscloud_cidr           = var.crosscloud_cidr
  enable_test_vm            = var.enable_test_vm
  enable_crosscloud_test_vm = var.enable_crosscloud_test_vm
  # Peering spoke needs the Cloud Router to advertise its subnet; Shared VPC
  # spoke lives in the hub VPC so DEFAULT advertisement already covers it.
  advertised_extra_ranges = (var.enable_spoke && var.spoke_mode == "peering") ? [var.spoke_cidr] : []
}

# Spoke A — VPC peering (works without an org)
module "spoke" {
  count            = var.enable_spoke && var.spoke_mode == "peering" ? 1 : 0
  source           = "../../modules/gcp-poc-spoke"
  spoke_project_id = var.spoke_project_id
  billing_account  = var.billing_account
  org_id           = var.org_id
  region           = var.region
  spoke_cidr       = var.spoke_cidr
  hub_network      = module.vpn_poc.network_self_link
  onprem_lan_cidr  = var.onprem_lan_cidr
}

# Spoke B — Shared VPC (needs org + compute.xpnAdmin)
module "spoke_shared" {
  count             = var.enable_spoke && var.spoke_mode == "shared_vpc" ? 1 : 0
  source            = "../../modules/gcp-poc-spoke-sharedvpc"
  spoke_project_id  = var.spoke_project_id
  billing_account   = var.billing_account
  org_id            = var.org_id
  region            = var.region
  spoke_cidr        = var.spoke_cidr
  host_project_id   = var.project_id
  host_network_name = module.vpn_poc.network_name
}

output "vpn_gateway_ip" { value = module.vpn_poc.vpn_gateway_ip }
output "bgp_gcp_ip" { value = module.vpn_poc.bgp_gcp_ip }
output "bgp_onprem_ip" { value = module.vpn_poc.bgp_onprem_ip }
output "test_vm_internal_ip" { value = module.vpn_poc.test_vm_internal_ip }
output "vpn_tunnel_name" { value = module.vpn_poc.vpn_tunnel_name }
output "cloud_router_name" { value = module.vpn_poc.cloud_router_name }
output "private_subnet_cidr" { value = module.vpn_poc.private_subnet_cidr }
output "crosscloud_subnet_cidr" { value = module.vpn_poc.crosscloud_subnet_cidr }
output "crosscloud_test_vm_internal_ip" { value = module.vpn_poc.crosscloud_test_vm_internal_ip }
locals {
  spoke_vm_ip = coalesce(
    try(module.spoke[0].spoke_vm_internal_ip, null),
    try(module.spoke_shared[0].spoke_vm_internal_ip, null),
    "none"
  )
  spoke_proj = coalesce(
    try(module.spoke[0].project_id, null),
    try(module.spoke_shared[0].project_id, null),
    "none"
  )
}

output "spoke_project_id" { value = var.enable_spoke ? local.spoke_proj : null }
output "spoke_vm_internal_ip" { value = var.enable_spoke ? local.spoke_vm_ip : null }
output "spoke_mode" { value = var.enable_spoke ? var.spoke_mode : null }
