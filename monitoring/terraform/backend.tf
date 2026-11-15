# Remote state in the bootstrap storage account, same partial configuration as the application root.
# Init with:  terraform init -backend-config=../../infrastructure/terraform/backend.hcl \
#                            -backend-config="key=monitoring.tfstate"
# Monitoring covers BOTH environments, so it has a single state file separate from dev/test.
terraform {
  backend "azurerm" {}
}
