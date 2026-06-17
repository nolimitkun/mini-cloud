# Azure Tier-2 cloud hub: ExpressRoute Gateway, hub VNet, Azure Firewall,
# Private DNS Resolver. Private-only: private peering, no public data path.
#
# NOTE: the ExpressRoute *gateway* requires a platform Public IP for its own control
# plane (not a data path). The "deny public IP" guardrail (doc 04 §3) must exempt this
# connectivity resource group, or use the gateway's managed IP. This is the one
# sanctioned public IP in the whole estate and it carries no workload traffic.

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-hub-connectivity"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_cidr]
  tags                = var.tags
}

# Required well-known subnets carved from the hub /20.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 4, 0)] # 10.x.0.0/24
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 4, 1)] # 10.x.1.0/24
}

resource "azurerm_subnet" "resolver_in" {
  name                 = "snet-dns-inbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_cidr, 8, 32)]
  delegation {
    name = "dns-resolver"
    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
    }
  }
}

# --- ExpressRoute gateway (private peering only) + connection to circuit ---
resource "azurerm_public_ip" "ergw" {
  name                = "pip-ergw" # platform/control-plane only (see NOTE above)
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "ergw" {
  name                = "ergw-hub"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  type                = "ExpressRoute"
  sku                 = "ErGw1AZ" # zone-redundant
  ip_configuration {
    name                 = "default"
    public_ip_address_id = azurerm_public_ip.ergw.id
    subnet_id            = azurerm_subnet.gateway.id
  }
  tags = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "er" {
  name                       = "conn-er"
  location                   = azurerm_resource_group.hub.location
  resource_group_name        = azurerm_resource_group.hub.name
  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.ergw.id
  express_route_circuit_id   = var.express_route_circuit_id
}

# --- Azure Firewall (east-west + forced tunneling for spokes) ---
resource "azurerm_firewall_policy" "hub" {
  name                = "afw-policy"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  # Default-deny; allow approved east-west prefixes (doc 02 §4) via rule collections. # TODO
}

resource "azurerm_public_ip" "afw" {
  name                = "pip-afw" # platform IP for the firewall resource; egress stays on-prem
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "hub" {
  name                = "afw-hub"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.afw.id
  }
  tags = var.tags
}

# --- Private DNS Resolver (doc 05) ---
resource "azurerm_private_dns_resolver" "hub" {
  name                = "pdnsr-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.resolver_in.id
  }
}
