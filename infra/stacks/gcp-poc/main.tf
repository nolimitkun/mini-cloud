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
variable "enable_crosscloud_test_vm" {
  type    = bool
  default = false
}
variable "crosscloud_cidr" {
  type    = string
  default = "192.168.50.0/24" # PoC choice (non-overlapping home-style); prod plan uses 172.19.x
}

module "vpn_poc" {
  source                    = "../../modules/gcp-vpn-poc"
  project_id                = var.project_id
  region                    = var.region
  onprem_public_ip          = var.onprem_public_ip
  onprem_lan_cidr           = var.onprem_lan_cidr
  shared_secret             = var.shared_secret
  crosscloud_cidr           = var.crosscloud_cidr
  enable_crosscloud_test_vm = var.enable_crosscloud_test_vm
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
