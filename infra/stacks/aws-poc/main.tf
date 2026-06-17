# AWS VPN PoC stack. Local state (throwaway PoC).
# Fill terraform.tfvars, then: terraform init && terraform apply && terraform output

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-1"
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
  source           = "../../modules/aws-vpn-poc"
  region           = var.region
  onprem_public_ip = var.onprem_public_ip
  onprem_lan_cidr  = var.onprem_lan_cidr
  shared_secret    = var.shared_secret
}

output "tunnel1_address" { value = module.vpn_poc.tunnel1_address }
output "tunnel2_address" { value = module.vpn_poc.tunnel2_address }
output "tunnel1_cgw_inside_address" { value = module.vpn_poc.tunnel1_cgw_inside_address }
output "tunnel1_vgw_inside_address" { value = module.vpn_poc.tunnel1_vgw_inside_address }
output "amazon_side_asn" { value = module.vpn_poc.amazon_side_asn }
