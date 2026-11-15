# Monitoring layer (Terraform root)

Attaches alerting and external availability tests to the resources created by
`infrastructure/terraform` (bootstrap + application). It creates **no** application resources —
every target is read through data sources — so it can be applied, changed or destroyed without
touching the workloads.

## What is monitored and why

| Target | Signal | Alert | Why |
|---|---|---|---|
| **Existing SQL Server** → `sqldb-uniqa-<env>` | `cpu_percent` avg > 80 % (15 m) | `sql-<env>-cpu-high`, sev 2 | Capacity: queries or tier undersized |
| | `dtu_consumption_percent` avg > 80 % (15 m) | `sql-<env>-dtu-high`, sev 2 | Capacity: Basic tier saturating |
| | `storage_percent` avg > 80 % (15 m) | `sql-<env>-storage-high`, sev 2 | Capacity: writes fail at 100 % |
| | `connection_failed` total > 5 (15 m) | `sql-<env>-failed-connections`, sev 1 | Failures: firewall / credentials / private endpoint |
| | `deadlock` total > 0 (15 m) | `sql-<env>-deadlocks`, sev 2 | Contention: transactions being killed |
| **Web App** `app-uniqa-<env>-stefanovic` | `Http5xx` total > 5 (5 m) | `app-<env>-http-5xx`, sev 1 | Errors |
| | `HttpResponseTime` avg > 2 s (15 m) | `app-<env>-response-time`, sev 2 | Latency |
| | `HealthCheckStatus` avg < 100 (5 m) | `app-<env>-health-check`, sev 1 | Platform health probe on `/health` |
| **External availability** | Standard web test `GET https://<env>.stefanovic-devops.xyz/health` from Amsterdam, Dublin, Virginia every 5 min; expects 200, body contains `"status":"ok"`, valid TLS cert with ≥ 7 days left | `avail-<env>-failed` when ≥ 2 locations fail, sev 1 | End-user view: DNS + TLS + front end + app |

All alerts notify the action group `ag-uniqa-oncall` (e-mail receiver, common alert schema) and
auto-resolve when the condition clears. Everything is created for each entry in `var.environments`
(default `["dev", "test"]`).

## Apply

```bash
cd monitoring/terraform

# Backend: same storage account as the application root, its own state file.
terraform init \
  -backend-config=../../infrastructure/terraform/backend.hcl \
  -backend-config="key=monitoring.tfstate"

# Inputs that must not live in the repo.
export TF_VAR_subscription_id="<subscription guid>"
export TF_VAR_sql_server_name="$(terraform -chdir=../../infrastructure/terraform/bootstrap output -raw sql_server_name)"
export TF_VAR_alert_email="oncall@example.com"

terraform plan -out=tfplan && terraform apply tfplan
```

Prerequisites: both environments applied by the application root (the data sources must resolve),
and the custom domains resolving publicly (the availability tests probe them).

## Where to see the data in the portal

- **Application Insights `appi-uniqa-<env>`** → *Availability* (web test results per location),
  *Failures* (exceptions, failed requests/dependencies), *Performance* (request and SQL dependency
  durations), *Live Metrics* (real-time during a deployment), *Transaction search*.
- **SQL database `sqldb-uniqa-<env>`** → *Metrics* (CPU, DTU, storage, failed connections,
  deadlocks), *Query Performance Insight*.
- **Monitor → Alerts** → fired/resolved alerts, *Alert rules* for the list created here,
  *Action groups* for `ag-uniqa-oncall`.
- **Log Analytics `log-uniqa`** → *Logs* for the KQL in [`../queries/`](../queries/).

## What I would add for production

- **Log-based alerts** (`azurerm_monitor_scheduled_query_rules_alert_v2`) on App Insights /
  App Service logs — e.g. new exception types, `Traceback` in console logs, dependency failure rate.
- **Dashboards / Workbooks** — an Azure Workbook per service combining availability, latency, 5xx
  and SQL DTU on one page; or **Grafana** with the Azure Monitor data source for team-wide boards.
- **SQL Insights / Database Watcher** for wait statistics and query-level telemetry, plus
  **Defender for SQL** (vulnerability assessment, threat detection — currently a Checkov skip).
- **Smart Detection / anomaly-based thresholds** instead of static ones as traffic patterns emerge.
- **Alert processing rules** for maintenance windows and routing by severity (sev 1 → pager,
  sev 2 → e-mail/Teams).
