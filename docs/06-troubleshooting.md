# 06 · Troubleshooting

*Step-by-step guide · real issues and their fixes · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** Every entry below is a problem that actually occurred while building this
solution, in the order it was met, with the symptom as it appeared, the cause, and the exact fix
that was applied. The point is not that things went wrong — it is that each one is now understood,
reproducible and documented, so the next person loses minutes rather than hours.

## 1. App Service quota is 0 on a free-trial subscription

**Symptom.** `terraform apply` of the bootstrap layer fails on `azurerm_service_plan.linux`:
`Operation cannot be completed without additional quota... Current Limit (Basic VMs): 0` — in every
region tried.

**Cause.** Free-trial subscriptions carry zero quota for App Service plans; it is not a regional
capacity issue.

**Fix.** *Subscription → Upgrade* to Pay-As-You-Go (the remaining trial credit carried over), then
re-run the apply.

```bash
az appservice list-locations --sku B1 --linux-workers-enabled -o table
```

Lists the regions where a Linux B1 plan can be created for this subscription; the quota itself is
shown under *Subscription → Usage + quotas → Compute* and must be ≥ 1 for the chosen region.

## 2. Azure SQL `ProvisioningDisabled` in North Europe

**Symptom.** `azurerm_mssql_server.main` fails with `ProvisioningDisabled: Provisioning is restricted
in this region`.

**Cause.** SQL provisioning for new (particularly new/trial) subscriptions is restricted in some
regions; North Europe was one of them at the time.

**Fix.** Moved the whole deployment to `francecentral` (`location = "francecentral"` in
`bootstrap/terraform.tfvars`). All layers take the location from the shared resource group, so no
other change was required.

> [!TIP]
> The portal's *Create SQL server* blade greys out restricted regions, and `az sql server create`
> fails within seconds with the same `ProvisioningDisabled` message, so testing a candidate region
> takes less than a minute — do it before building anything else there.

## 3. ARM eventual consistency: 404 after create, "inconsistent result after apply"

**Symptom.** Right after creating the private DNS zone link or the private endpoint, Terraform read
the resource back and got `404 Not Found`, or reported *Provider produced inconsistent result after
apply*. The resource was visible in the portal a few seconds later.

**Cause.** Azure Resource Manager replicates asynchronously; a read immediately after a write can
hit a replica that does not yet have the object.

**Fix.** Re-run the same `terraform apply`; it converged every time. When a resource existed in
Azure but Terraform had not recorded it in state (the apply aborted between create and write),
import it:

```bash
cd infrastructure/terraform/bootstrap
terraform import azurerm_private_dns_zone.webapp \
  "/subscriptions/664af7f2-f002-4be7-8bd6-8e7afa173e9d/resourceGroups/rg-uniqa-shared/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
terraform import azurerm_private_dns_zone_virtual_network_link.sql \
  "/subscriptions/664af7f2-f002-4be7-8bd6-8e7afa173e9d/resourceGroups/rg-uniqa-shared/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net/virtualNetworkLinks/link-uniqa-sql"
```

Each import adopts the existing object into state; a following `terraform plan` must show *No
changes* for it (if it shows in-place updates, the arguments in code differ from what was created —
fix the code, not the resource).

```bash
az resource list -g rg-uniqa-shared --query "[].{name:name,type:type}" -o table
```

Lists what really exists so you can compare against `terraform state list` and find orphans.

## 4. `health_check_path` requires `health_check_eviction_time_in_min`

**Symptom.** Plan showed a perpetual diff on `site_config`, or the apply error `health_check_eviction_time_in_min
must be set when health_check_path is set` (depending on provider version).

**Cause.** Azure stores the eviction time alongside the path; without it the provider cannot
reconcile the block.

**Fix.** Added `health_check_eviction_time_in_min = 10` next to `health_check_path = "/health"` in
`infrastructure/terraform/main.tf`.

## 5. `az webapp deploy` returns 504 although the build succeeded

**Symptom.** The deploy step in CD - DEV ended with `504 Gateway Timeout` from the Kudu endpoint,
yet the next `/health` call already served the new code.

**Cause.** With `SCM_DO_BUILD_DURING_DEPLOYMENT=true` the Oryx build (pip install on a B1 worker)
can exceed the Kudu HTTP gateway timeout; the build continues server-side.

**Fix.** The workflows use `azure/webapps-deploy@v3`, which polls the deployment status instead of
holding one request; the smoke test then confirms the new version is live (phase 1 waits for
`version == <sha>`). For ad-hoc deploys use `az webapp deploy --async true` and watch
`az webapp log deployment show`.

