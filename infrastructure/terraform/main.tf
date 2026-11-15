# ---------------------------------------------------------------------------
# 1. Per-environment database on the EXISTING shared SQL Server
# ---------------------------------------------------------------------------
resource "azurerm_mssql_database" "main" {
  name           = local.db_name
  server_id      = data.azurerm_mssql_server.shared.id # existing server, we only add a DB
  sku_name       = var.sql_database_sku
  max_size_gb    = var.sql_database_max_size_gb
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  zone_redundant = false # not available/needed on Basic tier
  tags           = local.tags

  # Collation cannot be changed in place; ignoring it prevents a destructive replace on drift.
  lifecycle {
    ignore_changes = [collation]
  }
}

# ---------------------------------------------------------------------------
# 2. Application Insights (workspace-based) for request/dependency telemetry
# ---------------------------------------------------------------------------
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.name_prefix}"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
  application_type    = "web"
  workspace_id        = data.azurerm_log_analytics_workspace.shared.id # store telemetry in the shared LAW
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 3. Linux Web App on the EXISTING App Service Plan
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "main" {
  name = local.app_name
  # Kept in the shared RG for simplicity of this assessment; in production the app would get its
  # own RG so environment lifecycle (and RBAC) is fully decoupled from the platform resources.
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
  service_plan_id     = data.azurerm_service_plan.shared.id # <-- the EXISTING Linux ASP
  https_only          = true                                # redirect HTTP -> HTTPS at the front end
  tags                = local.tags

  # System-assigned identity so the app can later authenticate to Azure services without secrets.
  identity {
    type = "SystemAssigned"
  }

  # The Private Endpoint below provides private ingress. Public access is INTENTIONALLY kept ON for
  # this assessment so the reviewer and the GitHub Actions deployment (Kudu/SCM) can reach the app
  # from the internet. In production set this to false and deploy from a self-hosted runner in the VNet.
  public_network_access_enabled = true

  # VNet Integration (outbound): app traffic egresses through the delegated subnet.
  virtual_network_subnet_id = data.azurerm_subnet.integration.id

  site_config {
    always_on                         = true       # keep the worker warm; required for reliable health checks
    ftps_state                        = "Disabled" # no FTP deployment surface
    minimum_tls_version               = "1.2"
    http2_enabled                     = true
    health_check_path                 = "/health" # the Flask endpoint; unhealthy instances are recycled
    health_check_eviction_time_in_min = 10        # minutes unhealthy before the instance is recycled
    vnet_route_all_enabled            = true      # send ALL outbound traffic (not just RFC1918) via the VNet
    app_command_line                  = "gunicorn --bind=0.0.0.0:8000 --workers=2 --timeout 120 app:app"

    application_stack {
      python_version = var.python_version
    }
  }

  # Application Settings: defaults first, environment-specific overrides from tfvars merged on top.
  app_settings = merge(
    {
      APP_ENV                                    = var.environment
      APP_VERSION                                = "0.1.0"
      SCM_DO_BUILD_DURING_DEPLOYMENT             = "true" # Oryx builds requirements.txt on zip deploy
      WEBSITES_PORT                              = "8000"
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.main.connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3" # codeless App Insights agent
    },
    var.app_settings,
  )

  # Connection String of type SQLServer; App Service exposes it to the process as the environment
  # variable SQLCONNSTR_TransactionsDb, which is exactly what application/app.py reads.
  connection_string {
    name  = "TransactionsDb"
    type  = "SQLServer"
    value = "Server=tcp:${data.azurerm_mssql_server.shared.fully_qualified_domain_name},1433;Database=${local.db_name};Uid=${var.sql_admin_login};Pwd=${var.sql_admin_password};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  }

  # Platform logs on the local file system (short retention); long-term logs go to LAW via diagnostics.
  logs {
    detailed_error_messages = true # keep HTTP 4xx/5xx detail pages for troubleshooting (CKV_AZURE_65)
    failed_request_tracing  = true # capture failed-request traces (CKV_AZURE_66)
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Information"
    }
  }

  # The CD pipeline stamps APP_VERSION at deploy time; Terraform must not revert it on the next apply.
  lifecycle {
    ignore_changes = [app_settings["APP_VERSION"]]
  }
}

# ---------------------------------------------------------------------------
# 4. Private Endpoint (inbound): the app gets a private IP inside the VNet
# ---------------------------------------------------------------------------
resource "azurerm_private_endpoint" "webapp" {
  name                = "pe-${local.app_name}"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
  subnet_id           = data.azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${local.app_name}"
    private_connection_resource_id = azurerm_linux_web_app.main.id
    subresource_names              = ["sites"] # the web app itself (not "sites-<slot>" / scm)
    is_manual_connection           = false
  }

  # Registers the A record in privatelink.azurewebsites.net so VNet clients resolve the private IP.
  private_dns_zone_group {
    name                 = "webapp-dns-zone-group"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.webapp.id]
  }
}

# ---------------------------------------------------------------------------
# 5. Diagnostic settings: ship platform logs and metrics to Log Analytics
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "webapp" {
  name                       = "diag-${local.app_name}"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.shared.id

  enabled_log {
    category = "AppServiceHTTPLogs" # access log: status codes, latency
  }
  enabled_log {
    category = "AppServiceConsoleLogs" # stdout/stderr from gunicorn
  }
  enabled_log {
    category = "AppServiceAppLogs" # application-level log records
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
