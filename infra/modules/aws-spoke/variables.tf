variable "name" {
  description = "Spoke name (e.g. prod, nonprod, shared)."
  type        = string
}

variable "spoke_cidr" {
  description = "Spoke /20 from the IPAM plan (doc 02 §1.2)."
  type        = string
}

variable "transit_gateway_id" {
  description = "Tier-2 hub TGW id (from aws-hub module)."
  type        = string
}

variable "azs" {
  description = "Availability zones for HA subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