## 6. `pyodbc` cannot load the ODBC driver on App Service

**Symptom.** `ImportError`/`Can't open lib 'ODBC Driver 18 for SQL Server'` at first request.

**Cause.** The App Service Linux Python image does not reliably ship the Microsoft ODBC driver, and
installing it needs root and apt — not available in the Oryx build.

**Fix.** Replaced `pyodbc` with **pymssql 2.3.13**, which ships a self-contained `manylinux_2_28`
wheel (FreeTDS and OpenSSL bundled). `app.py` parses the ADO.NET-style connection string App Service
provides and passes host, port, database, user and password to `pymssql.connect`.

```bash
pip download --only-binary=:all: --python-version 3.12 --platform manylinux_2_28_x86_64 pymssql==2.3.13 -d /tmp/whl
```

Proves a binary wheel exists for the runtime before relying on it; if this fails, Oryx would try a
source build and fail.

## 7. Smoke test 503 right after changing app settings

**Symptom.** The first CD - DEV run passed `/health` and then got `503` on `POST /transactions`.

**Cause.** `az webapp config appsettings set` restarts the container asynchronously; the script had
tested the *old* container and then hit the restart window.

**Fix.** `scripts/smoke-test.sh` now takes the expected version and waits (30 × 10 s) until
`/health` returns the **new** sha before any functional call, with per-request retries afterwards;
the workflows restart explicitly with `az webapp restart` so the rollout is deterministic.
Details in [04-cicd-pipelines.md](04-cicd-pipelines.md) §5.

## 8. Standard web test rejects location `emea-gb-db-azr`

**Symptom.** `azurerm_application_insights_standard_web_test` failed with
`Location 'emea-gb-db-azr' is not supported`.

**Cause.** Not every classic test location is available for *standard* web tests.

**Fix.** Replaced it with `emea-fr-pra-edge` (Paris) in `monitoring/terraform/availability.tf`.

The accepted identifiers are the ones offered in *Application Insights → Availability → Add
standard test → Test locations*; the portal list is authoritative for the subscription.

## 9. GitHub environment approval

**Symptom.** CD - TEST stayed in *Waiting* with no visible approve button.

**Cause.** The required reviewer must open *Review deployments*, tick the environment checkbox and
then click *Approve and deploy*; the button is disabled until the checkbox is ticked. Also,
*Prevent self-review* must be off if you are the only reviewer.

**Fix.** Approve in the UI as described, or from the terminal:

```bash
RUN_ID=$(gh run list --workflow "CD - TEST (promotion)" --status waiting --limit 1 --json databaseId --jq '.[0].databaseId')
ENV_ID=$(gh api repos/Voja/uniqa-devops-assignment/environments/test --jq .id)
gh api -X POST "repos/Voja/uniqa-devops-assignment/actions/runs/$RUN_ID/pending_deployments" \
  --input - <<EOF
{"environment_ids":[$ENV_ID],"state":"approved","comment":"promote to test"}
EOF
```

Approves the pending `test` deployment of the waiting run; the job starts within seconds.

## 10. `workflow_run` does not fire

**Symptom.** CD - DEV succeeded but no CD - TEST run appeared.

**Cause.** `workflow_run` only triggers for workflow files present on the **default branch**;
`cd-prod.yml` existed on `dev` only.

**Fix.** Merge the workflow to `main` first; subsequent CD - DEV runs chain correctly. For a
one-off, `gh workflow run "CD - TEST (promotion)" -f run_id=<id>` promotes any DEV run manually.

## 11. Slow deployments (Oryx build on B1)

**Symptom.** `deploy-dev` takes 4–6 minutes, most of it `pip install` on the B1 worker.

**Cause.** The package contains source only; App Service resolves and builds dependencies on a
single-core B1 instance each deploy.

**Fix (production).** Build wheels in CI and ship them in the package (`pip wheel -r
requirements.txt -w wheels/` + `SCM_DO_BUILD_DURING_DEPLOYMENT=false` with a pre-built venv), or
use **deployment slots** on an S1+/P-tier plan: deploy to a staging slot, warm it, then swap — zero
downtime and no build on the production slot.

## 12. Verification

- [ ] `terraform plan` for every root shows *No changes* after the fixes above are in place.
- [ ] `gh run list --limit 4` shows CI, QA, CD - DEV and CD - TEST green.
- [ ] *Monitor → Alerts → Alert rules* includes both `avail-<env>-failed` rules (proves §8 is resolved).
- [ ] `GET /health/deep` on both environments returns `"backend":"sqlserver"` (proves §6).
