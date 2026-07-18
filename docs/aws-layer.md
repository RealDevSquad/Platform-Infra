# AWS layer — services server

Account `{{AWS_ACCOUNT_ID}}` (Real Dev Squad), region **ap-south-1**. Extracted 2026-07-18
via the read-only `rds-LLM` role. These are the resources `tofu-prod-import/` imports.

## Compute + network

| Resource | Value |
|---|---|
| Instance | `{{INSTANCE_ID}}` — t4g.medium (arm64/aarch64), Ubuntu, launched ~2024-05-20, Name "RDS services server" |
| Key pair | `{{KEY_PAIR_NAME}}` (private key in 1Password: "EC2 RDS Services Single Box - SSH Key"; SSH alias `rds-services`, user `ubuntu`) |
| Elastic IP | `{{EIP}}` — alloc `{{EIP_ALLOC}}`, assoc `{{EIP_ASSOC}}`, Name "RDS-service-server-ip" |
| VPC / subnet | default VPC `{{VPC_ID}}` (172.31.0.0/16), subnet `{{SUBNET_ID}}`, private IP {{PRIVATE_IP}} |
| Security group | `{{SG_MAIN}}` "launch-wizard-1": inbound tcp 22, 80, 443 from 0.0.0.0/0 (nothing else; app ports 3010–4050 are host-published but blocked here) |
| Other SG | `{{SG_DEFAULT}}` default VPC SG (self-referencing, unused by the instance) |
| AMIs | none owned by the account — no golden image; rebuild = this repo |

## EBS volumes (6)

| Volume | Size/type | Device | Name tag | Purpose |
|---|---|---|---|---|
| `{{VOL_ROOT}}` | 30G gp2 | /dev/sda1 | {{KEY_PAIR_NAME}}-disk | root (48% used) |
| `{{VOL_TODO_PROD}}` | 5G gp3 | /dev/sdj | todo-production-postgres-db | todo prod Postgres data |
| `{{VOL_SKILLTREE_PROD}}` | 5G gp3 | /dev/sdi | skilltree-production-db | skilltree prod MySQL data (tag key has typo: `skilltree-prouction-db`) |
| `{{VOL_TINYSITE_PROD}}` | 5G gp3 | /dev/sdg | tinysite-prod-db | tinysite prod Postgres data |
| `{{VOL_SKILLTREE_STG}}` | 1G gp3 | /dev/sdh | skilltree-staging-db | skilltree staging MySQL data |
| `{{VOL_STAGING_SHARED}}` | 1G gp3 | /dev/sdf | tinysite-staging-db | tinysite staging Postgres data |

Mount points and container bindings: see `host-setup.md`. Corrections from the box:
the 1G "tinysite-staging-db" volume (mounted at `/mnt/ebs-staging-data`, also tagged
`rds-staging-data`) actually hosts **both** staging Postgres instances (todo +
tinysite) — its Name tag is misleading. Both RabbitMQ data dirs live on the root disk.

## DLM snapshot policies (the "42 snapshots")

| Policy | Targets | Schedule | Retention |
|---|---|---|---|
| `{{DLM_DEFAULT}}` "Default_volumes_backup" (account default, SIMPLIFIED) | **all volumes** | daily | 7 days |
| `{{DLM_TINYSITE}}` "tinysite_prod_ebs_snapshot_backup" | tag `tinysite-prod-db` | daily 09:00 UTC | count 3 |
| `{{DLM_SKILLTREE}}` "skilltree_prod_ebs_snapshot_backup" | tag `skilltree-prouction-db` (typo, matches the volume's typo'd tag) | daily 09:00 UTC | 7 days |

Note: no tag-targeted policy for `todo-production-postgres-db` — it is covered only by
the account-default all-volumes policy. AWS Backup: no plans.

## IAM

Instance profile/role `{{IAM_ROLE_BACKUP}}` (profile `{{INSTANCE_PROFILE_ID}}`).
Attached customer-managed policies (no inline):

- `{{IAM_POLICY_BACKUP_PREFIX}}-tinysite` (arn:…:policy/{{IAM_POLICY_BACKUP_PREFIX}}-tinysite)
- `{{IAM_POLICY_BACKUP_PREFIX}}-skilltree` (arn:…:policy/{{IAM_POLICY_BACKUP_PREFIX}}-skilltree)

The role can only upload DB backups. Planned additions (tracked internally):
`CloudWatchAgentServerPolicy` (observability), `AmazonSSMManagedInstanceCore` (SSM access).

## S3 (box-related buckets only)

- `{{BACKUP_BUCKET_SKILLTREE}}` — 4-hourly MySQL dumps (cron on box)
- `{{BACKUP_BUCKET_TINYSITE}}` — 4-hourly Postgres dumps (cron on box)

No lifecycle policies (unbounded growth — tracked internally). The many
`aws-sam-cli-*` / FeatureFlag / identity-service buckets belong to the Lambda stacks,
not this box.

## Off-box compute for context

`api.realdevsquad.com` (website-backend), identity-service, and FeatureFlagBackend do
NOT run on this box — identity + feature flags are Lambda stacks (see CloudWatch log
groups), website-backend is hosted elsewhere.
