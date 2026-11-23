include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/s3-tables"
}

inputs = {
  table_bucket_name = "neel-dev-iceberg"
  namespaces        = ["demo_neel"]

  tables = {
    events = {
      namespace = "demo_neel"
      metadata = {
        iceberg = {
          schema = {
            field = {
              event_id = { type = "string", required = true }
              event_ts = { type = "timestamp", required = true }
              user_id  = { type = "string" }
              payload  = { type = "string" }
            }
          }
        }
      }
    }
  }
}
