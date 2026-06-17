variable "location" {
  type    = string
  default = "westeurope"
}

variable "hub_cidr" {
  type        = string # e.g. 10.32.0.0/20
  description = "Cloud hub /20 from the IPAM plan (doc 02 §1.2)."
}

variable "express_route_circuit_id" {
  type        = string
  description = "Existing ExpressRoute circuit id (ordered out-of-band, private peering only)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
