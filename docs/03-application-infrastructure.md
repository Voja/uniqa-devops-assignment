# 03 · Application infrastructure (per environment)

*Step-by-step guide · `infrastructure/terraform/` · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** This root deploys *one environment* of the Transactions Service onto the
shared layer from [02-bootstrap-infrastructure.md](02-bootstrap-infrastructure.md): a Linux Web App
placed on the **existing** App Service Plan, a database on the **existing** SQL Server, and the
network wiring between them. The same code produces `dev` and `test`; only the tfvars file and the
name of the remote state file differ. All five assignment components — Application Settings,
Connection Strings, Custom Domain, Private Endpoint, VNet Integration — are attributes of the Web
App or small resources around it, and §5 maps each to the exact line of Terraform.

Two App Service networking features are easy to confuse. **VNet integration** is *outbound*: the app
gets an IP in the delegated subnet (10.10.1.x) and can reach private resources such as the SQL
private endpoint. A **private endpoint** on the Web App is *inbound*: clients inside the VNet reach
the app on 10.10.2.x instead of the public front end. This solution uses both.

## 1. Resources created per environment

| Resource | Name (`<env>` = dev/test) | Description |
|---|---|---|
| SQL database | `sqldb-uniqa-<env>` | Basic tier, 2 GB, on the existing `sql-uniqa-bisn5` |
| Application Insights | `appi-uniqa-<env>` | Workspace-based, linked to `log-uniqa` |
| Linux Web App | `app-uniqa-<env>-stefanovic` | Python 3.12, gunicorn, on `asp-uniqa-linux`; HTTPS only, TLS 1.2, health check `/health` |
| Private endpoint | `pe-app-uniqa-<env>-stefanovic` | In `snet-private-endpoints` (dev **10.10.2.5**, test **10.10.2.6**), registered in `privatelink.azurewebsites.net` |
| Diagnostic setting | `diag-app-uniqa-<env>-stefanovic` | HTTP, console and app logs + all metrics → `log-uniqa` |
| DNS records (optional) | `asuid.<env>` TXT, `<env>` CNAME | Ownership proof and alias in `stefanovic-devops.xyz` |
| Hostname binding + managed certificate (optional) | `<env>.stefanovic-devops.xyz` | Free App Service managed certificate, SNI |
| Random password | `random_password.flask_secret_key` | Flask `SECRET_KEY` app setting, generated per environment |

## 2. Inputs

| Input | How it is supplied | Description |
|---|---|---|
| `subscription_id` | `TF_VAR_subscription_id` | Never in the repo |
| `sql_server_name` | `TF_VAR_sql_server_name` | `sql-uniqa-bisn5`, bootstrap output |
| `sql_admin_password` | `TF_VAR_sql_admin_password` | Bootstrap output, sensitive |
| `environment`, `enable_custom_domain`, `app_settings` | `envs/<env>.tfvars` | Committed; contain no secrets |
| backend storage | `backend.hcl` (+ `key=<env>.tfstate` on the command line) | Ignored by git; copy from `backend.hcl.example` |

## 3. Deploy an environment

### 3.1 Backend configuration (once)

```bash
cd infrastructure/terraform
cp backend.hcl.example backend.hcl
```

Set `storage_account_name = "stuniqatfstatebisn5"` in `backend.hcl`; resource group and container
are already correct in the example.

### 3.2 Export the secrets and dynamic names

```bash
export TF_VAR_subscription_id="<SUBSCRIPTION_ID>"
export TF_VAR_sql_server_name="$(terraform -chdir=bootstrap output -raw sql_server_name)"
export TF_VAR_sql_admin_password="$(terraform -chdir=bootstrap output -raw sql_admin_password)"
```

The three values are read by Terraform from the environment, so they appear neither in files nor in
shell history as literals.

### 3.3 Initialise with the environment's state key

```bash
terraform init -backend-config=backend.hcl -backend-config="key=dev.tfstate"
```

Terraform connects to the `tfstate` container and creates or opens `dev.tfstate`.

### 3.4 Plan and apply

```bash
terraform plan -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan
```

First apply creates 6 resources (11 with custom domain enabled) in about 5 minutes; the plan shows
`app_settings` as `(sensitive value)` because it now contains `SECRET_KEY`.

### 3.5 Switch to the other environment

```bash
terraform init -reconfigure -backend-config=backend.hcl -backend-config="key=test.tfstate"
terraform plan -var-file=envs/test.tfvars -out=tfplan && terraform apply tfplan
```

`-reconfigure` re-points the working directory at `test.tfstate` without migrating anything; the
code is unchanged, only the inputs differ.

> [!WARNING]
> Always pair the state key with the matching tfvars. Running `envs/test.tfvars` against
> `dev.tfstate` would plan the destruction of the dev app and creation of the test app in the same
> state file. Reading the first line of the plan (`azurerm_linux_web_app.main must be replaced`) is
> the tell.

## 4. Enable the custom domain

