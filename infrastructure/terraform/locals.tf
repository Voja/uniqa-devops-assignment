# All derived names live here so main.tf reads as pure resource wiring.
locals {
  # Common "<project>-<env>" prefix for resources that only need to be unique within the subscription.
  name_prefix = "${var.project}-${var.environment}"

  # Web App name is a global DNS label (*.azurewebsites.net), hence the extra personal suffix.
  app_name = "app-${var.project}-${var.environment}-${var.app_name_suffix}"

  # Custom hostname per environment, e.g. dev.stefanovic-devops.xyz.
  custom_hostname = "${var.environment}.${var.dns_zone_name}"

  # One database per environment on the shared SQL Server.
  db_name = "sqldb-${var.project}-${var.environment}"

  # Default tags; caller-supplied tags are merged on top (and can override).
  tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
      layer       = "application"
    },
    var.tags,
  )
}
