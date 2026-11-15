# Monitoring

Observability for the Transactions API across both environments (`dev`, `test`) and the shared,
pre-existing SQL Server.

| Folder | Contents |
|---|---|
| [terraform/](terraform/README.md) | Terraform root: action group, metric alerts (SQL + Web App), external availability tests, availability alerts |
| [queries/](queries/) | Ready-to-run KQL for Application Insights / Log Analytics (`log-uniqa`) |

## How the existing SQL Server is monitored

- **Data source**: Azure Monitor platform metrics of each database on the existing server
  (`sql-uniqa-<suffix>` → `sqldb-uniqa-dev`, `sqldb-uniqa-test`), namespace
  `Microsoft.Sql/servers/databases`. No agent, no code — metrics are emitted by the platform.
- **Metrics & thresholds** (evaluated every 5 min over a 15-min window):

  | Metric | Threshold | Severity | Meaning |
  |---|---|---|---|
  | `cpu_percent` | avg > 80 % | 2 | compute saturation |
  | `dtu_consumption_percent` | avg > 80 % | 2 | Basic-tier DTU saturation |
  | `storage_percent` | avg > 80 % | 2 | approaching max size |
  | `connection_failed` | total > 5 | 1 | app cannot reach / authenticate to the DB |
  | `deadlock` | total > 0 | 2 | contention killing transactions |

- **Action group**: `ag-uniqa-oncall` — e-mail receiver (`TF_VAR_alert_email`) using the common
  alert schema; all alerts auto-resolve when the metric drops back below threshold.
- **Application-side view of SQL**: [queries/app-dependencies-sql.kql](queries/app-dependencies-sql.kql)
  shows every SQL call the app makes (count, failures, p95 latency), so DB-side metrics can be
  correlated with what the application experienced.

## How the apps feed Application Insights

The application-layer Terraform (`infrastructure/terraform/main.tf`) wires each App Service to its
Application Insights component with the app settings `APPLICATIONINSIGHTS_CONNECTION_STRING` and
`ApplicationInsightsAgent_EXTENSION_VERSION = "~3"`. The codeless agent instruments the Python
process, so **requests, dependencies (incl. SQL) and exceptions arrive without any code changes**.
Platform logs (`AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServiceAppLogs`) and metrics reach
`log-uniqa` through the diagnostic setting created in the same root.

## Quick checks

- Is the app healthy from the outside? → App Insights → *Availability* (`avail-<env>-health`).
- Why did 5xx fire? → [queries/app-failed-requests.kql](queries/app-failed-requests.kql) then
  [queries/appservice-console-errors.kql](queries/appservice-console-errors.kql).
- Is the database the bottleneck? → SQL database → *Metrics*, plus
  [queries/app-dependencies-sql.kql](queries/app-dependencies-sql.kql).
