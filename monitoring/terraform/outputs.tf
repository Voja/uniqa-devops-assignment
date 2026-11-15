output "action_group_id" {
  description = "Action group that receives every alert (attach more receivers here)."
  value       = azurerm_monitor_action_group.oncall.id
}

output "sql_alert_names" {
  description = "Metric alerts on the existing SQL Server's databases."
  value       = sort([for a in azurerm_monitor_metric_alert.sql : a.name])
}

output "webapp_alert_names" {
  description = "Metric alerts on the Web Apps."
  value       = sort([for a in azurerm_monitor_metric_alert.webapp : a.name])
}

output "availability_alert_names" {
  description = "Alerts on the external availability tests."
  value       = sort([for a in azurerm_monitor_metric_alert.availability : a.name])
}

output "web_test_ids" {
  description = "Application Insights standard web test IDs per environment."
  value       = { for e, t in azurerm_application_insights_standard_web_test.health : e => t.id }
}

output "log_analytics_workspace_id" {
  description = "Workspace to run the KQL files in monitoring/queries/ against."
  value       = data.azurerm_log_analytics_workspace.shared.id
}
