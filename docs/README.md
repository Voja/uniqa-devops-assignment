# Documentation

*Step-by-step guide · index · Vojislav Stefanović · v1, 15.11.2026*

This folder explains how the assignment solution is built, deployed, operated and torn down. Each
document opens with the concept it covers before any command, so the guides can be followed by
someone who has not worked with Azure App Service or Terraform before. Commands are exact and were
run against the real environments listed in the root [README](../README.md).

## 1. Reading order

| # | Document | Description |
|---|---|---|
| 1 | [01-prerequisites.md](01-prerequisites.md) | Accounts, tools, the free-trial quota lesson, service principal and GitHub secrets/variables/environments |
| 2 | [02-bootstrap-infrastructure.md](02-bootstrap-infrastructure.md) | The shared "existing" layer: resource group, Linux App Service Plan, VNet, SQL Server, DNS zone, state storage |
| 3 | [03-application-infrastructure.md](03-application-infrastructure.md) | One environment (dev/test): Web App on the existing plan, app settings, connection string, VNet integration, private endpoint, custom domain |
| 4 | [04-cicd-pipelines.md](04-cicd-pipelines.md) | The four GitHub Actions workflows, the `pipelines/` mirror rule, artifact promotion and the smoke test |
| 5 | [05-monitoring.md](05-monitoring.md) | Alerts on the existing SQL Server and the apps, availability tests, action group, KQL queries |
| 6 | [06-troubleshooting.md](06-troubleshooting.md) | Every problem hit during the project and its fix |
| 7 | [07-teardown.md](07-teardown.md) | Safe destroy order and cost note |
| – | [architecture.md](architecture.md) | Diagrams (SVG + Mermaid) and component inventory |
| – | [evidence/README.md](evidence/README.md) | Screenshot checklist proving the deployment |

## 2. Conventions used in the guides

- `<env>` stands for `dev` or `test`; `<SUBSCRIPTION_ID>` and similar placeholders are never real values.
- Commands are run from the repository root unless a `cd` is shown.
- Callouts: `[!NOTE]` adds context, `[!WARNING]` marks something that caused a real failure,
  `[!TIP]` gives a verification trick.
- Every guide ends with a **Verification** checklist describing what success looks like.

## 3. Verification

- [ ] Every link in the table above opens the intended document.
- [ ] Each guide starts with the header line and a "What this is and why" paragraph and ends with a Verification checklist.

## 4. Component READMEs

Shorter, code-adjacent references live next to the code and are linked from the guides rather than
duplicated: [application/README.md](../application/README.md),
[infrastructure/terraform/bootstrap/README.md](../infrastructure/terraform/bootstrap/README.md),
[infrastructure/terraform/README.md](../infrastructure/terraform/README.md),
[pipelines/README.md](../pipelines/README.md), [monitoring/README.md](../monitoring/README.md),
[security/README.md](../security/README.md).