Custom domains depend on public DNS, so they are a second step after the nameserver delegation
from [02 §4](02-bootstrap-infrastructure.md#4-the-one-manual-step-delegate-the-domain) has propagated.

### 4.1 Confirm delegation, then flip the flag

```bash
dig NS stefanovic-devops.xyz +short
```

The output must list the Azure nameservers; then set `enable_custom_domain = true` in
`envs/<env>.tfvars` (both files already have it enabled in the repo) and re-run §3.4 for each
environment.

### 4.2 What Terraform does

`custom_domain.tf` creates, in dependency order: the `asuid.<env>` TXT record carrying the Web
App's `custom_domain_verification_id`, the `<env>` CNAME to `app-uniqa-<env>-stefanovic.azurewebsites.net`,
the hostname binding, the managed certificate and the SNI certificate binding. The hostname binding
ignores changes to `ssl_state`/`thumbprint` because the certificate binding mutates them.

> [!NOTE]
> Issuing the managed certificate took 2–5 minutes per environment; until then the HTTPS URL answers
> with the default `*.azurewebsites.net` certificate and browsers warn. `az webapp config ssl list
> -g rg-uniqa-shared -o table` shows the certificate once issued.

## 5. Assignment component → Terraform

| Assignment component | Resource / attribute | Description |
|---|---|---|
| App Service on **existing** Linux ASP | `azurerm_linux_web_app.main.service_plan_id = data.azurerm_service_plan.shared.id` ([main.tf](../infrastructure/terraform/main.tf), [data.tf](../infrastructure/terraform/data.tf)) | The plan is read, never created, by this root |
| Application Settings | `azurerm_linux_web_app.main.app_settings = merge({...defaults...}, var.app_settings)` | Defaults: `APP_ENV`, `APP_VERSION`, `SECRET_KEY`, `WEBSITES_PORT`, `SCM_DO_BUILD_DURING_DEPLOYMENT`, App Insights; per-env `LOG_LEVEL`, `FEATURE_FLAG_DEMO` from tfvars |
| Connection Strings | `azurerm_linux_web_app.main.connection_string { name = "TransactionsDb", type = "SQLServer" }` | Surfaces to the process as `SQLCONNSTR_TransactionsDb`, read by `application/app.py` |
| Custom Domain | [custom_domain.tf](../infrastructure/terraform/custom_domain.tf): `azurerm_dns_txt_record.asuid`, `azurerm_dns_cname_record.app`, `azurerm_app_service_custom_hostname_binding.main`, `azurerm_app_service_managed_certificate.main`, `azurerm_app_service_certificate_binding.main` | Gated by `var.enable_custom_domain` |
| Private Endpoint | `azurerm_private_endpoint.webapp` (subresource `sites`, DNS zone group → `privatelink.azurewebsites.net`) | Inbound private IP 10.10.2.5 / 10.10.2.6 |
| VNet Integration | `azurerm_linux_web_app.main.virtual_network_subnet_id = data.azurerm_subnet.integration.id` + `site_config.vnet_route_all_enabled = true` | Outbound via 10.10.1.x; all traffic routed through the VNet |

## 6. Design note: `public_network_access_enabled = true`

The private endpoint already gives the app a private address, so why keep public access on? Because
the reviewer must be able to open the URL and because GitHub-hosted runners deploy over the public
Kudu/SCM endpoint. In production this would be `false`, with deployments from a self-hosted runner
in the VNet (or a private endpoint for the `scm` subresource) and public ingress fronted by
Application Gateway / Front Door. The decision is commented at the attribute itself in `main.tf`.

## 7. Verification

- [ ] `terraform output` shows `web_app_url`, `custom_domain_url`, `private_endpoint_ip` (10.10.2.5 for dev, 10.10.2.6 for test) and `web_app_principal_id`.
- [ ] `curl -s https://<env>.stefanovic-devops.xyz/health` returns `{"env":"<env>","status":"ok","version":"..."}`.
- [ ] `curl -s https://<env>.stefanovic-devops.xyz/health/deep` returns `"backend":"sqlserver"` and `"ok":true` — the app reached the database through the private endpoint.
- [ ] Opening `https://<env>.stefanovic-devops.xyz/` shows the **Request path** strip with the App Service name, the VNet-integration IP (`WEBSITE_PRIVATE_IP`, 10.10.1.x), the private endpoint node and the SQL node green with a latency in ms.
- [ ] `az webapp config appsettings list -g rg-uniqa-shared -n app-uniqa-<env>-stefanovic -o table` lists `APP_ENV`, `APP_VERSION`, `SECRET_KEY`, `LOG_LEVEL`, `FEATURE_FLAG_DEMO`.
- [ ] `az webapp config connection-string list -g rg-uniqa-shared -n app-uniqa-<env>-stefanovic` shows `TransactionsDb` of type `SQLServer`.
- [ ] `az webapp show -g rg-uniqa-shared -n app-uniqa-<env>-stefanovic --query virtualNetworkSubnetId` ends with `/snet-appsvc-integration`.
- [ ] `az webapp config ssl list -g rg-uniqa-shared -o table` lists a managed certificate for `<env>.stefanovic-devops.xyz`.
