# Single notification target for every alert in this layer. Keeping one action group means a new
# channel (Teams webhook, PagerDuty, SMS) is added in exactly one place.
resource "azurerm_monitor_action_group" "oncall" {
  name                = "ag-${var.project}-oncall"
  resource_group_name = data.azurerm_resource_group.shared.name
  short_name          = "uniqa-oncall" # <= 12 chars, shown in SMS/e-mail subjects
  tags                = local.tags

  email_receiver {
    name                    = var.alert_email_receiver_name
    email_address           = var.alert_email
    use_common_alert_schema = true # uniform JSON payload across metric/log/activity alerts
  }
}
