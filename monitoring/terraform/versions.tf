# Same provider pin as the other roots so all three layers behave identically in CI and locally.
terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Subscription passed explicitly (TF_VAR_subscription_id), never inferred from the az CLI context.
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
