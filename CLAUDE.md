# s3-tables-tf

Terraform + Terragrunt repo for Amazon S3 Tables (table buckets, namespaces, Iceberg tables).

## Layout

```
modules/
  s3-tables/            # reusable Terraform module: no environment values in here
  analytics-integration/   # S3 Tables <-> Glue Data Catalog integration
    main.tf  variables.tf  outputs.tf  versions.tf
live/
  root.hcl              # local state config, provider, common tags
  <env>/<region>/s3-tables/terragrunt.hcl   # one unit per env: passes inputs to the module
  <env>/<region>/analytics-integration/terragrunt.hcl   # Glue s3tablescatalog (one per account + Region)
```

- `modules/` holds logic. `live/` holds values only. No resources in `live/`.
- Each `live` unit sources the module by relative path and includes `root.hcl`:
  `include "root" { path = find_in_parent_folders("root.hcl") }`
- A new environment is a new folder under `live/` with its own `terragrunt.hcl`. Do not copy module code.

## Module design

`modules/s3-tables` wraps the upstream module, pinned:

```hcl
source  = "terraform-aws-modules/s3-bucket/aws//modules/table-bucket"
version = "5.10.0"
```

5.10.0 is the newest release that runs on AWS provider 6.33 (5.11.0 needs `>= 6.37`, 5.17.0+ needs `>= 6.44`).
Checked against the v5.10.0 source:

- It needs Terraform `>= 1.5.7` and AWS provider `>= 6.28`. Set the same floor in `versions.tf`.
  The exact provider version comes from the committed `.terraform.lock.hcl` in each unit (currently 6.33.0).
- It types `tables` as `any` and reads attributes with `try()`, which does not fall back on null.
  Our module drops null attributes before passing `tables` in, and sets `table_name` explicitly.
- It creates the table bucket, tables, and both policy types. It does **not** create namespaces.
  Our module must create `aws_s3tables_namespace` itself and pass
  `namespace = aws_s3tables_namespace.this[...].namespace` into `tables`, so tables wait for the namespace.
- It has no storage-class input. Storage class (Standard or Intelligent-Tiering) is not settable through it.

## S3 Tables rules that break plans

- Table bucket name: 3-63 characters, lowercase letters, numbers, hyphens.
- Namespace and table names: lowercase letters, numbers, underscores. No hyphens.
- Table `format` is `"ICEBERG"`.
- Maintenance defaults: compaction target 512 MB (valid 64-512), snapshots kept 1 minimum and 120 hours maximum age,
  unreferenced files removed after 3 days, then deleted for good 10 days later.
- Quotas: 100 table buckets per Region, 10,000 namespaces and 10,000 tables per table bucket.

## Commands

Local tools: Terragrunt 1.0.8, Terraform 1.15.7. Terragrunt 1.0 dropped `run-all` and `hclfmt`.

```bash
terragrunt hcl fmt                    # format HCL
terraform fmt -recursive modules/     # format module code
terragrunt validate                   # in a unit folder
terragrunt plan                       # in a unit folder
terragrunt run --all plan             # every unit under the current folder
```

`terragrunt run --all apply` adds `-auto-approve` by itself. Use `--no-auto-approve`, or apply one unit at a time.

## Rules

- Never run `apply` or `destroy` unless asked. `plan` is fine.
- Never commit or push unless asked.
- Pin every module and provider version. No `latest`, no unpinned git refs.
- No account IDs, ARNs with real account numbers, or secrets in the repo. Pass them as inputs.
- Do not invent provider arguments. Check the AWS provider docs for `aws_s3tables_*` first.

## Decided

- **State: local.** No remote backend, no state bucket, no locking. Set the path explicitly in `root.hcl`,
  or the state lands inside `.terragrunt-cache/` and is lost when that folder is cleaned:

  ```hcl
  remote_state {
    backend  = "local"
    generate = { path = "backend.tf", if_exists = "overwrite" }
    config   = { path = "${get_terragrunt_dir()}/terraform.tfstate" }
  }
  ```

  `.gitignore` covers `*.tfstate*`, `.terragrunt-cache/` and `.terraform/`. Local state means one person applies at a time.

