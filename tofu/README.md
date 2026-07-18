# tofu/ — the box module (creates a fresh services box)

**This is where we want to be**: every services box — the sandbox today, the
production successor tomorrow — created from this one module. (The one-to-one
import of the box that exists today lives in `../tofu-prod-import/`, and gets
deleted once this module has replaced it.)

OpenTofu that **creates** everything a services box needs, from scratch, in
whatever AWS account you point it at: default-VPC placement, security group
(80/443 public, optional 22 from `admin_cidr`), IAM role with SSM Session
Manager (keyless shell), latest Ubuntu 24.04 arm64 AMI (auto-resolved),
Elastic IP, and a backup S3 bucket.

Consumers, in order:

1. **Sandbox account** (now) — your separate dev account; full runbook
   in `../docs/sandbox-account.md`.
2. **Prod successor** (later) — same module, prod account, then DNS
   cutover per `../docs/new-box-bootstrap.md`.

```bash
cp terraform.tfvars.example terraform.tfvars   # subdomain + region (+ optional admin_cidr / ssh key)
tofu init && tofu plan && tofu apply           # with the TARGET account's credentials
```

`apply` prints the EIP, the exact DNS record to create, the `SITE_ADDRESS=`
line for `docker/.env`, and an `aws ssm start-session` command. `tofu destroy`
removes everything (the bucket has `force_destroy = true`).

State is local (`terraform.tfstate` — holds your account's IDs, never commit).
This module is greenfield-only; the *existing* hand-built prod box is described
by [`../tofu-prod-import/`](../tofu-prod-import/), which imports it and dies with it.

## DRY decision (2026-07-18): one flat module, no `common/` — for now

- **Never shared with `../tofu-prod-import/`.** Only ~30–40 boilerplate lines
  actually overlap (provider block, egress rule, bucket access-block flags).
  The real resources differ in shape *and in purpose*: the import's definition
  of correct is "matches the existing box exactly, warts included"; this
  module's is "is a good box". Improving one must not change the other, so a
  shared abstraction would couple opposite change-reasons. It would also force
  `tofu state mv` on all 30 imported prod-guarding resources (module addresses
  differ) for zero behavior gain — on a directory scheduled for deletion.
- **Within this module: restructure when the second consumer arrives.** The
  moment the prod-successor root is created, split into
  `modules/box/` + `envs/sandbox/` + `envs/prod/` (thin roots: tfvars + state).
  That refactor is cheap then — only create-mode, disposable state is involved.
  Until then, one consumer means the flat layout *is* the DRY layout.
