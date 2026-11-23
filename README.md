# s3-tables-tf

Terraform + Terragrunt for Amazon S3 Tables (Iceberg): table bucket, namespaces, tables, and the
S3 Tables integration with AWS analytics services (Glue Data Catalog).

This is a reference implementation. In another codebase, follow that org's structure and supported
Terraform/provider versions; [CLAUDE.md](CLAUDE.md) has the version compatibility table.

Current state: nothing deployed (applied, verified, then destroyed).

## What it creates (dev, us-east-1)

| Unit | Resources | AWS provider |
|---|---|---|
| `live/dev/us-east-1/s3-tables` | table bucket `neel-dev-iceberg`, namespace `demo_neel`, Iceberg table `events` | 6.33.0 |
| `live/dev/us-east-1/analytics-integration` | Glue catalog `s3tablescatalog` (IAM access mode) | 6.73.0 |

The analytics integration makes every table bucket in the account + Region visible to Athena, Redshift, EMR,
Glue, Firehose, and QuickSight as `s3tablescatalog/<bucket>`. It is one per account + Region.

## Run

Needs Terraform >= 1.5.7, Terragrunt 1.x, and AWS credentials for the target account.

```bash
cd live/dev/us-east-1/s3-tables && terragrunt plan     # then: terragrunt apply
cd live/dev/us-east-1/analytics-integration && terragrunt plan
```

State is local (`terraform.tfstate` in each unit folder, git-ignored). One person applies at a time;
keep a backup of the state files.

## Change things

- Tables, namespaces, bucket name: edit `live/dev/us-east-1/s3-tables/terragrunt.hcl`.
- Custom KMS instead of SSE-S3: add `create_kms_key = true` (or `kms_key_arn = "..."`) to that unit's inputs.
  Only new tables pick it up.
- New environment or Region: copy a `live/<env>/<region>/` folder and change `region.hcl` and the inputs.

## Write and query data

The console has no upload button for table buckets. Rows go in through an Iceberg engine:

- Athena: catalog `s3tablescatalog/neel-dev-iceberg`, database `demo_neel`, then
  `INSERT INTO events VALUES (...)` and `SELECT * FROM events`.
- PyIceberg / Spark / Trino: S3 Tables Iceberg REST endpoint `https://s3tables.us-east-1.amazonaws.com/iceberg`,
  warehouse = table bucket ARN, SigV4 signing name `s3tables`.

Gotchas (provider bugs, deleting buckets, version pins) are in [CLAUDE.md](CLAUDE.md).
