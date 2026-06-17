variable "region" {
  description = "Single region for this landing zone (doc D3)."
  type        = string
  default     = "eu-west-1"
}

variable "cloud_supernet" {
  description = "This cloud's /12 supernet (e.g. 10.16.0.0/12)."
  type        = string
}

variable "hub_cidr" {
  description = "Cloud hub /20 (connectivity, firewall, DNS, endpoints)."
  type        = string
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
}

variable "dx_connection_id" {
  description = "Existing Dedicated Direct Connect connection id (ordered out-of-band)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
