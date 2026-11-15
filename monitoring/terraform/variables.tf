variable "subscription_id" {
  description = "Azure subscription that holds the monitored resources (pass via TF_VAR_subscription_id)."
  type        = string
}

variable "project" {
  description = "Short project name; prefix for alert/action-group names and tag value."
  type        = string
  default     = "uniqa"
}

variable "shared_resource_group_name" {
  description = "Resource group that contains the shared infra AND the per-environment apps/databases."
  type        = string
  default     = "rg-uniqa-shared"
}

variable "sql_server_name" {
  description = "Name of the EXISTING Azure SQL Server to monitor (random suffix, pass via TF_VAR_sql_server_name)."
  type        = string
}

variable "environments" {
  description = "Environments to monitor; drives for_each over databases, web apps and App Insights components."
  type        = list(string)
  default     = ["dev", "test"]
}

variable "app_name_suffix" {
  description = "Suffix used by the application root to make Web App names globally unique."
  type        = string
  default     = "stefanovic"
}

variable "dns_zone_name" {
  description = "Public DNS zone; availability tests probe https://<env>.<dns_zone_name>/health."
  type        = string
  default     = "stefanovic-devops.xyz"
}

variable "alert_email" {
  description = "On-call mailbox that receives every alert (pass via TF_VAR_alert_email; not committed)."
  type        = string
}

variable "alert_email_receiver_name" {
  description = "Display name of the e-mail receiver inside the action group."
  type        = string
  default     = "devops-oncall"
}

variable "tags" {
  description = "Additional tags merged into the default tag set."
  type        = map(string)
  default     = {}
}
