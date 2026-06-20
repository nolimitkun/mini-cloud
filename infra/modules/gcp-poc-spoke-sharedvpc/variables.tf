variable "spoke_project_id" {
  type    = string
  default = "mini-cloud-lakehouse"
}

variable "billing_account" {
  type = string
}

variable "org_id" {
  type        = string
  description = "GCP organization id (required — Shared VPC needs both projects in an org)."
}

variable "create_project" {
  type    = bool
  default = true
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "spoke_cidr" {
  type        = string
  default     = "10.48.16.0/24"
  description = "Spoke workload subnet, created in the HOST (hub) VPC."
}

variable "host_project_id" {
  type        = string
  description = "Shared VPC host project (the hub)."
}

variable "host_network_name" {
  type        = string
  description = "Hub VPC name (host network) to create the spoke subnet in."
}
