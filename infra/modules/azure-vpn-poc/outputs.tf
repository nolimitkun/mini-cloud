output "vpn_gateway_public_ip" {
  description = "Azure VPN gateway public IP — strongSwan remote peer."
  value       = azurerm_public_ip.gw.ip_address
}

output "vnet_cidr" {
  description = "VNet range reachable over the tunnel (remote_ts for strongSwan)."
  value       = var.vnet_cidr
}
