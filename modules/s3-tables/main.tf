module "table_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/table-bucket"
  version = "5.10.0" # newest release that supports AWS provider < 6.37

  table_bucket_name         = var.table_bucket_name
  maintenance_configuration = var.maintenance_configuration
  tags                      = var.tags

  # Default for new tables in the bucket. Always set (even for SSE-S3) because AWS provider < 6.34
  # fails the apply ("inconsistent result") when it is left unset.
  encryption_configuration = (
    local.kms_key_arn == null
    ? { sse_algorithm = "AES256", kms_key_arn = null }
    : { sse_algorithm = "aws:kms", kms_key_arn = local.kms_key_arn }
  )

  # Referencing the namespace resource makes each table wait for its namespace.
  # Upstream types `tables` as `any` and reads it with try(), which does not skip nulls,
  # so unset optional attributes are dropped here instead of passed as null.
  tables = {
    for k, t in var.tables : k => {
      for attr, val in merge(t, {
        table_name = coalesce(t.table_name, k)
        namespace  = aws_s3tables_namespace.this[t.namespace].namespace
      }) : attr => val if val != null
    }
  }
}

# Upstream module does not create namespaces.
resource "aws_s3tables_namespace" "this" {
  for_each = toset(var.namespaces)

  namespace        = each.value
  table_bucket_arn = module.table_bucket.s3_table_bucket_arn
}

# --- Optional SSE-KMS with a customer-managed key ---

locals {
  kms_key_arn = var.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn

  # Built from inputs, not the module output, so the key policy does not depend on the bucket.
  table_bucket_arn = "arn:${data.aws_partition.current.partition}:s3tables:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:bucket/${var.table_bucket_name}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description         = "S3 Tables encryption for table bucket ${var.table_bucket_name}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms[0].json
  tags                = var.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/s3tables-${var.table_bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key ? 1 : 0

  # Default key policy statement: the account administers the key through IAM. Without it the key is unmanageable.
  statement {
    sid       = "EnableIAMUserPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Required by S3 Tables: CreateTable fails and maintenance (compaction, snapshot expiry) stops without it.
  statement {
    sid       = "S3TablesMaintenance"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["maintenance.s3tables.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${local.table_bucket_arn}/*"]
    }
  }
}
