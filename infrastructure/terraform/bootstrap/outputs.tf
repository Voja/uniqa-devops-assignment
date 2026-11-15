output "resource_group_name" {
  value = azurerm_resource_group.shared.name
}

output "location" {
  value = azurerm_resource_group.shared.location
}

output "service_plan_name" {
  value = azurerm_service_plan.linux.name
}

output "service_plan_id" {
  value = azurerm_service_plan.linux.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "integration_subnet_id" {
  value = azurerm_subnet.appsvc_integration.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_webapp_id" {
  value = azurerm_private_dns_zone.webapp.id
}

output "private_dns_zone_sql_id" {
  value = azurerm_private_dns_zone.sql.id
}

output "sql_server_name" {
  value = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_admin_login" {
  value = azurerm_mssql_server.main.administrator_login
}

output "sql_admin_password" {
  value     = random_password.sql_admin.result
  sensitive = true
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "dns_zone_name" {
  value = azurerm_dns_zone.public.name
}

output "dns_zone_name_servers" {
  value = azurerm_dns_zone.public.name_servers
}

output "tfstate_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  value = azurerm_storage_container.tfstate.name
}
