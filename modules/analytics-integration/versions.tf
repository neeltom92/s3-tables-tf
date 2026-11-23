terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.44" # aws_glue_catalog first shipped in 6.44.0
    }
  }
}
