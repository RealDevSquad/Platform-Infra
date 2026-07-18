# Once-per-account bootstrap: the S3 bucket that holds OpenTofu state for
# every module in this repo, plus the SSM parameter that makes its generated
# name discoverable (`make init` reads it). Run from the repo root with the
# TARGET account's credentials:
#
#   make state-bootstrap
#
# This root's own state stays local and is throwaway — the bucket is always
# rediscoverable (see README.md).

terraform {
  required_version = ">= 1.10.0" # >=1.10 for backend use_lockfile in consumers
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "bucket_prefix" {
  type        = string
  default     = "rds-tofu-state-"
  description = "AWS appends a random suffix -> globally unique, no account number in the name."
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "rds-infra", ManagedBy = "opentofu" }
  }
}

resource "aws_s3_bucket" "state" {
  bucket_prefix = var.bucket_prefix
  # No force_destroy: this bucket holds the state of real infrastructure.
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The discovery pointer: a FIXED path, identical in every account (SSM names
# are account-scoped). The account describes itself; tooling asks, not tells.
resource "aws_ssm_parameter" "state_bucket" {
  name  = "/rds/tofu/state-bucket"
  type  = "String"
  value = aws_s3_bucket.state.bucket
}

output "state_bucket" {
  value       = aws_s3_bucket.state.bucket
  description = "Generated bucket name (also written to SSM /rds/tofu/state-bucket)."
}
