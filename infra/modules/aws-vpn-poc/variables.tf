variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.16.0.0/24" # from the AWS supernet (doc 02 §1)
}

variable "subnet_cidr" {
  type    = string
  default = "10.16.0.0/25"
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
  description = "Pre-shared key for both tunnels (8-64 chars; must match strongSwan)."
}

variable "onprem_asn" {
  type    = number
  default = 65000
}

variable "amazon_side_asn" {
  type    = number
  default = 65010
}
