# External availability: Application Insights standard web tests probe /health over the public
# custom domain from three regions every 5 minutes. This observes the FULL path (DNS, TLS cert,
# App Service front end, app, implicit SQL access) from outside Azure, unlike platform metrics.

resource "azurerm_application_insights_standard_web_test" "health" {
  for_each = local.envs

  name                    = "avail-${each.key}-health"
  resource_group_name     = data.azurerm_resource_group.shared.name
  location                = data.azurerm_application_insights.env[each.key].location # must match the component
  application_insights_id = data.azurerm_application_insights.env[each.key].id
  geo_locations           = ["emea-nl-ams-azr", "emea-fr-pra-edge", "us-va-ash-azr"] # Amsterdam, Paris, Virginia
  frequency               = 300                                                      # seconds between runs from each location
  timeout                 = 30                                                       # seconds before a run counts as failed
  enabled                 = true
  retry_enabled           = true # one automatic retry filters transient network blips
  description             = "GET /health on ${each.key} must return 200 with status=ok."
  tags                    = local.tags

  request {
    url                              = "https://${each.key}.${var.dns_zone_name}/health"
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false # plain JSON endpoint, nothing to parse
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true # fail if the managed certificate is invalid ...
    ssl_cert_remaining_lifetime = 7    # ... or expires within 7 days (managed cert auto-renews earlier)

    content {
      content_match      = "\"status\":\"ok\""
      pass_if_text_found = true
      ignore_case        = true
    }
  }
}

# Fire when the probe fails from at least 2 of the 3 locations (a single location failing is
# usually a regional network issue, not an outage).
resource "azurerm_monitor_metric_alert" "availability" {
  for_each = local.envs

  name                = "avail-${each.key}-failed"
  resource_group_name = data.azurerm_resource_group.shared.name
  # Web-test alerts must be scoped to both the test and its App Insights component.
  scopes = [
    azurerm_application_insights_standard_web_test.health[each.key].id,
    data.azurerm_application_insights.env[each.key].id,
  ]
  description   = "${each.key}: /health unreachable from 2+ regions - service down for end users."
  severity      = 1
  frequency     = "PT5M"
  window_size   = "PT5M"
  auto_mitigate = true
  tags          = local.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health[each.key].id
    component_id          = data.azurerm_application_insights.env[each.key].id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.oncall.id
  }
}
