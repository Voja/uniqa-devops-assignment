# Bootstrap layer (shared infrastructure)

This root module provisions the **shared, "pre-existing" infrastructure** the
assignment assumes is already there: the Linux App Service Plan, the SQL
Server, the VNet with integration / private-endpoint subnets, private DNS
zones, the Log Analytics workspace, the public DNS zone, and the storage
account used as the remote Terraform backend for the per-environment root.

## Why a separate root?

- It simulates infrastructure owned by a platform team that application
  environments only *reference* (via outputs / data sources), never manage.
- Separate blast radius: `terraform destroy` of an environment can never take
  the shared plan, SQL Server or state storage with it.
- Chicken-and-egg: this root creates the remote-state storage account, so it
  cannot use it. State is **local** (`terraform.tfstate`, gitignored, contains
  the SQL admin password — keep it safe).

## Apply

```bash
cd infrastructure/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in subscription_id, admin_client_ip
az login
terraform init
terraform plan  -var-file=terraform.tfvars -out tfplan
terraform apply tfplan
```

## After apply (one manual step)

Delegate the public DNS zone at your registrar: set the domain's NS records to
the values in `terraform output dns_zone_name_servers`. Nothing in Azure can do
this for you. Then feed the other outputs (`tfstate_storage_account_name`,
`service_plan_id`, subnet / DNS zone IDs, SQL server name) into the
per-environment root's backend config and variables.
