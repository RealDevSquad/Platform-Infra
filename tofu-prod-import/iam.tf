# IAM layer: the instance role that uploads DB backups to S3.
# Role/profile/policy names are not anonymized (they appear as literals in
# docs/aws-layer.md); bucket names ARE — they come through var.backup_buckets.

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "backup" {
  name        = var.instance_profile_name
  description = "Allows EC2 instances to call AWS services on your behalf.\nUploads data to s3, for database backup"
  path        = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backup" {
  name = var.instance_profile_name
  path = "/"
  role = aws_iam_role.backup.name
}

# Two customer-managed policies, one per backup bucket. Documents fetched via
# `aws iam get-policy-version` (v1, 2026-07-18). The description wording
# differs between the two ("to s3 bucket" vs "s3 bucket") — kept verbatim.
locals {
  backup_policy_descriptions = {
    tinysite  = "Policy to upload data to ${var.backup_buckets["tinysite"]} to s3 bucket"
    skilltree = "Policy to upload data to ${var.backup_buckets["skilltree"]} s3 bucket"
  }
}

resource "aws_iam_policy" "backup" {
  for_each    = var.backup_buckets
  name        = "{{IAM_POLICY_BACKUP_PREFIX}}-${each.key}"
  path        = "/"
  description = local.backup_policy_descriptions[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObjectAcl",
          "s3:GetObject",
          "s3:DeleteObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectTagging",
          "s3:DeleteObject",
          "s3:PutObjectAcl",
          "s3:GetObjectVersion",
        ]
        Resource = "arn:aws:s3:::${each.value}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  # Static keys (not for_each over the policy resource) so addresses stay
  # resolvable during CLI import / partial state.
  for_each   = var.backup_buckets
  role       = aws_iam_role.backup.name
  policy_arn = aws_iam_policy.backup[each.key].arn
}
