# ---------------------------------------------------------------------------
# Identity / scope
# ---------------------------------------------------------------------------
variable "subscription_id" {
  description = "Azure subscription ID where the environment is deployed (pass via TF_VAR_subscription_id)."
  type        = string
}

variable "project" {
  description = "Short project name used as prefix in resource names and tags."
  type        = string
  default     = "uniqa"
}

variable "environment" {
  description = "Target environment; drives names, the state key and the custom sub-domain."
  type        = string

  validation {
    condition     = contains(["dev", "test"], var.environment)
    error_message = "environment must be either \"dev\" or \"test\"."
  }
}

variable "app_name_suffix" {
  description = "Suffix appended to the Web App name to make it globally unique on *.azurewebsites.net."
  type        = string
  default     = "stefanovic"
}

# ---------------------------------------------------------------------------
# References to EXISTING shared infrastructure (created by the bootstrap root)
# ---------------------------------------------------------------------------
variable "shared_resource_group_name" {
  description = "Resource group that holds the shared infrastructure (App Service Plan, VNet, SQL Server...)."
  type        = string
  default     = "rg-uniqa-shared"
}

variable "service_plan_name" {
  description = "Name of the EXISTING Linux App Service Plan the Web App is placed on."
  type        = string
  default     = "asp-uniqa-linux"
}

variable "vnet_name" {
  description = "Name of the existing virtual network."
  type        = string
  default     = "vnet-uniqa"
}

variable "integration_subnet_name" {
  description = "Subnet delegated to Microsoft.Web/serverFarms, used for App Service VNet Integration (outbound)."
  type        = string
  default     = "snet-appsvc-integration"
}

variable "private_endpoint_subnet_name" {
  description = "Subnet that hosts Private Endpoints (inbound)."
  type        = string
  default     = "snet-private-endpoints"
}

variable "private_dns_zone_webapp_name" {
  description = "Existing private DNS zone used by the Web App private endpoint."
  type        = string
  default     = "privatelink.azurewebsites.net"
}

variable "sql_server_name" {
  description = "Name of the EXISTING Azure SQL Server (random suffix, so no default; pass via TF_VAR_sql_server_name)."
  type        = string
}

variable "sql_admin_login" {
  description = "Administrator login of the existing SQL Server, used in the app connection string."
  type        = string
  default     = "sqladminuser"
}

variable "sql_admin_password" {
  description = "Administrator password of the existing SQL Server (pass via TF_VAR_sql_admin_password, never commit)."
  type        = string
  sensitive   = true
}

variable "log_analytics_workspace_name" {
  description = "Name of the existing Log Analytics workspace that receives diagnostics and App Insights data."
  type        = string
  default     = "log-uniqa"
}

variable "dns_zone_name" {
  description = "Existing public DNS zone used for the custom domain (<environment>.<dns_zone_name>)."
  type        = string
  default     = "stefanovic-devops.xyz"
}

# ---------------------------------------------------------------------------
# Environment-specific settings
# ---------------------------------------------------------------------------
variable "sql_database_sku" {
  description = "SKU of the per-environment Azure SQL database (Basic is the cheapest for dev/test)."
  type        = string
  default     = "Basic"
}

variable "sql_database_max_size_gb" {
  description = "Maximum size of the SQL database in GB (Basic supports up to 2)."
  type        = number
  default     = 2
}

variable "enable_custom_domain" {
  description = "Create DNS records, hostname binding and managed certificate for <environment>.<dns_zone_name>. Requires the zone to be delegated at the registrar."
  type        = bool
  default     = false
}

variable "app_settings" {
  description = "Extra, environment-specific Application Settings merged on top of the defaults (environment wins on key conflict)."
  type        = map(string)
  default     = {}
}

variable "python_version" {
  description = "Python runtime version of the Linux Web App."
  type        = string
  default     = "3.12"
}

variable "tags" {
  description = "Additional tags merged into the default tag set on every resource."
  type        = map(string)
  default     = {}
}
