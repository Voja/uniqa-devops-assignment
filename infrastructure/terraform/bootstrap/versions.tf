terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state on purpose: this is the chicken-and-egg root. It CREATES the
  # storage account that every other Terraform root uses as its remote backend,
  # so it cannot use that backend itself. The resulting terraform.tfstate is
  # gitignored and must be kept safe by the engineer (it contains the SQL admin
  # password). Applied rarely (once per subscription), so this is acceptable.
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
