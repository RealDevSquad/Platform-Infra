terraform {
  # OpenTofu (decided 2026-07-18). >=1.8 for variables in import-block ids
  # and native state encryption.
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # >=6.x required: aws_dlm_lifecycle_policy default_policy
      # (SIMPLIFIED account-default DLM policy) is absent from the 5.x schema.
    }
    # cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
    # ^ enable when the zone export lands
  }

  # State backend: adopt remote state (account-discovered bucket) via
  #   cp backend.tf.example backend.tf && make init MODULE=tofu-prod-import
  # — see ../docs/remote-state.md. Until adopted: local state, which must
  # never be committed (contains real IDs after import).
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile # read-only rds-LLM suffices for import + plan
}
