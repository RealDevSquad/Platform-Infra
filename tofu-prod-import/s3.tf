# S3 backup buckets: 4-hourly DB dumps pushed from the box by cron
# (skilltree = MySQL, tinysite = Postgres). No lifecycle rules — unbounded
# growth, tracked internally.
#
# Companion config observed live but deliberately NOT imported (all are the
# S3 post-2023 account defaults, nothing bucket-specific to manage):
#   - SSE: AES256 + bucket key enabled (aws_s3_bucket_server_side_encryption_configuration)
#   - Ownership controls: BucketOwnerEnforced (aws_s3_bucket_ownership_controls)
#   - Versioning: disabled (no aws_s3_bucket_versioning needed)
# The public-access-block IS imported below — it is explicit bucket-level
# security config on backup data.

resource "aws_s3_bucket" "backup" {
  for_each = var.backup_buckets

  bucket = each.value

  # Real tag on the skilltree bucket only: key = the bucket's own name,
  # value = the database engine dumped into it.
  tags = each.key == "skilltree" ? { (each.value) = "postgres" } : {}
}

resource "aws_s3_bucket_public_access_block" "backup" {
  # Static keys (not for_each over the bucket resource) so addresses stay
  # resolvable during CLI import / partial state.
  for_each = var.backup_buckets

  bucket = aws_s3_bucket.backup[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
