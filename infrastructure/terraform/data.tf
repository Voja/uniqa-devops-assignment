# This file READS the pre-existing shared infrastructure (bootstrap layer) instead of creating it.
# That is the core of the assignment: deploy an App Service onto an EXISTING Linux App Service Plan,
# wire it into an EXISTING VNet, and use an EXISTING SQL Server — without owning any of them.

# Shared resource group: everything in this environment is placed inside it (see main.tf for the note).
data "azurerm_resource_group" "shared" {
  name = var.shared_resource_group_name
}

# The EXISTING Linux App Service Plan the Web App will run on.
data "azurerm_service_plan" "shared" {
  name                = var.service_plan_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Delegated subnet for VNet Integration (outbound traffic from the app into the VNet).
data "azurerm_subnet" "integration" {
  name                 = var.integration_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = data.azurerm_resource_group.shared.name
}

# Subnet that hosts the Web App's Private Endpoint (inbound traffic from the VNet to the app).
data "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = data.azurerm_resource_group.shared.name
}

# Private DNS zone so the app's hostname resolves to the private endpoint IP from inside the VNet.
data "azurerm_private_dns_zone" "webapp" {
  name                = var.private_dns_zone_webapp_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# The EXISTING SQL Server; we only add a per-environment database to it.
data "azurerm_mssql_server" "shared" {
  name                = var.sql_server_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Central Log Analytics workspace that receives diagnostics and Application Insights telemetry.
data "azurerm_log_analytics_workspace" "shared" {
  name                = var.log_analytics_workspace_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Public DNS zone where the custom-domain records are created.
data "azurerm_dns_zone" "public" {
  name                = var.dns_zone_name
  resource_group_name = data.azurerm_resource_group.shared.name
}
