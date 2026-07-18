# Import blocks — loop COMPLETED 2026-07-18: all 30 resources are
# imported into local state (via `tofu import`, read-only against AWS) and
# `tofu plan` is clean ("No changes."). The blocks below are kept as the
# durable record of what maps to what; against existing state they are no-ops.
# Re-running from scratch (fresh state): ./generate-tfvars.sh && tofu init &&
# tofu plan — rds-LLM (read-only) suffices for import + plan.
#
import {
  to = aws_instance.services
  id = var.instance_id
}
#
import {
  to = aws_eip.services
  id = var.eip_allocation_id
}

import {
  to = aws_eip_association.services
  id = var.eip_association_id
}
#
import {
  to = aws_security_group.main
  id = var.sg_main_id
}

import {
  to = aws_key_pair.deploy
  id = var.key_pair_name
}
#
import {
  to = aws_iam_role.backup
  id = var.instance_profile_name
}

import {
  to = aws_iam_instance_profile.backup
  id = var.instance_profile_name
}

import {
  for_each = var.backup_buckets
  to       = aws_iam_policy.backup[each.key]
  id       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/{{IAM_POLICY_BACKUP_PREFIX}}-${each.key}"
}

import {
  for_each = var.backup_buckets
  to       = aws_iam_role_policy_attachment.backup[each.key]
  id       = "${var.instance_profile_name}/arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/{{IAM_POLICY_BACKUP_PREFIX}}-${each.key}"
}
#
# for_each imports (volumes, DLM policies, buckets) — enable with for_each
# resources:
#
import {
  for_each = var.volume_ids
  to       = aws_ebs_volume.data[each.key]
  id       = each.value
}

import {
  for_each = var.volume_ids
  to       = aws_volume_attachment.data[each.key]
  id       = "${local.volumes[each.key].device}:${each.value}:${var.instance_id}"
}
#
# DLM: only the account-default policy remains imported. The two broken
# tag-targeted policies (tinysite/skilltree — matched nothing) were
# imported during the loop and are now REMOVED from config: the next apply
# destroys them, replaced by aws_dlm_lifecycle_policy.snap_prod_db (dlm.tf).
import {
  to = aws_dlm_lifecycle_policy.snap_default
  id = var.dlm_policy_ids["default"]
}
#
import {
  for_each = var.backup_buckets
  to       = aws_s3_bucket.backup[each.key]
  id       = each.value
}

import {
  for_each = var.backup_buckets
  to       = aws_s3_bucket_public_access_block.backup[each.key]
  id       = each.value
}
#
# Attribute source of truth while filling resources: ../docs/aws-layer.md
# (types/sizes/tags/schedules) — restore real values first if the tree is
# anonymized (scripts/sanitize.sh --restore).
