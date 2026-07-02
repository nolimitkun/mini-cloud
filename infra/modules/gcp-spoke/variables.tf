variable "name" {
  type        = string
  description = "Spoke name (prod, nonprod, shared)."

  validation {
    condition     = contains(["prod", "nonprod", "shared"], var.name)
    error_message = "name must be one of: prod, nonprod, shared."
  }
}
variable "service_project_id" {
  type        = string
  description = "Workload service project to attach to the Shared VPC host."
}

variable "host_project_id" {
  type        = string
  description = "Shared VPC host project (the cloud hub)."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "host_network_name" {
  type        = string
  description = "Hub VPC network name (the Shared VPC host network) for subnet placement."
}

variable "spoke_cidr" {
  type        = string
  description = "Spoke /20 from the private IPAM plane (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.spoke_cidr, 0)) && can(regex("/20$", var.spoke_cidr))
    error_message = "spoke_cidr must be a valid IPv4 CIDR with a /20 prefix, e.g. 10.48.16.0/20."
  }
}

variable "crosscloud_cidr" {
  type        = string
  description = "Cross-cloud /24 from the 172.16.0.0/12 plane (doc 02 §1.2)."

  validation {
    condition     = can(cidrhost(var.crosscloud_cidr, 0)) && can(regex("/24$", var.crosscloud_cidr))
    error_message = "crosscloud_cidr must be a valid IPv4 CIDR with a /24 prefix, e.g. 172.19.16.0/24."
  }
}
