# s3-tables-tf

Terraform + Terragrunt repo for Amazon S3 Tables (table buckets, namespaces, Iceberg tables).

## Layout

```
modules/
  s3-tables/            # reusable Terraform module: no environment values in here
    main.tf  variables.tf  outputs.tf  versions.tf
live/
  root.hcl              # local state config, provider, common tags
  <env>/<region>/s3-tables/terragrunt.hcl   # one unit per env: passes inputs to the module
```

- `modules/` holds logic. `live/` holds values only. No resources in `live/`.
- Each `live` unit sources the module by relative path and includes `root.hcl`:
  `include "root" { path = find_in_parent_folders("root.hcl") }`
- A new environment is a new folder under `live/` with its own `terragrunt.hcl`. Do not copy module code.

## Module design

`modules/s3-tables` wraps the upstream module, pinned:

```hcl
source  = "terraform-aws-modules/s3-bucket/aws//modules/table-bucket"
version = "5.18.0"
```

Checked against the v5.18.0 source:

- It needs Terraform `>= 1.5.7` and AWS provider `>= 6.44`. Set the same floor in `versions.tf`.
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

- **Encryption: the AWS default.** Leave `encryption_configuration` unset. The default for every table bucket is
  SSE-S3 (S3-managed keys), not KMS. S3 Tables has no "default KMS key" option: SSE-KMS means a customer-managed key,
  plus a key policy grant for `maintenance.s3tables.amazonaws.com`. Do not add a KMS key unless asked.

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
