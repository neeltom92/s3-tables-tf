# Terraform equivalent of "Enable integration" for S3 Tables in the S3 console, in IAM access mode:
# registers every table bucket in this account + Region as s3tablescatalog/<bucket> in the Glue Data Catalog,
# so Athena, Redshift, EMR, Glue, and Firehose can find the tables. Access is controlled by IAM policies.
# One per account + Region.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_glue_catalog" "s3tables" {
  name        = "s3tablescatalog" # fixed name expected by AWS analytics services
  description = "Federated catalog for S3 Tables"

  federated_catalog {
    identifier      = "arn:${data.aws_partition.current.partition}:s3tables:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:bucket/*"
    connection_name = "aws:s3tables"
  }

  # IAM_ALLOWED_PRINCIPALS + ALL = IAM-only mode (no Lake Formation grants needed).
  create_database_default_permissions {
    permissions = ["ALL"]
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }

  tags = var.tags
}
