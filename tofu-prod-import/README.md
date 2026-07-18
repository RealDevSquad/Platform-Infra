# tofu-prod-import/ — the existing prod box, imported (import loop DONE 2026-07-18)

> **Temporary by design — this directory will one day be deleted.** Right now it
> is a **one-to-one copy of what exists in our system**: every AWS resource of
> the hand-built box currently serving production, imported as-is (`tofu plan` =
> "No changes.", 30 resources), warts included. It builds nothing — it exists so
> reality is written down and drift is visible. [`../tofu/`](../tofu/) is
> **where we want to be**: boxes created from code, not described after the
> fact. When the box this imports is replaced and decommissioned, this directory
> goes with it. (Renamed from `tofu/` on 2026-07-18.)

Deliberately **not** DRY'd against `../tofu/` — the overlap is boilerplate
only, and the two have opposite change-reasons (this must match reality; that
must be a good box). Full reasoning: the DRY note in `../tofu/README.md`.

Engine: **OpenTofu** (decided 2026-07-18; pin via `required_version` +
`opentofu/setup-opentofu`). State: S3 in account {{AWS_ACCOUNT_ID}}, locked + encrypted
(OpenTofu native state encryption) — **still to be configured; state is local
for now** (`terraform.tfstate`, mode 600, never commit — real IDs). Strategy:
`tofu import` everything below — recreate nothing. Full attribute detail:
`../docs/aws-layer.md`.

Status: all 30 AWS resources below are imported and `tofu plan` reports
**"No changes."** against the live account (read-only `rds-LLM` profile).
Cloudflare remains blocked on the zone export. Notes:

- Provider pinned `~> 6.0` (bumped from 5.x): the account-default DLM policy
  is a SIMPLIFIED-language policy, which only provider 6.x can model.
- Two unavoidable `lifecycle.ignore_changes` escapes, both provider
  limitations, documented inline: `aws_key_pair.deploy` (`public_key` never
  read back; Required+ForceNew) and `aws_dlm_lifecycle_policy.snap_default`
  (`default_policy` write-only but required with SIMPLIFIED fields).
- S3 companions imported: per-bucket public-access-block (all four flags on).
  Observed but deliberately unmodeled (account defaults): SSE AES256 + bucket
  key, ownership controls BucketOwnerEnforced, versioning disabled.

## Import checklist

| Resource type | ID |
|---|---|
| aws_instance | `{{INSTANCE_ID}}` |
| aws_eip | `{{EIP_ALLOC}}` |
| aws_eip_association | `{{EIP_ASSOC}}` |
| aws_security_group | `{{SG_MAIN}}` |
| aws_key_pair | `{{KEY_PAIR_NAME}}` |
| aws_iam_role + instance profile | `{{IAM_ROLE_BACKUP}}` |
| aws_iam_policy ×2 | `{{IAM_POLICY_BACKUP_PREFIX}}-tinysite`, `{{IAM_POLICY_BACKUP_PREFIX}}-skilltree` |
| aws_ebs_volume ×6 (+ attachments) | see docs/aws-layer.md table |
| aws_dlm_lifecycle_policy ×3 | `{{DLM_DEFAULT}}`, `{{DLM_TINYSITE}}`, `{{DLM_SKILLTREE}}` |
| aws_s3_bucket ×2 | `{{BACKUP_BUCKET_SKILLTREE}}`, `{{BACKUP_BUCKET_TINYSITE}}` |
| cloudflare_record (zone realdevsquad.com) | after the zone export (docs/dns.md) |

Acceptance: `tofu plan` clean against the live account.
