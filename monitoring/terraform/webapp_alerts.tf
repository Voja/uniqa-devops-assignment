# Metric alerts on each Linux Web App: errors (5xx), latency (response time) and platform health
# (the /health probe configured as health_check_path by the application root).

locals {
  webapp_alerts = {
    http-5xx = {
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = 5
      window      = "PT5M"
      severity    = 1
      description = "More than 5 HTTP 5xx responses in 5 minutes - application errors."
    }
    response-time = {
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 2 # seconds
      window      = "PT15M"
      severity    = 2
      description = "Average response time above 2 s for 15 minutes - latency regression or SQL slowness."
    }
    health-check = {
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 100 # percent of instances healthy
      window      = "PT5M"
      severity    = 1
      description = "Health check (/health) failing on at least one instance."
    }
  }

  webapp_alert_instances = {
    for pair in setproduct(local.envs, keys(local.webapp_alerts)) :
    "${pair[0]}/${pair[1]}" => merge(local.webapp_alerts[pair[1]], { env = pair[0], alert = pair[1] })
  }
}

resource "azurerm_monitor_metric_alert" "webapp" {
  for_each = local.webapp_alert_instances

  name                = "app-${each.value.env}-${each.value.alert}"
  resource_group_name = data.azurerm_resource_group.shared.name
  scopes              = [data.azurerm_linux_web_app.env[each.value.env].id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT5M"
  window_size         = each.value.window
  auto_mitigate       = true
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.oncall.id
  }
}
