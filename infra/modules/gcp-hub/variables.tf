variable "project_id" {
  type        = string
  description = "Host project (Shared VPC) = the Tier-2 hub."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "hub_cidr" {
  type        = string # e.g. 10.48.0.0/20
  description = "Cloud hub /20 from the IPAM plan (doc 02 §1.2)."
}

variable "cloud_router_asn" {
  type    = number
  default = 65020 # doc 02 §3
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
