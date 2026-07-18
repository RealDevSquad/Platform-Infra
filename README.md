# Infra

Infrastructure-as-code and documentation for the Real Dev Squad **services server** —
the single EC2 box behind `services.realdevsquad.com` that runs all containerized
backend services (production + staging).

**Goal:** rebuilding this box is a 1-2-3 process from this repo, and any subset of it
runs locally with one flag (`COMPOSE_PROFILES=todo docker compose up`).

> **Plain files — deliberately no VCS yet.** Extraction snapshots contain real
> identifiers; `docs/publishing-plan.md` defines the sanitize → fresh-init → push
> pipeline. Do not `git init` before running it. Created 2026-07-18 from the live-box
> extraction.

**Ground rule:** the documentation/extraction phase is strictly **read-only against the
production box** — nothing on the machine is modified by this project. Every fix or
install (restart policies, pruning, Caddy edits, monitoring agents) is tracked
internally and happens only as its own explicitly approved change, never as a side effect.

## Layout

| Path | Contents |
|---|---|
| `docs/deployment-map.md` | The complete as-is map: 5 services × 2 envs, ports, Caddy routes, wiring, CI pipelines, drift findings |
| `docs/aws-layer.md` | Every AWS resource the box depends on (instance, EIP, SG, IAM, volumes, DLM, S3) — feeds `tofu-prod-import/` |
| `docs/secrets.md` | Every env var by name: kind, storage location, consumer. **Names only, never values** |
| `docs/dns.md` | realdevsquad.com DNS as observed; Cloudflare export pending |
| `docker/` | **The one way to bring machines up** — single Compose project: base (Caddy) + per-service profiles, `compose.local.yaml` (laptop) and `compose.prod.yaml` (server) overlays. Both proven 2026-07-18 |
| `tofu/` | **The box module — where we want to be**: every box (sandbox now, prod successor later) is *created* from here (instance, SG, IAM+SSM, EIP, backup bucket) |
| `tofu-prod-import/` | **Temporary, will be deleted**: a one-to-one imported copy of the prod box exactly as it exists today (`tofu plan` clean, 30 resources). Gone once `tofu/` has replaced that box |
| `tofu-state-bootstrap/` | Once per account: creates the remote-state bucket (`rds-tofu-state-<random>`) + its SSM discovery pointer — `make state-bootstrap`, then `make init MODULE=…` (`docs/remote-state.md`) |
| `scripts/` | `bootstrap.sh` (fresh-box provisioner), `sanitize.sh` (anonymize/restore) |
| `docs/new-box-bootstrap.md` | The 1-2-3 rebuild: launch → `bootstrap.sh` → verify → DNS cutover. Legacy box never touched |
| `mirror/` | Verbatim as-is snapshots of the hand-built legacy box — **reference only, never a bring-up path**; see `mirror/README.md` |
| `runbooks/` | Reviewed change packages for on-box changes (currently parked — new-box strategy supersedes them) |

## Conventions (the navigation contract)

- **Every directory has a `README.md`** answering: what this is, how to use it, status/tickets. If you're lost, read the nearest README.
- **Filenames are kebab-case**; `README.md` is the only uppercase name.
- **Environment variants use a suffix**: `compose.local.yaml`, `Caddyfile.local` (future: `.prod`). Base file = no suffix.
- **Templates end in `.example`** (committed); the live copies (`env/*.env`, `.env`, `terraform.tfvars`) are machine-local and never committed.
- **Target-state vs as-is**: `docker/` + `tofu/` define machines to build; `tofu-prod-import/` pins the existing box in code; `mirror/` only records it as found. Never bring anything up from `mirror/`.
- **Generated artifacts** (`tofu*/.terraform/`, tfvars, live env files) are listed in the publishing plan's `.gitignore` floor.

## Rebuild sketch (target end-state)

1. `tofu apply` — instance, EIP, SG, IAM, volumes, DLM, S3, DNS.
2. `scripts/bootstrap.sh` — docker, networks, mounts, secrets from their store.
3. `docker compose --profile all up -d` + restore data from S3/EBS snapshots; point CI at the box.

## Status (2026-07-18)

- [x] Deployment map (services, ports, routing, CI)
- [x] Caddy config mirrored
- [x] AWS layer documented (incl. 6 EBS volumes + 3 DLM snapshot policies)
- [x] secrets.md v1 (GitHub-side complete; on-box entries pending)
- [x] DNS as-observed
- [x] On-box: rabbitmq compose (mirrored), backup scripts (mirrored, redacted), DB init model, host facts, EBS mount map (`docs/host-setup.md`)
- [x] `/etc/fstab` + mount options + package set (in `docs/host-setup.md`)
- [x] Anonymization pass (`scripts/sanitize.sh`, mapping outside repo; round-trip verified)
- [x] `docker/` scaffolded: base + 4 profiles + local overlay + env templates — `docker compose config` valid, live `up` test pending
- [x] `tofu-prod-import/` scaffolded: providers, variables, tfvars generator, import scaffold — `tofu validate` passing; import→plan loop pending
- [x] Local acceptance PASSED (2026-07-18): all 4 profiles up — 11/11 containers, every route app-served through Caddy; recovery drill proved `make up` + surviving volumes rebuild the stack. `scripts/validate-stack.sh` = repeatable 9-check matrix (+3 authed checks awaiting real tokens); local HTTPS (Caddy internal CA) verified on every route
- [x] Import loop DONE — `tofu plan` "No changes.", 30 resources; DLM redesign coded, plan ready (1 add/3 change/2 destroy) awaiting admin `tofu apply`
- [x] New-box path: `compose.prod.yaml` + `Caddyfile.prod` validated, `scripts/bootstrap.sh`, `docs/new-box-bootstrap.md`. Legacy box strategy = never modify; replace + DNS cutover
- [x] Config model designed local-first (`docs/config-model.md`): env file = contract, providers pluggable, SSM server-only
- [x] `scripts/render-env.sh` reviewed + repaired: truncated main + f-string syntax fixed; offline-fallback contract tested 2026-07-18
- [x] **Sandbox account stand-up DONE** (2026-07-18): fresh account → `tofu apply` (9 resources) → repo via S3-presign bounce → `bootstrap.sh` ×2 → 7 containers (todo+discord profiles, t4g.small + swap) → real ACME cert behind Cloudflare (orange, Full strict) → `/todo/api/schema` 200 over public TLS. Full-chain proof of the repo thesis
- [x] Remote state + mode separation: account-discovered state bucket (`tofu-state-bootstrap/` + `make init`), `backend.tf.example` adoption, `ENV_PROVIDER` gate, EC2-only bootstrap gate — per-account adoption pending (`docs/remote-state.md`)
- [ ] `tofu/ssm.tf` parameter tree from `docs/secrets.md` (config-model phase 3)
- [ ] Throwaway-EC2 end-to-end bootstrap test (largely covered by the sandbox stand-up)
- [ ] Cloudflare DNS export (user-side; also feeds tofu DNS + cutover docs)
- [ ] Deploy workflows consume this repo
- [ ] Open decisions: shell-access model · public-vs-private repo/publish · Atlas backup tier check
- [ ] **Sanitize review → git init → push** per `docs/publishing-plan.md` (on {{MAINTAINER}}'s go)
