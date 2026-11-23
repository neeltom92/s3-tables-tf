# s3-tables-tf

Reference implementation for Amazon S3 Tables (table buckets, namespaces, Iceberg tables) with Terraform + Terragrunt,
plus the S3 Tables integration with AWS analytics services (Glue Data Catalog).

## Read this first: this repo is a reference, not a template

Use it to learn what works and what breaks. Do **not** copy its layout or choices into another codebase as-is.

1. **Follow the target org's structure.** Its repo layout, module conventions, naming, tagging, state backend,
   CI/CD, review and apply process all take precedence over anything here. Find them first (existing repos,
   internal module registry, platform docs) and adapt the resources below to fit. If you cannot find them, ask.
2. **Check the org's supported versions before writing code.** Do not assume AWS provider 6.x, Terraform 1.15, or
   Terragrunt is available. Ask or look up: Terraform CLI version, AWS provider version (and any pin or lock file
   policy), whether Terragrunt is used, and whether public registry modules are allowed.
   Then pick the matching row in [Version compatibility](#version-compatibility).
3. **Verify, do not trust this file blindly.** Re-check provider and module docs for the exact versions in use.
   Never invent provider arguments.

## Version compatibility

Checked 2026-11-23 against the AWS provider changelog/docs and the `terraform-aws-modules/s3-bucket` source.

**AWS provider: when each S3 Tables feature arrived**

| Provider | What it adds |
|---|---|
| < 5.80 | No S3 Tables support at all |
| 5.80.0 | `aws_s3tables_table_bucket`, `_namespace`, `_table`, `_table_bucket_policy`, `_table_policy` |
| 5.98.0 | `encryption_configuration` on table bucket and table (SSE-KMS) |
| 6.2.0 | `metadata` on tables (define the Iceberg column schema in Terraform) |
| 6.11.0 | `force_destroy` on table bucket |
| 6.21.0 | `tags` on table bucket and table |
| 6.24.0 | `aws_s3tables_table_bucket_replication`, `aws_s3tables_table_replication` |
| 6.34.0 | Fix: table bucket with `encryption_configuration` unset no longer fails apply with "inconsistent result" |
| 6.44.0 | `aws_glue_catalog` (needed to manage the analytics integration in Terraform) |

`aws_s3tables_namespace` has no `tags` argument in any version checked.

**Upstream module `terraform-aws-modules/s3-bucket/aws//modules/table-bucket`: provider floor per release**

| Module | Needs provider | Notes |
|---|---|---|
| 4.8.0 – 4.11.0 | >= 5.83 (4.8) / >= 5.98 (4.9+) | Terraform >= 1.0. No tags, no table `metadata`, no `region` input |
| 5.0.0 | >= 6.0 | |
| 5.5.0 – 5.8.0 | >= 6.5 | |
| 5.10.0 | >= 6.28 | Used here. Types `tables` as `any` (see Module design) |
| 5.11.0 | >= 6.37 | |
| 5.12.0 | >= 6.39 | |
| 5.14.0 – 5.16.0 | >= 6.42 | |
| 5.17.0 – 5.18.0 | >= 6.44 | 5.18.0 types `tables` as an object |

None of these releases create namespaces.

**Picking a setup by org provider version**

- **< 5.80:** S3 Tables cannot be managed in Terraform. Upgrade the provider, or use CLI/console.
- **5.80 – 5.x:** write plain `aws_s3tables_*` resources, or use module 4.9–4.11 if provider >= 5.98.
  No schema in Terraform (create columns with Athena/Spark), no tags. In this repo's code, change
  `data.aws_region.current.region` to `.name` (the `.region` attribute is 6.x only).
- **6.x below 6.34:** works, but set `encryption_configuration` explicitly (this repo does).
- **6.x below 6.44:** analytics integration must be enabled with the CLI or console, not Terraform.
- **6.44+:** everything here works, including module 5.17/5.18.

**Terraform CLI:** module 5.x needs >= 1.5.7, module 4.x >= 1.0. This repo's own code uses `optional()` with
defaults, which needs >= 1.3.

## What this repo does

| Unit | Resources | Provider (lock file) |
|---|---|---|
| `live/dev/us-east-1/s3-tables` | table bucket, namespace, one Iceberg table with a 4-column schema, optional KMS key | 6.33.0 |
| `live/dev/us-east-1/analytics-integration` | Glue catalog `s3tablescatalog` (IAM access mode) | 6.73.0 |

Status: both units were applied, verified (Glue saw bucket/namespace/table), and then **destroyed** on 2026-11-23.
Nothing is deployed. State is local and git-ignored.

```
modules/
  s3-tables/               # bucket + namespaces + tables (+ optional KMS key)
  analytics-integration/   # aws_glue_catalog s3tablescatalog
live/
  root.hcl                 # local state, generated provider block, common tags
  dev/us-east-1/region.hcl # region local, read by root.hcl
  dev/us-east-1/<unit>/terragrunt.hcl   # values only, sources ../../../../modules/<module>
```

`modules/` hold logic, `live/` holds values only. Each unit has its own lock file, so units can run different
provider versions.

## Module design (modules/s3-tables)

- Wraps the upstream `table-bucket` module **5.10.0**, the newest release that runs on provider 6.33.
  Floor in `versions.tf`: Terraform `>= 1.5.7`, AWS `>= 6.28`. The exact version comes from the lock file.
- Upstream does not create namespaces. The module creates `aws_s3tables_namespace` and passes
  `namespace = aws_s3tables_namespace.this[...].namespace` into `tables`, so each table waits for its namespace.
- 5.10.0 types `tables` as `any` and reads it with `try()`, which does not fall back on null. The module drops
  null attributes before passing `tables` in and sets `table_name` explicitly. With 5.17+ this is not needed.
- Schema columns are a map keyed by column name: `field = { event_id = { type = "string", required = true } }`.
- No storage-class input upstream (Standard vs Intelligent-Tiering is not settable through it).
- Input validation enforces the naming rules below at plan time.

## S3 Tables rules that break plans

- Table bucket name: 3-63 characters, lowercase letters, numbers, hyphens. Unique per account + Region.
- Namespace and table names: lowercase letters, numbers, underscores. No hyphens.
- Table `format` is `"ICEBERG"`.
- Maintenance defaults: compaction target 512 MB (valid 64-512), snapshots kept 1 minimum and 120 hours maximum age,
  unreferenced files removed after 3 days, then deleted for good 10 days later.
- Quotas: 100 table buckets per Region, 10,000 namespaces and 10,000 tables per table bucket.

## Encryption

- Default is SSE-S3 (`AES256`). The module always sets `encryption_configuration` explicitly because of the
  provider < 6.34 bug above.
- **Custom KMS (SSE-KMS) is supported**, opt-in through module inputs:
  - `create_kms_key = true`: the module creates a customer-managed key (rotation on, alias
    `alias/s3tables-<bucket>`) whose policy has the account-root admin statement and the required grant to
    `maintenance.s3tables.amazonaws.com` (`kms:GenerateDataKey`, `kms:Decrypt`, condition
    `kms:EncryptionContext:aws:s3:arn` = `<bucket ARN>/*`). Wins over `kms_key_arn`.
  - `kms_key_arn = "<arn>"`: bring your own key. It needs that same maintenance grant, or `CreateTable` fails and
    compaction/snapshot maintenance stops.
- Only customer-managed keys work. The AWS-managed `aws/s3` key is not an option.
- Bucket encryption is the default for **new** tables only. Changing it is an in-place bucket update; existing
  tables keep their encryption. Moving an existing table to KMS means recreating it (data is lost).
- Readers and writers (Athena users, Glue/EMR job roles) need `kms:Decrypt` and `kms:GenerateDataKey` on the key.

## Analytics integration (modules/analytics-integration)

- Terraform equivalent of the S3 console's **Enable integration**: one `aws_glue_catalog` named
  `s3tablescatalog`, `federated_catalog { identifier = "arn:aws:s3tables:<region>:<account>:bucket/*",
  connection_name = "aws:s3tables" }`. Needs provider >= 6.44.
- Then every table bucket in the account + Region appears as `s3tablescatalog/<bucket>` (namespace = database,
  table = table). Required for Athena, Redshift, EMR, Glue ETL, Firehose, QuickSight. One per account + Region.
- **IAM access mode** here: default permissions `ALL` for `IAM_ALLOWED_PRINCIPALS`, so IAM policies alone control
  access. Lake Formation mode (per-table/column grants) needs an IAM role plus `aws_lakeformation_resource` with
  `with_federation = true`; not set up. Follow the org's data-governance model when choosing.
- If the integration was already enabled in the console, the catalog exists: import it
  (`terraform import aws_glue_catalog.s3tables s3tablescatalog`) instead of creating it.
- Provider < 6.44: enable it with the CLI instead (`aws glue create-catalog --name s3tablescatalog` with the same
  `FederatedCatalog` and default permissions; see the AWS Glue docs "Enabling S3 Tables integration").
- Not needed for PyIceberg, open-source Spark, Trino, or DuckDB through the S3 Tables Iceberg REST endpoint
  (`https://s3tables.<region>.amazonaws.com/iceberg`, warehouse = table bucket ARN, SigV4 signing name `s3tables`).

## Writing and querying data

- The console has no upload button for table buckets. Rows go in through an Iceberg engine: Athena
  `INSERT INTO`, Spark (EMR/Glue), Firehose, PyIceberg. Raw files put in the table's storage do not become rows.
- Athena: catalog `s3tablescatalog/<bucket>`, database = namespace.

## Deleting table buckets

- The console cannot delete a table bucket. Use the CLI, SDKs, or `terraform`/`terragrunt destroy`.
- A table bucket must be empty: tables, then namespaces, deleted first. Terraform orders this when it owns all three.
- After a delete, the bucket name is blocked for several minutes (`409 ConflictException ... transitional state`).
  Observed: about 8 minutes before the same name could be created again.
- After a failed apply, run `state list` and `plan` before re-running. A half-created resource is tainted, and a
  blind re-apply destroys and recreates it.

## This repo's local choices (replace with org standards)

- **State: local**, path set explicitly in `root.hcl` (`${get_terragrunt_dir()}/terraform.tfstate`), otherwise it
  lands in `.terragrunt-cache/` and is lost. One person applies at a time. Orgs normally use a remote backend
  with locking.
- **Tags:** common tags in `root.hcl` `inputs`. A unit-level `tags` input replaces the root map; to add tags, expose
  the include and `merge(include.root.locals.common_tags, {...})`.
- **Provider pin:** `versions.tf` sets a floor; the committed `.terraform.lock.hcl` per unit fixes the exact version.
- **Tools used:** Terragrunt 1.0.8 (no `run-all`/`hclfmt`; use `terragrunt run --all ...`, `terragrunt hcl fmt`),
  Terraform 1.15.7. `terragrunt run --all apply` auto-approves; use `--no-auto-approve` or apply one unit at a time.

## Rules for agents

- Never run `apply` or `destroy` unless asked. `plan` is fine.
- Never commit or push unless asked.
- Pin module and provider versions to what the org supports.
- No account IDs, real ARNs, or secrets in code. Pass them as inputs or read them from data sources.
- Check provider docs for the exact version in use before using any `aws_s3tables_*` or `aws_glue_catalog` argument.
