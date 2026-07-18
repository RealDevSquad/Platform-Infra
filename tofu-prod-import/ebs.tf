# EBS layer: root disk + 5 database data volumes, all in ap-south-1c and
# attached to the services instance. Keys here match var.volume_ids.
# Empty-tag fix applied in code (2026-07-18): the historical hand-made tags with
# EMPTY values (which the old tag-targeted DLM policies never matched) are
# removed; prod DB volumes instead set backup = true, which merges
# local.backup_tag — the SAME map aws_dlm_lifecycle_policy.snap_prod_db
# targets. Volume tags and policy targets cannot drift: one source of truth.

locals {
  # Single source of truth for "this volume gets the prod-db snapshot policy".
  # Consumed by BOTH the volume tags below AND dlm.tf's snap_prod_db target.
  backup_tag = { backup = "prod-db" }

  volumes = {
    root = {
      size      = 30
      type      = "gp2"
      encrypted = false
      device    = "/dev/sda1"
      backup    = false
      tags      = { Name = "${var.key_pair_name}-disk" }
    }
    todo_prod = {
      size      = 5
      type      = "gp3"
      encrypted = false
      device    = "/dev/sdj"
      backup    = true
      tags      = { Name = "todo-production-postgres-db" }
    }
    skilltree_prod = {
      size      = 5
      type      = "gp3"
      encrypted = true
      device    = "/dev/sdi"
      backup    = true
      tags      = { Name = "skilltree-production-db" }
    }
    tinysite_prod = {
      size      = 5
      type      = "gp3"
      encrypted = true
      device    = "/dev/sdg"
      backup    = true
      tags      = { Name = "tinysite-prod-db" }
    }
    skilltree_stg = {
      size      = 1
      type      = "gp3"
      encrypted = true
      device    = "/dev/sdh"
      backup    = false
      tags = {
        Name                   = "skilltree-staging-db"
        "staging-skilltree-db" = ""
      }
    }
    staging_shared = {
      # Name tag says tinysite, but this 1G volume hosts BOTH staging Postgres
      # instances (todo + tinysite) — see docs/aws-layer.md corrections.
      size      = 1
      type      = "gp3"
      encrypted = false
      device    = "/dev/sdf"
      backup    = false
      tags = {
        Name               = "tinysite-staging-db"
        "rds-staging-data" = ""
      }
    }
  }
}

resource "aws_ebs_volume" "data" {
  for_each = local.volumes

  availability_zone = "ap-south-1c"
  size              = each.value.size
  type              = each.value.type
  encrypted         = each.value.encrypted
  # gp3 volumes all run baseline performance; gp2 (root) computes its own.
  iops       = each.value.type == "gp3" ? 3000 : null
  throughput = each.value.type == "gp3" ? 125 : null

  tags = merge(each.value.tags, each.value.backup ? local.backup_tag : {})
}

resource "aws_volume_attachment" "data" {
  for_each = local.volumes

  device_name = each.value.device
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.services.id
}
