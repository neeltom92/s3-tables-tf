include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/analytics-integration"
}

# No inputs: account and Region come from the provider. Tags come from root.hcl.
