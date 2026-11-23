output "table_bucket_arn" {
  description = "ARN of the table bucket."
  value       = module.table_bucket.s3_table_bucket_arn
}

output "namespaces" {
  description = "Created namespace names."
  value       = [for n in aws_s3tables_namespace.this : n.namespace]
}

output "table_arns" {
  description = "Table ARNs, keyed by table key."
  value       = module.table_bucket.s3_table_arns
}

output "table_warehouse_locations" {
  description = "Iceberg warehouse locations, keyed by table key."
  value       = module.table_bucket.s3_table_warehouse_locations
}

output "kms_key_arn" {
  description = "KMS key used for SSE-KMS, or null when the bucket uses SSE-S3."
  value       = local.kms_key_arn
}
