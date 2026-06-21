output "resource_group_name" {
  description = "Spoke resource group name."
  value       = azurerm_resource_group.spoke.name
}

output "vnet_id" {
  description = "Spoke VNet ID."
  value       = azurerm_virtual_network.spoke.id
}

output "vnet_name" {
  description = "Spoke VNet name."
  value       = azurerm_virtual_network.spoke.name
}

output "workload_subnet_id" {
  description = "Workload subnet ID."
  value       = azurerm_subnet.workload.id
}

output "crosscloud_subnet_id" {
  description = "Cross-cloud subnet ID."
  value       = azurerm_subnet.crosscloud.id
}
