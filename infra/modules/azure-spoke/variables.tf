variable "name" {
  type        = string
  description = "Spoke name (prod, nonprod, shared)."

  validation {
    condition     = contains(["prod", "nonprod", "shared"], var.name)
    error_message = "name must be one of: prod, nonprod, shared."
  }
}
variable "location" {
  type    = string
  default = "westeurope"
}

variable "spoke_cidr" {
  type        = string
  description = "Spoke /20 from the private IPAM plane (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.spoke_cidr, 0)) && can(regex("/20$", var.spoke_cidr))
    error_message = "spoke_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.32.16.0/20."
  }
}

variable "crosscloud_cidr" {
  type        = string
  description = "Cross-cloud /24 from the 172.16.0.0/12 plane (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.crosscloud_cidr, 0)) && can(regex("/24$", var.crosscloud_cidr))
    error_message = "crosscloud_cidr must be a valid IPv4 CIDR with a /24 prefix, e.g. 172.18.16.0/24."
  }
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
