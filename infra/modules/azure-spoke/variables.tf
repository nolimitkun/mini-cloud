variable "name" {
  type        = string
  description = "Spoke name (prod, nonprod, shared)."
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "spoke_cidr" {
  type        = string
  description = "Spoke /20 from the private IPAM plane (doc 02 §1.2)."
}

variable "crosscloud_cidr" {
  type        = string
  description = "Cross-cloud /24 from the 172.16.0.0/12 plane (doc 02 §1.2)."
}

variable "hub_vnet_id" {
  type        = string
  description = "Hub VNet id (from azure-hub module) for peering."
}

variable "hub_vnet_name" {
  type = string
}

variable "hub_resource_group" {
  type = string
}

variable "firewall_private_ip" {
  type        = string
  description = "Azure Firewall private IP — UDR default-route next hop."
}

variable "tags" {
  type    = map(string)
  default = {}
}
