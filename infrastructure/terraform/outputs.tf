# Consumed by the CD pipeline (app name for deployment) and by humans/evidence docs (URLs).

output "web_app_name" {
  description = "Name of the Linux Web App; the CD pipeline deploys to this."
  value       = azurerm_linux_web_app.main.name
}

output "web_app_default_hostname" {
  description = "Default *.azurewebsites.net hostname."
  value       = azurerm_linux_web_app.main.default_hostname
}

output "web_app_url" {
  description = "Public HTTPS URL of the app on the default hostname."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "custom_domain_url" {
  description = "HTTPS URL on the custom domain, or null when enable_custom_domain = false."
  value       = var.enable_custom_domain ? "https://${local.custom_hostname}" : null
}

output "private_endpoint_ip" {
  description = "Private IP of the Web App inside the VNet (private endpoint NIC)."
  value       = azurerm_private_endpoint.webapp.private_service_connection[0].private_ip_address
}

output "application_insights_name" {
  description = "Application Insights component name."
  value       = azurerm_application_insights.main.name
}

output "application_insights_connection_string" {
  description = "App Insights connection string (also injected into the app settings)."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "sql_database_name" {
  description = "Per-environment database created on the shared SQL Server."
  value       = azurerm_mssql_database.main.name
}

output "web_app_principal_id" {
  description = "Object ID of the Web App's system-assigned managed identity (for future RBAC grants)."
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}
