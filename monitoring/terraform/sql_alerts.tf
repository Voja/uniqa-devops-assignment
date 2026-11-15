# Metric alerts on the per-environment databases of the EXISTING SQL Server.
# Signals: capacity (CPU, DTU, storage), reachability (failed connections) and contention (deadlocks).
# All evaluate every 5 minutes over a 15-minute window to smooth out short spikes.

locals {
  # One definition per alert; expanded per environment below.
  sql_alerts = {
    cpu-high = {
      metric      = "cpu_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      description = "Average CPU above 80% for 15 minutes - queries or tier undersized."
    }
    dtu-high = {
      metric      = "dtu_consumption_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      description = "DTU consumption above 80% - Basic tier is saturating, consider scaling."
    }
    storage-high = {
      metric      = "storage_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      description = "Database storage above 80% of the max size - inserts will start failing at 100%."
    }
    failed-connections = {
      metric      = "connection_failed"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = 5
      severity    = 1
      description = "More than 5 failed connections - firewall, credentials or private endpoint issue."
    }
    deadlocks = {
      metric      = "deadlock"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = 0
      severity    = 2
      description = "Any deadlock - transactions are being killed, investigate query patterns."
    }
  }

  # Cartesian product environments x alerts -> map keyed "env/alert".
  sql_alert_instances = {
    for pair in setproduct(local.envs, keys(local.sql_alerts)) :
    "${pair[0]}/${pair[1]}" => merge(local.sql_alerts[pair[1]], { env = pair[0], alert = pair[1] })
  }
}

resource "azurerm_monitor_metric_alert" "sql" {
  for_each = local.sql_alert_instances

  name                = "sql-${each.value.env}-${each.value.alert}"
  resource_group_name = data.azurerm_resource_group.shared.name
  scopes              = [data.azurerm_mssql_database.env[each.value.env].id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  auto_mitigate       = true # resolves automatically when the metric returns below threshold
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.oncall.id
  }
}
