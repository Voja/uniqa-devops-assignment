# 07 · Teardown

*Step-by-step guide · destroying the environments safely · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** The running solution costs roughly **0.5 USD per day** (B1 plan ≈ 13 USD
per month, two Basic databases ≈ 5 USD per month each, the rest is cents), so it is cheap to keep
alive for a review period but should not be forgotten. Terraform roots must be destroyed in the
reverse order of creation: monitoring reads the apps and databases, the environments read the
shared layer, and the shared layer holds the state storage that the other roots are using — so it
goes last and from local state.

## 1. Destroy order

| Step | Root | State | Description |
|---|---|---|---|
| 1 | `monitoring/terraform` | `monitoring.tfstate` | Alerts, web tests, action group |
| 2 | `infrastructure/terraform` with `envs/test.tfvars` | `test.tfstate` | TEST app, DB, private endpoint, DNS records |
| 3 | `infrastructure/terraform` with `envs/dev.tfvars` | `dev.tfstate` | DEV app, DB, private endpoint, DNS records |
| 4 | `infrastructure/terraform/bootstrap` | local | Everything shared, including the state storage account |

## 2. Commands

### 2.1 Monitoring

```bash
cd monitoring/terraform
terraform init -backend-config=../../infrastructure/terraform/backend.hcl -backend-config="key=monitoring.tfstate"
terraform destroy
```

Removes 21 resources; confirm with `yes` when the plan lists only `azurerm_monitor_*` and
`azurerm_application_insights_standard_web_test` objects.

### 2.2 TEST, then DEV

```bash
cd ../../infrastructure/terraform
export TF_VAR_subscription_id="<SUBSCRIPTION_ID>"
export TF_VAR_sql_server_name="$(terraform -chdir=bootstrap output -raw sql_server_name)"
export TF_VAR_sql_admin_password="$(terraform -chdir=bootstrap output -raw sql_admin_password)"

terraform init -reconfigure -backend-config=backend.hcl -backend-config="key=test.tfstate"
terraform destroy -var-file=envs/test.tfvars

terraform init -reconfigure -backend-config=backend.hcl -backend-config="key=dev.tfstate"
terraform destroy -var-file=envs/dev.tfvars
```

Each destroy removes 11 resources (6 without custom domain); the certificate binding and managed
certificate go first, then the hostname binding, DNS records, private endpoint and finally the Web
App and database.

> [!WARNING]
> Match the state key to the tfvars exactly as in [03 §3.5](03-application-infrastructure.md#35-switch-to-the-other-environment).
> A destroy with `dev.tfstate` + `envs/test.tfvars` would still destroy **dev** (destroy follows the
> state, not the variables) — read the resource names in the plan before confirming.

### 2.3 Bootstrap (last)

```bash
cd bootstrap
terraform destroy -var-file=terraform.tfvars
```

Removes the 18 shared resources including the storage account that held the remote state files
(they are no longer needed — the roots above are already empty). The resource group deletion is the
slowest step (SQL Server and private endpoints), about 5 minutes.

> [!NOTE]
> If a destroy fails half-way with a dependency error (typically the private endpoint NIC still
> attached), simply re-run `terraform destroy`; ARM finishes the first deletion in the background.

## 3. Restore the domain

The public DNS zone is gone after §2.3, so the registrar must stop delegating to Azure DNS.

### 3.1 Switch the nameservers back

In Namecheap *Domain List → Manage → Nameservers* choose *Namecheap BasicDNS* (or the previous
custom set) and save; until then `stefanovic-devops.xyz` does not resolve at all.

```bash
dig NS stefanovic-devops.xyz +short
```

Should no longer list `azure-dns` nameservers once the registrar change has propagated.

## 4. Optional: GitHub and the service principal

```bash
az ad sp delete --id "$(az ad sp list --display-name sp-uniqa-devops-github --query '[0].appId' -o tsv)"
gh secret delete AZURE_CREDENTIALS --repo Voja/uniqa-devops-assignment
```

Removes the deployment identity and the secret that held its credentials; repository variables and
environments can stay, they contain nothing sensitive.

## 5. Verification

- [ ] `az group exists -n rg-uniqa-shared` prints `false`.
- [ ] `az resource list --query "[?contains(name,'uniqa')]" -o table` returns nothing.
- [ ] *Cost Management → Cost analysis* shows no further daily charges after the teardown date.
- [ ] `curl -sI https://dev.stefanovic-devops.xyz` fails to resolve (expected).
- [ ] `az ad sp list --display-name sp-uniqa-devops-github -o table` is empty (if §4 was done).
