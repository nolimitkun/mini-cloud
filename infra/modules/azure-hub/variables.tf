variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region for this landing zone (doc D3)."

  validation {
    condition     = length(var.location) > 0
    error_message = "location must not be empty."
  }
}

variable "hub_cidr" {
  type        = string # e.g. 10.32.0.0/20
  description = "Cloud hub /20 from the IPAM plan (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.hub_cidr, 0)) && can(regex("/20$", var.hub_cidr))
    error_message = "hub_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.32.0.0/20."
  }
}

variable "express_route_circuit_id" {
  type        = string
  description = "Existing ExpressRoute circuit id (ordered out-of-band, private peering only)."

  validation {
    condition     = can(regex("^/subscriptions/", var.express_route_circuit_id))
    error_message = "express_route_circuit_id must be a full Azure resource ID starting with /subscriptions/."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
