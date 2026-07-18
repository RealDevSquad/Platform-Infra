# DLM snapshot policies (imported; empty-tag redesign applied in code).
#   snap_default — account-default policy (SIMPLIFIED language), all volumes,
#                  daily, 7-day retention: kept verbatim as the backstop
#                  (it is what covers the root disk). Requires aws >= 6.x.
#   snap_prod_db — NEW unified policy replacing the two broken tag-targeted
#                  ones: targets local.backup_tag, the SAME map the prod DB
#                  volumes merge into their tags (ebs.tf) — policy and volumes
#                  cannot drift. Daily 00:20 UTC keep 7 + weekly Sunday keep 4,
#                  copy_tags on. Snapshots land ~20 min after the 00:00 UTC
#                  SQL-dump cron, so each one contains a fresh dump.
#
# History (why the old ones were removed): the imported snap_tinysite and
# snap_skilltree policies targeted tag key=value pairs, but the volumes carried
# those keys with EMPTY values — the filters matched NOTHING, ever. Every
# existing snapshot came from snap_default alone. Applying this file destroys
# those two no-op policies. Verified 2026-07-18 via aws dlm get-lifecycle-policy
# + volume describes.

locals {
  dlm_execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AWSDataLifecycleManagerDefaultRole"
}

resource "aws_dlm_lifecycle_policy" "snap_default" {
  description        = "Default_volumes_backup"
  execution_role_arn = local.dlm_execution_role_arn
  state              = "ENABLED"
  default_policy     = "VOLUME"

  lifecycle {
    # Unavoidable: default_policy is write-only in the provider (never read
    # back into state, so it stays null after import → permanent spurious
    # in-place update), yet provider validation REQUIRES it whenever the
    # SIMPLIFIED policy_details fields below are set. ignore_changes is the
    # only way to keep the faithful create-time config AND a clean plan.
    ignore_changes = [default_policy]
  }

  policy_details {
    policy_type     = "EBS_SNAPSHOT_MANAGEMENT"
    policy_language = "SIMPLIFIED"
    resource_type   = "VOLUME"
    create_interval = 1
    retain_interval = 7
    copy_tags       = false
    extend_deletion = false

    exclusions {
      exclude_boot_volumes = false
      exclude_tags         = {}
      exclude_volume_types = []
    }
  }

  tags = {
    Name = "Default_all_volumes_backup"
  }
}

resource "aws_dlm_lifecycle_policy" "snap_prod_db" {
  description        = "prod-db-snapshots unified"
  execution_role_arn = local.dlm_execution_role_arn
  state              = "ENABLED"

  policy_details {
    policy_type        = "EBS_SNAPSHOT_MANAGEMENT"
    resource_types     = ["VOLUME"]
    resource_locations = ["CLOUD"]

    # THE fix: same map the prod DB volumes merge into their tags (ebs.tf
    # local.backup_tag). Adding backup = true to any future volume enrolls it
    # here automatically — no second place to keep in sync.
    target_tags = local.backup_tag

    schedule {
      name      = "daily keep 7"
      copy_tags = true

      create_rule {
        location      = "CLOUD"
        interval      = 24
        interval_unit = "HOURS"
        times         = ["00:20"] # ~20 min after the 00:00 UTC dump cron
      }

      retain_rule {
        count = 7
      }
    }

    schedule {
      name      = "weekly keep 4"
      copy_tags = true

      create_rule {
        location        = "CLOUD"
        cron_expression = "cron(40 0 ? * SUN *)"
      }

      retain_rule {
        count = 4
      }
    }
  }

  tags = {
    Name = "prod-db-snapshots"
  }
}
