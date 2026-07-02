variable "project_id" {
  type        = string
  description = "Host project (Shared VPC) = the Tier-2 hub."

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 chars, start with a letter, contain only lowercase letters, digits, and hyphens."
  }
}
variable "region" {
  type    = string
  default = "europe-west1"
}

variable "hub_cidr" {
  type        = string # e.g. 10.48.0.0/20
  description = "Cloud hub /20 from the IPAM plan (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.hub_cidr, 0)) && can(regex("/20$", var.hub_cidr))
    error_message = "hub_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.48.0.0/20."
  }
}

variable "cloud_router_asn" {
  type    = number
  default = 65020 # doc 02 §3

  validation {
    condition     = var.cloud_router_asn >= 64512 && var.cloud_router_asn <= 65534
    error_message = "cloud_router_asn must be a private ASN in the range 64512-65534."
  }
}

variable "interconnect_attachment_names" {
  type        = list(string)
  description = "VLAN attachment names for the two Dedicated Interconnect circuits (ordered out-of-band)."
  default     = ["ic-attach-a", "ic-attach-b"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
