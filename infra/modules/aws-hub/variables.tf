variable "region" {
  description = "Single region for this landing zone (doc D3)."
  type        = string
  default     = "eu-west-1"
}

variable "cloud_supernet" {
  description = "This cloud's /12 supernet (e.g. 10.16.0.0/12)."
  type        = string

  validation {
    condition     = can(cidrhost(var.cloud_supernet, 0)) && can(regex("/12$", var.cloud_supernet))
    error_message = "cloud_supernet must be a valid IPv4 CIDR with a /12 prefix, e.g. 10.16.0.0/12."
  }
}

variable "hub_cidr" {
  description = "Cloud hub /20 (connectivity, firewall, DNS, endpoints)."
  type        = string

  validation {
    condition     = can(cidrhost(var.hub_cidr, 0)) && can(regex("/20$", var.hub_cidr))
    error_message = "hub_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.16.0.0/20."
  }
}

variable "onprem_supernet" {
  description = "On-prem supernet advertised from the hub side (10.0.0.0/12)."
  type        = string
  default     = "10.0.0.0/12"
}

variable "amazon_side_asn" {
  description = "Transit Gateway ASN (doc 02 §3)."
  type        = number
  default     = 65010

  validation {
    condition     = var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534
    error_message = "amazon_side_asn must be a private ASN in the range 64512-65534."
  }
}

variable "dx_connection_id" {
  description = "Existing Dedicated Direct Connect connection id (ordered out-of-band)."
  type        = string

  validation {
    condition     = can(regex("^dxcon-", var.dx_connection_id))
    error_message = "dx_connection_id must start with \"dxcon-\"."
  }
}

variable "firewall_azs" {
  description = "AZs for the Network Firewall endpoint subnets (one per AZ)."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
