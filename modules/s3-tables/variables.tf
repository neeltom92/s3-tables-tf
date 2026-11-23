variable "table_bucket_name" {
  description = "Name of the S3 table bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.table_bucket_name))
    error_message = "Table bucket name must be 3-63 characters: lowercase letters, numbers, hyphens."
  }
}

variable "namespaces" {
  description = "Namespaces to create in the table bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.namespaces : can(regex("^[a-z0-9][a-z0-9_]*[a-z0-9]$|^[a-z0-9]$", n))])
    error_message = "Namespace names may contain only lowercase letters, numbers, and underscores."
  }
}

variable "maintenance_configuration" {
  description = "Bucket-level maintenance (unreferenced file removal). Null keeps the AWS defaults."
  type = object({
    iceberg_unreferenced_file_removal = object({
      settings = object({
        non_current_days  = number
        unreferenced_days = number
      })
      status = string
    })
  })
  default = null
}

variable "tables" {
  description = "Iceberg tables, keyed by table name. `namespace` must be listed in var.namespaces."
  type = map(object({
    namespace  = string
    table_name = optional(string)
    format     = optional(string, "ICEBERG")
    tags       = optional(map(string), {})

    maintenance_configuration = optional(object({
      iceberg_compaction = optional(object({
        settings = optional(object({
          target_file_size_mb = optional(number)
        }))
        status = optional(string)
      }))
      iceberg_snapshot_management = optional(object({
        settings = optional(object({
          max_snapshot_age_hours = optional(number)
          min_snapshots_to_keep  = optional(number)
        }))
        status = optional(string)
      }))
    }))

    metadata = optional(object({
      iceberg = optional(object({
        schema = optional(object({
          # Map key is the column name.
          field = optional(map(object({
            type     = string
            required = optional(bool)
          })), {})
        }))
      }))
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k, t in var.tables : can(regex("^[a-z0-9_]+$", coalesce(t.table_name, k)))])
    error_message = "Table names may contain only lowercase letters, numbers, and underscores."
  }
}

variable "create_kms_key" {
  description = "Create a customer-managed KMS key (with the S3 Tables maintenance grant) and use SSE-KMS. Wins over kms_key_arn."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Existing customer-managed KMS key for SSE-KMS. Its key policy must allow maintenance.s3tables.amazonaws.com kms:GenerateDataKey and kms:Decrypt. Null with create_kms_key = false means SSE-S3."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the table bucket and every table."
  type        = map(string)
  default     = {}
}
