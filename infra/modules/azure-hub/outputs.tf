output "hub_vnet_id" {
  description = "Hub VNet id for spoke peering."
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "resource_group_name" {
  value = azurerm_resource_group.hub.name
}

output "firewall_private_ip" {
  description = "Azure Firewall private IP — spoke UDR 0.0.0.0/0 next hop (doc 02 §3.4)."
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}
