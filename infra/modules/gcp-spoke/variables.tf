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
  description = "Spoke /20 from the IPAM plan (doc 02 §1.2)."
}
