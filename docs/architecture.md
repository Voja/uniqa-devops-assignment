# Architecture

*Step-by-step guide · diagrams and component inventory · Vojislav Stefanović · v1, 15.11.2026*

**What this is and why.** One picture of how a request travels from a user's browser to the
database, and one of how a commit travels from a developer to the TEST environment. Both diagrams
below are kept deliberately simple; the exact names, addresses and thresholds live in the
inventory table (§3) and in the step-by-step guides.

![Architecture](img/architecture.svg)

## 1. Infrastructure

```mermaid
flowchart LR
  U[Internet / users] -- HTTPS --> APP
  DNS[Azure DNS<br/>stefanovic-devops.xyz<br/>CNAME + TXT asuid] -. resolves .-> U
  GH[GitHub Actions] -. service principal<br/>zip deploy .-> APP

  subgraph PLAN[asp-uniqa-linux · B1 · existing]
    APP[app-uniqa-env-stefanovic<br/>public hostname + managed cert]
  end

  subgraph VNET[vnet-uniqa 10.10.0.0/16]
    subgraph S1[snet-appsvc-integration 10.10.1.0/24]
      VI[VNet integration<br/>10.10.1.x · vnet_route_all]
    end
    subgraph S2[snet-private-endpoints 10.10.2.0/24]
      PEA[pe-app · 10.10.2.5 / .6]
      PES[pe-sql-uniqa-bisn5]
    end
    PDNS[Private DNS zones<br/>privatelink.azurewebsites.net<br/>privatelink.database.windows.net]
  end

  APP -- VNet integration --> VI
  PEA -- private endpoint --> APP
  VI -- TCP 1433 --> PES
  PES -- private link --> SQL[(Azure SQL · existing<br/>sql-uniqa-bisn5<br/>sqldb-uniqa-dev / test)]

  APP -. telemetry .-> AI[Application Insights<br/>appi-uniqa-env]
  AI --> LAW[Log Analytics<br/>log-uniqa]
  APP -. diagnostics .-> LAW
  SQL -. metrics .-> AL[Azure Monitor alerts<br/>ag-uniqa-oncall]
  APP -. metrics .-> AL
```

User traffic enters through the public hostname; the app's own traffic to SQL never leaves the VNet.

> [!NOTE]
> The Web App's private endpoint (10.10.2.x) is not on the user path in this assessment — public
> access is kept on so the reviewer and GitHub-hosted runners can reach the app. It is the ingress
> that an Application Gateway or a VNet-internal client would use in production.

## 2. CI/CD

```mermaid
flowchart LR
  DEV[push to dev] --> CI[CI<br/>flake8 · black · bandit · pytest<br/>terraform validate · checkov]
  TAG[tag QA-n] --> QA[QA<br/>reports · coverage ≥ 80 %]
  PR[PR → main] --> CI
  MAIN[merge to main] --> CDD[CD - DEV<br/>build app.zip → deploy dev<br/>APP_VERSION · restart · smoke test]
  CDD -- workflow_run --> GATE{{approval · environment test}}
  GATE --> CDT[CD - TEST<br/>same app.zip → deploy test<br/>APP_VERSION · restart · smoke test]
```

The artifact built in CD - DEV is the only thing that reaches TEST; nothing is rebuilt after the gate.

## 3. Components

| Layer | Component | Name | Description |
|---|---|---|---|
| Shared | Resource group | `rg-uniqa-shared` | All resources, `francecentral` |
| Shared | App Service Plan | `asp-uniqa-linux` | Linux B1; the *existing* plan |
| Shared | Virtual network | `vnet-uniqa` 10.10.0.0/16 | Two subnets, see below |
| Shared | Subnet | `snet-appsvc-integration` 10.10.1.0/24 | Delegated to `Microsoft.Web/serverFarms`; outbound VNet integration |
| Shared | Subnet | `snet-private-endpoints` 10.10.2.0/24 | Private endpoints for the Web Apps and SQL |
| Shared | SQL Server | `sql-uniqa-bisn5` | The *existing* server; private endpoint `pe-sql-uniqa-bisn5`; firewall allows only the admin IP |
| Shared | Private DNS zones | `privatelink.azurewebsites.net`, `privatelink.database.windows.net` | Linked to the VNet |
| Shared | Public DNS zone | `stefanovic-devops.xyz` | Azure DNS; delegated from Namecheap |
| Shared | Log Analytics | `log-uniqa` | Diagnostics and App Insights workspace |
| Shared | State storage | `stuniqatfstatebisn5` / `tfstate` | `dev.tfstate`, `test.tfstate`, `monitoring.tfstate` |
| Environment | Web App | `app-uniqa-<env>-stefanovic` | Python 3.12, gunicorn, Flask; `https://<env>.stefanovic-devops.xyz` |
| Environment | SQL database | `sqldb-uniqa-<env>` | Basic, 2 GB |
| Environment | Private endpoint | `pe-app-uniqa-<env>-stefanovic` | dev 10.10.2.5, test 10.10.2.6 |
| Environment | Application Insights | `appi-uniqa-<env>` | Codeless agent; availability test `avail-<env>-health` |
| Environment | Custom domain | `<env>.stefanovic-devops.xyz` | TXT `asuid.<env>` + CNAME, managed certificate (SNI) |
| Environment | Secrets | `SECRET_KEY` (random_password), `TransactionsDb` connection string | Only in Terraform state and App Service settings |
| Monitoring | Action group | `ag-uniqa-oncall` | E-mail receiver, common alert schema |
| Monitoring | Metric alerts | `sql-<env>-*` (5), `app-<env>-*` (3), `avail-<env>-failed` | 18 rules total |
| Delivery | Service principal | `sp-uniqa-devops-github` | Contributor on the subscription; used by `azure/login` only |
| Delivery | Workflows | CI, QA, CD - DEV, CD - TEST (promotion) | `pipelines/` mirrored to `.github/workflows/` |

## 4. Verification

- [ ] `docs/img/architecture.svg` renders in the GitHub README (no external fonts or images).
- [ ] Every name in §3 matches `terraform state list` output of the corresponding root.
- [ ] The Mermaid blocks render on GitHub (flowchart syntax only).
