# Remote state in the storage account created by the bootstrap layer.
# PARTIAL configuration on purpose: storage account / container / key are supplied at init time
# (-backend-config=backend.hcl -backend-config="key=<env>.tfstate"), so this ONE code base serves
# both dev and test with completely separate state files and no per-environment copies of code.
terraform {
  backend "azurerm" {}
}
