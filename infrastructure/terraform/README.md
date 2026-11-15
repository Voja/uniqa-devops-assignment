# Application layer (per-environment Terraform root)

Provisions **one environment** (dev or test) of the Transactions API onto the shared infrastructure
created by [bootstrap/](bootstrap/): a Linux Web App on the **existing** App Service Plan, a database on
the **existing** SQL Server, VNet Integration, a Private Endpoint, Application Insights, diagnostics and
(optionally) a custom domain with a managed certificate.

The same code serves both environments; only the tfvars file and the remote-state key differ.

## Prerequisites

1. `bootstrap/` has been applied and you have its outputs (`terraform -chdir=bootstrap output`).
2. `az login` with access to the subscription.
3. `cp backend.hcl.example backend.hcl` and fill in `storage_account_name` from the bootstrap output.

## Deploy an environment

```bash
cd infrastructure/terraform

# 1. Backend: shared storage account, per-environment state file.
terraform init -backend-config=backend.hcl -backend-config="key=dev.tfstate"

# 2. Secrets / dynamic IDs come from the environment, never from the repo.
export TF_VAR_subscription_id="<subscription guid>"
export TF_VAR_sql_server_name="$(terraform -chdir=bootstrap output -raw sql_server_name)"
export TF_VAR_sql_admin_password="$(terraform -chdir=bootstrap output -raw sql_admin_password)"

# 3. Plan + apply with the environment's tfvars.
terraform plan  -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan
```

### Switching environments

Re-initialise with a different state key (code and backend.hcl stay the same):

```bash
terraform init -reconfigure -backend-config=backend.hcl -backend-config="key=test.tfstate"
terraform plan -var-file=envs/test.tfvars -out=tfplan && terraform apply tfplan
```

### Custom domain

Set `enable_custom_domain = true` in the tfvars once the public DNS zone's nameservers are delegated
at the registrar (see bootstrap README). This creates the `asuid` TXT + CNAME records, the hostname
binding and a free App Service managed certificate for `<env>.stefanovic-devops.xyz`.

## Requirement → code map

| Assignment requirement | Resource / attribute |
|---|---|
| App Service on **existing** Linux ASP | `azurerm_linux_web_app.main.service_plan_id = data.azurerm_service_plan.shared.id` ([main.tf](main.tf), [data.tf](data.tf)) |
| Application Settings | `azurerm_linux_web_app.main.app_settings` = `merge(defaults, var.app_settings)`; per-env values in [envs/*.tfvars](envs/) |
| Connection Strings | `azurerm_linux_web_app.main.connection_string { name = "TransactionsDb", type = "SQLServer" }` → env var `SQLCONNSTR_TransactionsDb` read by `application/app.py` |
| Custom Domain | [custom_domain.tf](custom_domain.tf): `azurerm_dns_txt_record.asuid`, `azurerm_dns_cname_record.app`, `azurerm_app_service_custom_hostname_binding.main`, `azurerm_app_service_managed_certificate.main`, `azurerm_app_service_certificate_binding.main` |
| Private Endpoint (inbound) | `azurerm_private_endpoint.webapp` in `snet-private-endpoints`, subresource `sites`, DNS group → `privatelink.azurewebsites.net` |
| VNet Integration (outbound) | `azurerm_linux_web_app.main.virtual_network_subnet_id = data.azurerm_subnet.integration.id` + `site_config.vnet_route_all_enabled = true` |
| Monitoring | `azurerm_application_insights.main` (workspace-based), `azurerm_monitor_diagnostic_setting.webapp` → Log Analytics |

## Why `public_network_access_enabled` stays `true`

The Private Endpoint already gives the app a private IP in the VNet. Public access is deliberately kept
on for this assessment so the reviewer can open the URL and so GitHub Actions can deploy over the public
Kudu/SCM endpoint. In production it would be `false`, with deployments executed from a self-hosted
runner inside the VNet (or via a private SCM endpoint) and ingress fronted by Application Gateway / Front Door.