- **Encryption: SSE-S3 by default, custom KMS supported (opt-in).** The default for every table bucket is SSE-S3
  (S3-managed keys). The module always sets `encryption_configuration` explicitly, because AWS provider < 6.34
  fails the apply with "inconsistent result" when it is unset.

  **SSE-KMS with a customer-managed key is supported** through two module inputs:

  ```hcl
  # unit terragrunt.hcl inputs, pick one
  create_kms_key = true                          # module creates key + alias + key policy
  kms_key_arn    = "<existing customer-managed key ARN>"   # bring your own key
  ```

  - Neither set: SSE-S3 (`AES256`). This is what `dev/us-east-1` uses today.
  - `create_kms_key = true` wins over `kms_key_arn`. The created key has rotation on, alias
    `alias/s3tables-<bucket>`, and a key policy with the account-root admin statement plus the required
    `maintenance.s3tables.amazonaws.com` grant (`kms:GenerateDataKey`, `kms:Decrypt`, scoped by
    `kms:EncryptionContext:aws:s3:arn` = `<bucket ARN>/*`).
  - A key you bring must have that same maintenance grant, or `CreateTable` fails and compaction/snapshot
    maintenance stops. The AWS-managed `aws/s3` key is not supported: S3 Tables has no "default KMS key" option.
  - Bucket encryption is the default for **new** tables only. Switching it is an in-place bucket update
    (checked with `plan`); existing tables keep their encryption. To move an existing table to KMS, recreate it
    (that deletes its data).
  - Anyone reading or writing KMS tables (Athena users, Glue/EMR job roles) also needs `kms:Decrypt` and
    `kms:GenerateDataKey` on the key.

- **Tags.** Common tags live in `root.hcl` and reach every unit. A unit that needs more must merge them itself:
  a plain `tags` input in a unit replaces the root map, it does not add to it.

  ```hcl
  # root.hcl
  locals { common_tags = { owner = "neel" } }
  inputs = { tags = local.common_tags }

  # unit terragrunt.hcl, only when it needs extra tags
  include "root" {
    path   = find_in_parent_folders("root.hcl")
    expose = true
  }
  inputs = { tags = merge(include.root.locals.common_tags, { team = "data" }) }
  ```

  The module takes `tags` (`map(string)`) and passes it to the upstream module, which tags the table bucket and
  merges the same tags into every table. Check the provider docs before tagging `aws_s3tables_namespace`.

## Not decided yet

Ask before writing code that depends on these:

- AWS account, Region, and environment names (`dev`, `prod`, ...).
- Who reads the tables (Athena, EMR, Glue catalog integration) and the IAM policies that follow.

## AWS analytics integration (Terraform unit)

- Managed by `modules/analytics-integration` + `live/dev/us-east-1/analytics-integration`. It is the Terraform
  equivalent of the S3 console's **Enable integration** button: one `aws_glue_catalog` named `s3tablescatalog`,
  federated to `arn:aws:s3tables:<region>:<account>:bucket/*` with connection `aws:s3tables`.
- Every table bucket in the account + Region then shows up as `s3tablescatalog/<bucket>` (namespace = database,
  table = table). Athena, Redshift, EMR, Glue ETL, Firehose, and QuickSight need this.
- **IAM access mode**: default permissions `ALL` for `IAM_ALLOWED_PRINCIPALS`, so access is controlled by IAM
  policies alone. Lake Formation mode (per-table/column grants, IAM role + `aws_lakeformation_resource` with
  `with_federation = true`) is not set up. The console button sets up Lake Formation mode instead.
- One per account + Region. If the integration was already enabled in the console, `apply` fails because the
  catalog exists: import it (`terragrunt import aws_glue_catalog.s3tables s3tablescatalog`) or skip this unit.
- `aws_glue_catalog` first shipped in AWS provider **6.44.0**, so this unit needs `>= 6.44` (lock file: 6.73.0),
  while the `s3-tables` unit stays on 6.33.0. Each unit has its own lock file, so the two do not conflict.
- Not needed for PyIceberg, open-source Spark, Trino, or DuckDB through the S3 Tables Iceberg REST endpoint
  (`https://s3tables.<region>.amazonaws.com/iceberg`, warehouse = bucket ARN, SigV4 signing name `s3tables`).
- Console has no upload button for table buckets: rows go in through an engine (Athena `INSERT INTO`, Spark,
  Firehose, PyIceberg).

## Deleting table buckets

- The console cannot delete a table bucket. Use the AWS CLI, SDKs, REST API, or `terragrunt destroy` in the unit.
- A table bucket must be empty (tables, then namespaces, deleted first). Terraform handles the order when it
  owns all three.
- After a delete, the bucket name is blocked for several minutes (`409 ConflictException ... transitional
  state`). Seen 2026-11-23: about 8 minutes before the same name could be created again.
- After a failed apply, check `terragrunt state list` and the plan before re-running: a half-created resource is
  tainted, and a blind re-apply destroys and recreates it.
