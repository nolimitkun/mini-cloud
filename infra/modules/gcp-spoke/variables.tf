variable "name" {
  type        = string
  description = "Spoke name (prod, nonprod, shared)."
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

variable "spoke_cidr" {
  type        = string
  description = "Spoke /20 from the private IPAM plane (doc 02 §1.2)."
}

variable "crosscloud_cidr" {
  type        = string
  description = "Cross-cloud /24 from the 172.16.0.0/12 plane (doc 02 §1.2)."
}
