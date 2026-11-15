# This root creates NO application or platform resources: it only reads the ones provisioned by
# infrastructure/terraform (bootstrap + application) and attaches monitoring to them.

locals {
  envs = toset(var.environments)

  # Names must match infrastructure/terraform/locals.tf exactly.
  db_name   = { for e in local.envs : e => "sqldb-${var.project}-${e}" }
  app_name  = { for e in local.envs : e => "app-${var.project}-${e}-${var.app_name_suffix}" }
  appi_name = { for e in local.envs : e => "appi-${var.project}-${e}" }

  tags = merge(
    {
      project    = var.project
      managed_by = "terraform"
      layer      = "monitoring"
    },
    var.tags,
  )
}

# Everything monitored lives in the shared resource group (see application root for the rationale).
data "azurerm_resource_group" "shared" {
  name = var.shared_resource_group_name
}

# The EXISTING SQL Server from the assignment bonus ("monitor an existing SQL Server").
data "azurerm_mssql_server" "shared" {
  name                = var.sql_server_name
  resource_group_name = data.azurerm_resource_group.shared.name
}

# One database per environment on that server; metric alerts are scoped per database.
data "azurerm_mssql_database" "env" {
  for_each  = local.envs
  name      = local.db_name[each.key]
  server_id = data.azurerm_mssql_server.shared.id
}

# The Linux Web Apps deployed by the application root.
data "azurerm_linux_web_app" "env" {
  for_each            = local.envs
  name                = local.app_name[each.key]
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Application Insights components (telemetry sink for requests/dependencies and availability tests).
data "azurerm_application_insights" "env" {
  for_each            = local.envs
  name                = local.appi_name[each.key]
  resource_group_name = data.azurerm_resource_group.shared.name
}

# Central Log Analytics workspace; referenced in outputs/README for KQL queries.
data "azurerm_log_analytics_workspace" "shared" {
  name                = "log-${var.project}"
  resource_group_name = data.azurerm_resource_group.shared.name
}
