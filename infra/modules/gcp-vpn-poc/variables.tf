variable "project_id" {
  type        = string
  description = "GCP project for the PoC."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.48.0.0/24" # from the GCP supernet (doc 02 §1)
  description = "Hub subnet for the PoC VPC."
}

variable "onprem_public_ip" {
  type        = string
  description = "Public (WAN/NAT) IP of the on-prem strongSwan host — the VPN peer."
}

variable "onprem_lan_cidr" {
  type        = string
  default     = "192.168.1.0/24"
  description = "On-prem LAN range allowed in over the tunnel. Set to your real LAN."
}

variable "shared_secret" {
  type        = string
  sensitive   = true
  description = "IPsec pre-shared key (must match strongSwan secrets)."
}

variable "onprem_asn" {
  type    = number
  default = 65000
}

variable "cloud_router_asn" {
  type    = number
  default = 65020
}

variable "bgp_gcp_ip" {
  type    = string
  default = "169.254.0.1"
}

variable "bgp_onprem_ip" {
  type    = string
  default = "169.254.0.2"
}
