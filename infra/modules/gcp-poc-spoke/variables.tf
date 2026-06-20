variable "spoke_project_id" {
  type        = string
  default     = "mini-cloud-lakehouse"
  description = "Project id for the spoke (created if create_project = true)."
}

variable "billing_account" {
  type        = string
  description = "Billing account id to link the spoke project to."
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
  default     = "10.48.16.0/24" # spoke subnet, from the GCP private /12
  description = "Spoke VPC subnet (must not overlap hub 10.48.0.0/24 or 192.168.50.0/24)."
}

variable "hub_network" {
  type        = string
  description = "Self-link of the hub VPC (vpc-poc) to peer with."
}

variable "onprem_lan_cidr" {
  type    = string
  default = "192.168.1.0/24"
}
