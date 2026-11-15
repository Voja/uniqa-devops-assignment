# Pipelines

## The four workflows

| File | Name | Trigger | What it does | Environment / approval |
|---|---|---|---|---|
| [ci.yml](ci.yml) | **CI** | push to `dev`, PR into `main`, manual | flake8 · black · bandit · pytest+coverage · builds `app.zip` · `terraform fmt/validate` (application, bootstrap, monitoring roots) · Checkov · verifies the workflow mirror | none (read-only) |
| [qa.yml](qa.yml) | **QA** | push of tag `QA` / `QA-*`, manual | flake8 statistics · black · bandit report · pylint ≥ 8 · pytest with `--cov-fail-under=80` · HTML coverage artifact · everything in the job summary | none |
| [cd-dev.yml](cd-dev.yml) | **CD - DEV** | push to `main`, manual | quick tests → build `app.zip` → deploy to DEV Web App → set `APP_VERSION` → smoke test (`/health`, POST+GET `/transactions`) | GitHub Environment `dev` (no approval) |
| [cd-prod.yml](cd-prod.yml) | **CD - TEST (promotion)** | `workflow_run` after a successful **CD - DEV**, or manual with `run_id` | downloads the **same** `app-package` artifact from the DEV run → deploy to TEST Web App → set `APP_VERSION` → smoke test | GitHub Environment `test` **with required reviewer → manual approval gate** |

> The assignment names the last file `cd-prod.yml`. The second Azure environment in this assessment is
> TEST, so the file promotes DEV → TEST. A PROD stage would be one more job with `environment: prod`
> promoting the identical artifact again.

## Promotion flow

```
 feature work                 quality gate                 delivery
 ────────────                 ────────────                 ────────
 push to dev ─────────────▶  CI  (lint, test, tf validate, checkov, package)
                              │
 git tag QA-n ────────────▶  QA  (reports + coverage threshold)
                              │
 PR dev ─▶ main ──────────▶  CI on the PR
      │
      └─ merge to main ───▶  CD - DEV ──▶ deploy DEV ──▶ smoke test
                                               │ app-package (same zip)
                                               ▼
                             CD - TEST ─▶ ⏸ approval (env "test") ─▶ deploy TEST ─▶ smoke test
```

Build once, promote the artifact: TEST never rebuilds from source, so what was verified in DEV is
byte-for-byte what reaches TEST.

## `pipelines/` vs `.github/workflows/`

The assignment mandates the four files under `pipelines/`, but GitHub Actions only executes
workflows found in `.github/workflows/`. Therefore:

- **`pipelines/` is the source of truth.** Edit workflows here.
- `.github/workflows/` holds byte-identical copies. Regenerate them with
  [`scripts/sync-pipelines.sh`](../scripts/sync-pipelines.sh).
- The CI job **"Verify .github/workflows mirrors pipelines/"** runs `diff -r` between the two folders
  and fails on any drift, so the copies can never silently diverge.

```bash
scripts/sync-pipelines.sh          # copy pipelines/*.yml -> .github/workflows/
scripts/sync-pipelines.sh --check  # what CI runs
```

## Required GitHub configuration

### Secret (repository)

| Name | Value |
|---|---|
| `AZURE_CREDENTIALS` | Service-principal JSON (`clientId`, `clientSecret`, `subscriptionId`, `tenantId`), e.g. output of `az ad sp create-for-rbac --sdk-auth`. Scope: *Contributor* on the subscription for this assignment (least-privilege alternative: *Website Contributor* on `rg-uniqa-shared`) (see [security/README.md](../security/README.md)). |

### Variable (repository)

| Name | Value |
|---|---|
| `AZURE_RESOURCE_GROUP` | `rg-uniqa-shared` — resource group of both Web Apps (Terraform output `resource_group_name`) |

### Variables per GitHub Environment

Create Environments `dev` and `test` (Settings → Environments). On `test`, add a **required reviewer**.

| Environment | `AZURE_WEBAPP_NAME` | `APP_URL` |
|---|---|---|
| `dev` | `app-uniqa-dev-stefanovic` | `https://dev.stefanovic-devops.xyz` (or the `web_app_url` Terraform output) |
| `test` | `app-uniqa-test-stefanovic` | `https://test.stefanovic-devops.xyz` (or the `web_app_url` Terraform output) |

Both values are Terraform outputs of `infrastructure/terraform` (`web_app_name`, `web_app_url` /
`custom_domain_url`).

## Conventions

- Runners: `ubuntu-latest`; Python 3.12; actions pinned to major versions.
- `concurrency` per workflow + ref; `cancel-in-progress: true` only for CI/QA, never for deployments.
- `permissions: contents: read` everywhere (`actions: read` added only where an artifact is pulled
  from another run). Azure auth uses the SP secret, so no `id-token: write`.
- `app.zip` = application source + `requirements.txt` only (no venv, tests, caches, dev tooling).
  App Service installs dependencies itself because Terraform sets `SCM_DO_BUILD_DURING_DEPLOYMENT=true`.
- `APP_VERSION` is stamped at deploy time with the short commit SHA; Terraform ignores changes to
  that key so the next `terraform apply` does not revert it.
