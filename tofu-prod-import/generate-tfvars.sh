#!/usr/bin/env bash
# Generate terraform.tfvars from the private mapping (../../.infra-private/values.env).
# terraform.tfvars contains REAL identifiers — it is never committed
# (covered by .gitignore at publish time, per docs/publishing-plan.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES="${INFRA_VALUES:-$(cd "$HERE/../.." && pwd)/.infra-private/values.env}"
[ -f "$VALUES" ] || { echo "mapping not found: $VALUES" >&2; exit 1; }

# shellcheck disable=SC1090
set -a; source "$VALUES"; set +a

cat > "$HERE/terraform.tfvars" <<EOF
instance_id        = "${INSTANCE_ID}"
eip_allocation_id  = "${EIP_ALLOC}"
eip_association_id = "${EIP_ASSOC}"
sg_main_id         = "${SG_MAIN}"
subnet_id          = "${SUBNET_ID}"
vpc_id             = "${VPC_ID}"
key_pair_name      = "${KEY_PAIR_NAME}"

volume_ids = {
  root           = "${VOL_ROOT}"
  todo_prod      = "${VOL_TODO_PROD}"
  skilltree_prod = "${VOL_SKILLTREE_PROD}"
  tinysite_prod  = "${VOL_TINYSITE_PROD}"
  skilltree_stg  = "${VOL_SKILLTREE_STG}"
  staging_shared = "${VOL_STAGING_SHARED}"
}

dlm_policy_ids = {
  default   = "${DLM_DEFAULT}"
  tinysite  = "${DLM_TINYSITE}"
  skilltree = "${DLM_SKILLTREE}"
}

backup_buckets = {
  skilltree = "${BACKUP_BUCKET_SKILLTREE}"
  tinysite  = "${BACKUP_BUCKET_TINYSITE}"
}
EOF

chmod 600 "$HERE/terraform.tfvars"
echo "wrote $HERE/terraform.tfvars (mode 600 — never commit)"
