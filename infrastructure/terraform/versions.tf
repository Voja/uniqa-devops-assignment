# Pin Terraform and provider versions so every engineer and the CI pipeline run identical code.
terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Single azurerm provider; subscription is passed in explicitly (never inferred from az CLI context).
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
