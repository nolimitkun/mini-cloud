variable "name" {
  description = "Spoke name (e.g. prod, nonprod, shared)."
  type        = string

  validation {
    condition     = contains(["prod", "nonprod", "shared"], var.name)
    error_message = "name must be one of: prod, nonprod, shared."
  }
}
variable "spoke_cidr" {
  description = "Spoke /20 from the IPAM plan (doc 02 §1.2)."
  type        = string

  validation {
    condition     = can(cidrhost(var.spoke_cidr, 0)) && can(regex("/20$", var.spoke_cidr))
    error_message = "spoke_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.16.16.0/20."
  }
}

variable "transit_gateway_id" {
  description = "Tier-2 hub TGW id (from aws-hub module)."
  type        = string
}

variable "crosscloud_cidr" {
  description = "Cross-cloud /24 from the 172.16.0.0/12 plane (doc 02 §1.2)."
  type        = string

  validation {
    condition     = can(cidrhost(var.crosscloud_cidr, 0)) && can(regex("/24$", var.crosscloud_cidr))
    error_message = "crosscloud_cidr must be a valid IPv4 CIDR with a /24 prefix, e.g. 172.17.16.0/24."
  }
}

variable "azs" {
  description = "Availability zones for HA subnets."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
