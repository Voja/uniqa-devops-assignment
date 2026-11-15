variable "subscription_id" {
  description = "Azure subscription ID that all bootstrap resources are created in."
  type        = string
}

variable "project" {
  description = "Short project name used as the prefix/suffix in every resource name and tag."
  type        = string
  default     = "uniqa"
}

variable "location" {
  description = "Azure region for all resources in this layer."
  type        = string
  default     = "northeurope"
}

variable "asp_sku" {
  description = "SKU of the shared Linux App Service Plan (e.g. B1, S1, P1v3)."
  type        = string
  default     = "B1"
}

variable "sql_admin_login" {
  description = "Administrator login name for the shared Azure SQL Server."
  type        = string
  default     = "sqladminuser"
}

variable "admin_client_ip" {
  description = "Public IPv4 address of the engineer's workstation; allowed through the SQL Server firewall for management only."
  type        = string
}

variable "dns_zone_name" {
  description = "Public DNS zone to create for application custom domains; must be delegated at the registrar after apply."
  type        = string
  default     = "stefanovic-devops.xyz"
}
