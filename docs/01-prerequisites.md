# 01 · Prerequisites

*Step-by-step guide · accounts, tools, service principal, GitHub configuration · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** Before any infrastructure can be created, three things must exist: an
Azure subscription with enough quota to run an App Service, a set of command-line tools on the
engineer's workstation, and a non-human identity (a *service principal*) that GitHub Actions uses to
deploy code without a person logging in. This guide walks through all three and ends with the exact
GitHub configuration (one secret, one repository variable, two environments) the pipelines expect.
Everything here is done once per subscription/repository.

## 1. Accounts

| Item | Used for | Description |
|---|---|---|
| Azure subscription | all infrastructure | Must allow App Service Linux plans and Azure SQL in the chosen region (see the warning below) |
| GitHub account + repository `Voja/uniqa-devops-assignment` | source, pipelines | Branches `main` (default) and `dev`; the free plan is sufficient (Environments with required reviewers work on public repos) |
| Domain `stefanovic-devops.xyz` at a registrar (Namecheap) | custom domains | Nameservers are delegated to Azure DNS in [02-bootstrap-infrastructure.md](02-bootstrap-infrastructure.md) |

> [!WARNING]
> **Free-trial subscriptions have an App Service quota of 0 in every region.** The first
> `terraform apply` failed with `Quota exceeded... Current Limit: 0` for the B1 plan, and Azure SQL in
> North Europe returned `ProvisioningDisabled`. The fix was to upgrade the subscription to
> **Pay-As-You-Go** (the remaining trial credit carried over) and to use the region
> **`francecentral`**, where both the App Service plan and SQL provisioned. Check
> *Subscription → Usage + quotas → Compute* before planning anything.

## 2. Tools

| Tool | Minimum version | Description |
|---|---|---|
| Azure CLI (`az`) | 2.60 | Authentication for Terraform (`az login`) and ad-hoc checks |
| Terraform | 1.6 (used 1.17) | Provisions all three layers; provider `azurerm ~> 4.0` |
| GitHub CLI (`gh`) | 2.40 | Sets secrets, variables and environments from the terminal |
| Python | 3.12 | Runs the app and its tests locally |
| `zip`, `curl`, `dig` | any | Packaging and verification |

### 2.1 Check the versions

```bash
az version --query '"azure-cli"' -o tsv && terraform version && gh --version && python3 --version
```

Each line should print a version at or above the minimum in the table; if `python3` is below 3.12
the local tests will still run, but the App Service runtime is 3.12 and should be matched.

### 2.2 Log in

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
gh auth login
```

`az login` opens a browser; `az account set` pins the subscription Terraform will use (the roots
also take it explicitly via `subscription_id`), and `gh auth login` authorises the GitHub CLI.

## 3. Service principal for GitHub Actions

A service principal is an application identity in Entra ID. GitHub Actions authenticates with it
(`azure/login@v2`) to run `az webapp deploy`, change the `APP_VERSION` app setting and restart the
app. It is **not** used for Terraform, which an engineer runs interactively.

### 3.1 Create it

```bash
az ad sp create-for-rbac \
  --name sp-uniqa-devops-github \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth > sp-uniqa-devops-github.json
```

This creates the principal, assigns **Contributor** on the subscription and writes a JSON document
(`clientId`, `clientSecret`, `subscriptionId`, `tenantId`) in the format `azure/login` expects.

> [!NOTE]
> Contributor on the subscription was chosen for simplicity of the assessment. The pipelines only
> need to deploy and change settings on two Web Apps, so the least-privilege scope would be
> *Website Contributor* on `rg-uniqa-shared` — see [security/README.md](../security/README.md).
> The JSON file is a secret: it is `.gitignore`d (`*.json.local` pattern is not enough, so keep it
> outside the repository) and should be deleted after step 4.1.

## 4. GitHub configuration

The workflows read one repository secret, one repository variable and two per-environment
variables. Environment `test` additionally has a **required reviewer**, which is what turns the
TEST deployment into a manual approval gate.

| Scope | Name | Value | Description |
|---|---|---|---|
| Repository secret | `AZURE_CREDENTIALS` | contents of the SP JSON | Used by `azure/login@v2` in both CD workflows |
| Repository variable | `AZURE_RESOURCE_GROUP` | `rg-uniqa-shared` | Resource group of both Web Apps |
| Environment `dev` variable | `AZURE_WEBAPP_NAME` | `app-uniqa-dev-stefanovic` | Deployment target |
| Environment `dev` variable | `APP_URL` | `https://dev.stefanovic-devops.xyz` | Smoke-test base URL and environment link |
| Environment `test` variable | `AZURE_WEBAPP_NAME` | `app-uniqa-test-stefanovic` | Deployment target |
| Environment `test` variable | `APP_URL` | `https://test.stefanovic-devops.xyz` | Smoke-test base URL and environment link |
| Environment `test` protection | required reviewer | your GitHub user | Pauses `CD - TEST` until approved |

### 4.1 Secret and repository variable

```bash
gh secret set AZURE_CREDENTIALS --repo Voja/uniqa-devops-assignment < sp-uniqa-devops-github.json
gh variable set AZURE_RESOURCE_GROUP --repo Voja/uniqa-devops-assignment --body rg-uniqa-shared
rm sp-uniqa-devops-github.json
```

The secret is stored encrypted and never printed by Actions; the variable is plain text and visible
in workflow logs.

### 4.2 Environments and their variables

```bash
gh api -X PUT repos/Voja/uniqa-devops-assignment/environments/dev
gh api -X PUT repos/Voja/uniqa-devops-assignment/environments/test \
  --input - <<EOF
{"reviewers":[{"type":"User","id":$(gh api user --jq .id)}]}
EOF

for env in dev test; do
  gh variable set AZURE_WEBAPP_NAME --repo Voja/uniqa-devops-assignment --env "$env" --body "app-uniqa-$env-stefanovic"
  gh variable set APP_URL           --repo Voja/uniqa-devops-assignment --env "$env" --body "https://$env.stefanovic-devops.xyz"
done
```

The first two calls create the environments (the second one with you as required reviewer); the
loop sets the two variables each CD job reads through `${{ vars.* }}`.

> [!TIP]
> `gh variable list --env test` and `gh api repos/Voja/uniqa-devops-assignment/environments/test --jq
> '.protection_rules[].type'` show the configuration without opening the browser; the second command
> must print `required_reviewers`.

## 5. Verification

- [ ] `az account show --query name` prints the Pay-As-You-Go subscription.
- [ ] *Usage + quotas* shows a non-zero limit for *Basic App Service Plan* (or the plan size you use) in `francecentral`.
- [ ] `terraform version` ≥ 1.6, `python3 --version` = 3.12.x.
- [ ] `az ad sp list --display-name sp-uniqa-devops-github --query '[].appId' -o tsv` prints one id.
- [ ] `gh secret list` shows `AZURE_CREDENTIALS`; `gh variable list` shows `AZURE_RESOURCE_GROUP`.
- [ ] `gh variable list --env dev` and `--env test` each show `AZURE_WEBAPP_NAME` and `APP_URL`.
- [ ] Environment `test` lists a `required_reviewers` protection rule.
