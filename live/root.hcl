locals {
  region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals.region

  common_tags = {
    owner      = "neel"
    project    = "demo-neel"
    managed_by = "terragrunt"
  }
}

remote_state {
  backend  = "local"
  generate = { path = "backend.tf", if_exists = "overwrite" }
  config   = { path = "${get_terragrunt_dir()}/terraform.tfstate" }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
    }
  EOT
}

inputs = {
  tags = local.common_tags
}
