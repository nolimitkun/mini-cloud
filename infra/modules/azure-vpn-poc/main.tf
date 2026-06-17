# Azure VPN PoC: route-based VPN Gateway to an on-prem strongSwan peer.
# Static routing (on-prem LAN as the local network gateway address space) keeps the
# PoC simple — Azure BGP-over-VPN uses APIPA peers and can be added later.
# Matches the GCP PoC pattern (doc 08).

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

resource "azurerm_resource_group" "poc" {
  name     = "rg-vpn-poc"
  location = var.location
}

resource "azurerm_virtual_network" "poc" {
  name                = "vnet-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.poc.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 0)] # 10.32.0.0/27
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.poc.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 1)] # 10.32.0.32/27
}

resource "azurerm_public_ip" "gw" {
  name                = "pip-vpngw-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "vpngw" {
  name                = "vpngw-poc"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1"
  ip_configuration {
    name                          = "default"
    public_ip_address_id          = azurerm_public_ip.gw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}

resource "azurerm_local_network_gateway" "onprem" {
  name                = "lng-onprem"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  gateway_address     = var.onprem_public_ip
  address_space       = [var.onprem_lan_cidr] # static routing
}

resource "azurerm_virtual_network_gateway_connection" "onprem" {
  name                       = "conn-onprem"
  location                   = azurerm_resource_group.poc.location
  resource_group_name        = azurerm_resource_group.poc.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpngw.id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem.id
  shared_key                 = var.shared_secret
}

# Allow only on-prem LAN in.
resource "azurerm_network_security_group" "from_lan" {
  name                = "nsg-from-onprem-lan"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  security_rule {
    name                       = "allow-onprem-lan"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.onprem_lan_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.from_lan.id
}
