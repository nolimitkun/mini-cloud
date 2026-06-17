# Azure VPN PoC stack. Local state (throwaway PoC).
# Fill terraform.tfvars, then: terraform init && terraform apply && terraform output
# Note: the VPN gateway takes ~20-45 min to provision.

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "westeurope"
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

module "vpn_poc" {
  source           = "../../modules/azure-vpn-poc"
  location         = var.location
  onprem_public_ip = var.onprem_public_ip
  onprem_lan_cidr  = var.onprem_lan_cidr
  shared_secret    = var.shared_secret
}

output "vpn_gateway_public_ip" { value = module.vpn_poc.vpn_gateway_public_ip }
output "vnet_cidr" { value = module.vpn_poc.vnet_cidr }
