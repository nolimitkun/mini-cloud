# Azure landing-zone stack: Tier-2 hub + workload spokes. Run after policy/.

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
  # backend "azurerm" { ... }  # TODO: remote state
}

provider "azurerm" {
  features {}
  # subscription_id = connectivity subscription  # TODO
}

variable "express_route_circuit_id" {
  description = "ExpressRoute circuit id (ordered out-of-band, private peering only, doc 03 §4)."
  type        = string
}

locals {
  location = "westeurope"
  tags     = { project = "hybrid-cloud", tier = "landing-zone", cloud = "azure" }
}

module "hub" {
  source                   = "../../modules/azure-hub"
  location                 = local.location
  hub_cidr                 = "10.32.0.0/20"
  express_route_circuit_id = var.express_route_circuit_id
  tags                     = local.tags
}

module "spoke" {
  source = "../../modules/azure-spoke"
  for_each = {
    prod    = "10.32.16.0/20"
    nonprod = "10.32.32.0/20"
    shared  = "10.32.48.0/20"
  }
  name                = each.key
  location            = local.location
  spoke_cidr          = each.value
  hub_vnet_id         = module.hub.hub_vnet_id
  hub_vnet_name       = module.hub.hub_vnet_name
  hub_resource_group  = module.hub.resource_group_name
  firewall_private_ip = module.hub.firewall_private_ip
  tags                = local.tags
}
