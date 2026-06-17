variable "location" {
  type    = string
  default = "westeurope"
}

variable "vnet_cidr" {
  type    = string
  default = "10.32.0.0/24" # from the Azure supernet (doc 02 §1)
}

variable "onprem_public_ip" {
  type        = string
  description = "Public (WAN/NAT) IP of the on-prem strongSwan host."
}

variable "onprem_lan_cidr" {
  type    = string
  default = "192.168.1.0/24"
}

variable "shared_secret" {
  type        = string
  sensitive   = true
  description = "IPsec pre-shared key (must match strongSwan)."
}
