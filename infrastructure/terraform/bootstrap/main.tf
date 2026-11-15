locals {
  tags = {
    project    = var.project
    managed_by = "terraform"
    layer      = "bootstrap"
  }
}

# Random suffixes for globally-unique names (SQL Server, storage account).
resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# 1. Resource group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "shared" {
  name     = "rg-${var.project}-shared"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# 2. Shared Linux App Service Plan ("existing plan" the app environments reuse)
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "linux" {
  name                = "asp-${var.project}-linux"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  os_type             = "Linux"
  sku_name            = var.asp_sku
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 3. Virtual network + subnets
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  address_space       = ["10.10.0.0/16"]
  tags                = local.tags
}

# Outbound: App Service VNet Integration requires a delegated subnet.
resource "azurerm_subnet" "appsvc_integration" {
  name                 = "snet-appsvc-integration"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]

  delegation {
    name = "appsvc-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Inbound: Private Endpoints for SQL Server and Web Apps live here.
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.shared.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.2.0/24"]
}

# ---------------------------------------------------------------------------
# 4. Private DNS zones (resolved from inside the VNet)
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "webapp" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapp" {
  name                  = "link-${var.project}-webapp"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.webapp.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "link-${var.project}-sql"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.tags
}

# ---------------------------------------------------------------------------
# 5. Shared Azure SQL Server ("existing SQL Server" for the monitoring bonus)
# ---------------------------------------------------------------------------
resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_mssql_server" "main" {
  name                         = "sql-${var.project}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.shared.name
  location                     = azurerm_resource_group.shared.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"
  # Public access stays on but is restricted to the admin IP by the firewall
  # rule below; application traffic uses the private endpoint.
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_mssql_firewall_rule" "allow_admin_ip" {
  name             = "allow-admin-ip"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = var.admin_client_ip
  end_ip_address   = var.admin_client_ip
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${azurerm_mssql_server.main.name}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${azurerm_mssql_server.main.name}"
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

# ---------------------------------------------------------------------------
# 6. Log Analytics workspace (central sink for diagnostics / App Insights)
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project}"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 7. Public DNS zone for custom domains (delegate NS at the registrar)
# ---------------------------------------------------------------------------
resource "azurerm_dns_zone" "public" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 8. Remote state backend for the per-environment Terraform root
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.project}tfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.shared.name
  location                        = azurerm_resource_group.shared.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
