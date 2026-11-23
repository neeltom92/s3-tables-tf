output "catalog_name" {
  description = "Glue catalog that holds the S3 table buckets (s3tablescatalog/<bucket>)."
  value       = aws_glue_catalog.s3tables.name
}
