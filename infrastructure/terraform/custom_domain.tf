# Custom domain <environment>.<dns_zone_name> with a free App Service managed certificate.
# Everything here is gated by var.enable_custom_domain because it only works once the public zone's
# nameservers have been delegated at the registrar (manual step documented in bootstrap/README.md).

# Domain-ownership proof: App Service checks asuid.<host> TXT == custom_domain_verification_id.
resource "azurerm_dns_txt_record" "asuid" {
  count = var.enable_custom_domain ? 1 : 0

  name                = "asuid.${var.environment}"
  zone_name           = data.azurerm_dns_zone.public.name
  resource_group_name = data.azurerm_resource_group.shared.name
  ttl                 = 300
  tags                = local.tags

  record {
    value = azurerm_linux_web_app.main.custom_domain_verification_id
  }
}

# Points <environment>.<zone> at the app's default *.azurewebsites.net hostname.
resource "azurerm_dns_cname_record" "app" {
  count = var.enable_custom_domain ? 1 : 0

  name                = var.environment
  zone_name           = data.azurerm_dns_zone.public.name
  resource_group_name = data.azurerm_resource_group.shared.name
  ttl                 = 300
  record              = azurerm_linux_web_app.main.default_hostname
  tags                = local.tags
}

# Binds the hostname to the Web App; both DNS records must exist first or validation fails.
resource "azurerm_app_service_custom_hostname_binding" "main" {
  count = var.enable_custom_domain ? 1 : 0

  hostname            = local.custom_hostname
  app_service_name    = azurerm_linux_web_app.main.name
  resource_group_name = data.azurerm_resource_group.shared.name

  depends_on = [
    azurerm_dns_txt_record.asuid,
    azurerm_dns_cname_record.app,
  ]

  # The certificate binding below mutates ssl_state/thumbprint on this resource out-of-band;
  # without this the provider would try to "fix" them back on every plan (known quirk).
  lifecycle {
    ignore_changes = [ssl_state, thumbprint]
  }
}

# Free, auto-renewing App Service managed certificate for the bound hostname.
resource "azurerm_app_service_managed_certificate" "main" {
  count = var.enable_custom_domain ? 1 : 0

  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.main[0].id
  tags                       = local.tags
}

# Attaches the certificate to the hostname binding (SNI, no dedicated IP needed).
resource "azurerm_app_service_certificate_binding" "main" {
  count = var.enable_custom_domain ? 1 : 0

  hostname_binding_id = azurerm_app_service_custom_hostname_binding.main[0].id
  certificate_id      = azurerm_app_service_managed_certificate.main[0].id
  ssl_state           = "SniEnabled"
}
