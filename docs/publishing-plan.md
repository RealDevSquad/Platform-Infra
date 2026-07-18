# Publishing plan — how this becomes a (possibly public) git repo

**Current state, by decision (2026-07-18): plain files, no VCS.** Git history was
deliberately removed — the extraction snapshots contained real identifiers end to end.
Do not `git init` here until the sanitization below has run.

## 1. What must be scrubbed before the first commit

Token classes currently present in these files:

| Class | Examples in tree | Replacement |
|---|---|---|
| AWS account ID | `{{AWS_ACCOUNT_ID}}` | `{{AWS_ACCOUNT_ID}}` |
| Instance / resource IDs | instance, volumes ×6, SGs, subnet, VPC, EIP alloc/assoc, DLM policies ×3, instance-profile ID | `{{INSTANCE_ID}}`, `{{VOL_TODO_PROD}}`, … |
| IPs | EIP `{{EIP}}`, private `172.31.…` (docker subnets 172.20/172.18 are generic — keep) | `{{EIP}}`, `{{PRIVATE_IP}}` |
| Filesystem UUIDs | five fstab UUIDs | `{{UUID_…}}` (already partially elided) |
| People | Docker Hub namespace `{{DOCKERHUB_USER}}`, any names/emails | `{{DOCKERHUB_USER}}`; drop names |
| Key/vault names | key pair `{{KEY_PAIR_NAME}}`, 1Password item names, SSH alias | generalize to "the deploy key pair" |
| Bucket names | `rds-backup-prod-*` (org-guessable; decide: keep or `{{BACKUP_BUCKET_*}}`) | decide at review |

Keep as-is: public domains (`services.realdevsquad.com` — public DNS anyway), service
names, ports (path-routing is observable publicly), container names.
**Scrub too: tracker ticket IDs and tracker names** (`RDS-<n>` etc. — the issue
tracker is private, so references are dead links to outsiders; decided
2026-07-18, guard-enforced; say "tracked internally" instead).

The real values move to `private/values.env` (gitignored) — the mapping that turns the
generalized docs back into the concrete ones. Master copy can also live in 1Password.

## 2. The pipeline (run when {{MAINTAINER}} says "publish")

1. **Sanitize sweep** — scripted find/replace using the table above (`scripts/sanitize.sh`, to be written), producing an in-place generalized tree + `private/values.env`.
2. **Human review** — read the full diff; the table is a floor, not a ceiling.
3. **Automated gate** — `gitleaks detect --no-git` plus the custom regex list maintained in `scripts/sanitize.sh` (account ID, EIP octets, AWS resource-ID shapes, `AKIA`, known emails/names). Zero findings required.
4. **Fresh history** — `git init`, commit `.gitignore` first, then one initial commit of the sanitized tree. No pre-sanitization history exists to leak. The `.gitignore` floor: `private/`, `docker/.env`, `docker/env/*.env` (examples stay), `**/.terraform/`, `**/terraform.tfvars`, `*.tfstate*` (covers both `tofu/` and `tofu-prod-import/`).
5. **Push** to `Real-Dev-Squad/Infra`; enable branch protection + CODEOWNERS for `/` (workflows especially).
6. **Standing guard** — the same scan as a pre-commit hook and a CI job (gitleaks action), so post-publish commits can't reintroduce identifiers.

## 3. Open decision

Public repo (full scrub, table above) vs. **private org repo** (lighter scrub: secrets
never, IDs tolerable). The pipeline is the same; only the replacement table shrinks.
Default assumption until decided: public, full scrub.
