# 05 · Monitoring

*Step-by-step guide · `monitoring/` · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** Monitoring answers two questions: *is the service working for users right
now* and *is a dependency about to fail*. For the first, Application Insights runs availability
tests against each environment's public URL from three regions and the App Service health check
probes `/health` from inside the platform. For the second, Azure Monitor metric alerts watch the
**existing SQL Server's** databases (capacity, failed connections, deadlocks) and the Web Apps
(errors, latency). Everything notifies one action group. The monitoring Terraform root creates only
alerting objects; the telemetry pipeline itself (App Insights agent, diagnostic settings) was wired
in by the application layer, so requests and SQL calls arrive without any code changes.

## 1. What is monitored

| Target | Signal | Alert name | Condition | Severity | Description |
|---|---|---|---|---|---|
| `sqldb-uniqa-<env>` on **existing** `sql-uniqa-bisn5` | `cpu_percent` | `sql-<env>-cpu-high` | avg > 80 % over 15 min | 2 | Compute saturation |
| | `dtu_consumption_percent` | `sql-<env>-dtu-high` | avg > 80 % over 15 min | 2 | Basic tier (5 DTU) saturating |
| | `storage_percent` | `sql-<env>-storage-high` | avg > 80 % over 15 min | 2 | Approaching the 2 GB limit |
| | `connection_failed` | `sql-<env>-failed-connections` | total > 5 over 15 min | 1 | App cannot reach/authenticate |
| | `deadlock` | `sql-<env>-deadlocks` | total > 0 over 15 min | 2 | Contention |
| `app-uniqa-<env>-stefanovic` | `Http5xx` | `app-<env>-http-5xx` | total > 5 over 5 min | 1 | Application errors |
| | `HttpResponseTime` | `app-<env>-response-time` | avg > 2 s over 15 min | 2 | Latency regression |
| | `HealthCheckStatus` | `app-<env>-health-check` | avg < 100 over 5 min | 1 | `/health` failing on an instance |
| `https://<env>.stefanovic-devops.xyz/health` | standard web test `avail-<env>-health` | `avail-<env>-failed` | ≥ 2 of 3 locations fail (5 min) | 1 | End-user availability incl. DNS and TLS |

All metric alerts evaluate every 5 minutes and auto-resolve. The web test runs every 300 s from
`emea-nl-ams-azr` (Amsterdam), `emea-fr-pra-edge` (Paris) and `us-va-ash-azr` (Virginia), expects
HTTP 200, body containing `"status":"ok"`, and a valid certificate with ≥ 7 days remaining.

> [!WARNING]
> The location id `emea-gb-db-azr` (Dublin) listed in older documentation is rejected by the API for
> standard web tests (`Location ... is not supported`); `emea-fr-pra-edge` was used instead.

## 2. Action group

| Property | Value | Description |
|---|---|---|
| Name / short name | `ag-uniqa-oncall` / `uniqa-oncall` | Short name appears in e-mail subjects |
| Receiver | e-mail `devops-oncall` → `TF_VAR_alert_email` | Common alert schema enabled |

Adding a Teams webhook, SMS or PagerDuty receiver is a single block in
[action_group.tf](../monitoring/terraform/action_group.tf); every alert already points at the group.

## 3. Apply the monitoring root

### 3.1 Initialise with its own state key

```bash
cd monitoring/terraform
terraform init \
  -backend-config=../../infrastructure/terraform/backend.hcl \
  -backend-config="key=monitoring.tfstate"
```

Uses the same storage account as the application root but a separate `monitoring.tfstate`, because
monitoring spans both environments.

### 3.2 Export inputs and apply

```bash
export TF_VAR_subscription_id="<SUBSCRIPTION_ID>"
export TF_VAR_sql_server_name="$(terraform -chdir=../../infrastructure/terraform/bootstrap output -raw sql_server_name)"
export TF_VAR_alert_email="<oncall mailbox>"
terraform plan -out=tfplan && terraform apply tfplan
```

Creates 1 action group, 16 metric alerts (8 per environment), 2 web tests and 2 availability
alerts — 21 resources — in about a minute; the data sources require both environments to exist.

> [!TIP]
> Trigger a real alert to prove the chain works: `for i in $(seq 1 10); do curl -s -o /dev/null
> https://dev.stefanovic-devops.xyz/does-not-exist; done` only produces 404s, so instead stop the
> app (`az webapp stop -g rg-uniqa-shared -n app-uniqa-dev-stefanovic`) for ~10 minutes:
> `avail-dev-failed` and `app-dev-health-check` fire, the e-mail arrives, and both resolve after
> `az webapp start`.

## 4. Where to look in the portal

| Question | Portal location | Description |
|---|---|---|
| Is it up for users? | Application Insights `appi-uniqa-<env>` → **Availability** | Per-location results of `avail-<env>-health` |
| What failed? | App Insights → **Failures** | Failed requests, dependencies (SQL) and exceptions |
| Where is time spent? | App Insights → **Performance** | Request and SQL dependency durations |
| What is happening now? | App Insights → **Live Metrics** | Real-time during a deployment |
| Is the database the bottleneck? | SQL database `sqldb-uniqa-<env>` → **Metrics** | CPU, DTU, storage, failed connections, deadlocks |
| What fired? | **Monitor → Alerts** | Fired/resolved alerts; *Alert rules* lists the 20 rules; *Action groups* shows `ag-uniqa-oncall` |
| Raw logs | Log Analytics `log-uniqa` → **Logs** | Run the KQL files below |

## 5. KQL queries

| File | Table | Description |
|---|---|---|
| [app-requests-overview.kql](../monitoring/queries/app-requests-overview.kql) | `requests` | Count, avg, p95 and success rate per endpoint, last 24 h |
| [app-failed-requests.kql](../monitoring/queries/app-failed-requests.kql) | `requests` | Every 5xx with URL and `operation_Id` for drill-down |
| [app-dependencies-sql.kql](../monitoring/queries/app-dependencies-sql.kql) | `dependencies` | SQL calls: volume, failure %, p95 — proves the app → SQL path is observed |
| [appservice-http-5xx.kql](../monitoring/queries/appservice-http-5xx.kql) | `AppServiceHTTPLogs` | Platform-level 5xx incl. 502/503 during restarts |
| [appservice-console-errors.kql](../monitoring/queries/appservice-console-errors.kql) | `AppServiceConsoleLogs` | gunicorn/Python `Traceback`/`error` lines |

Paste a file's contents into *Logs* of the matching resource (App Insights for the first three,
`log-uniqa` for the last two) and run it.

## 6. Verification

- [ ] `terraform output` in `monitoring/terraform` lists 10 `sql_alert_names`, 6 `webapp_alert_names`, 2 `availability_alert_names` and 2 `web_test_ids`.
- [ ] *Monitor → Alerts → Alert rules* shows 20 enabled rules targeting resources in `rg-uniqa-shared`.
- [ ] App Insights → *Availability* shows green results from all three locations for both environments.
- [ ] `app-dependencies-sql.kql` returns rows with `target` = `sql-uniqa-bisn5.database.windows.net` after a few requests to `/transactions`.
- [ ] A test e-mail from *Action groups → ag-uniqa-oncall → Test* arrives in the on-call mailbox.
