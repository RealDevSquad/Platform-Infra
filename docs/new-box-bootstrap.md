# New-box bootstrap — the 1-2-3 rebuild

Strategy (decided 2026-07-18): **the legacy box is never modified.** Its
successor is built from this repo, tested while the old box still serves
traffic, and takes over via DNS cutover. Everything below is testable before
any user notices anything.

## 1 — Launch the instance

Preferred: `tofu/` (the box module — same proven path as `docs/sandbox-account.md`)
pointed at the target account. Console/CLI equivalent, if launching by hand:

| Setting | Value |
|---|---|
| AMI | Ubuntu 22.04 or 24.04 LTS, **arm64** |
| Type | t4g.medium to start (2 vCPU / 4 GB — same as legacy; upgrade later is a stop/start) |
| Security group | inbound 443 + 80 from 0.0.0.0/0, 22 from your IP (tighten later) |
| Key pair | `{{KEY_PAIR_NAME}}` (existing, in 1Password) or a new one |
| Storage | 30 GB gp3 root (data volumes can be added later — see below) |
| Elastic IP | allocate a NEW one and associate (the legacy EIP stays on the legacy box until cutover) |

## 2 — Bootstrap

```bash
# from your laptop: put the repo on the box (until the repo has a git origin)
scp -r ~/Workspaces/Real-Dev-Squad/Infra ubuntu@<NEW_IP>:~/Infra
ssh ubuntu@<NEW_IP>
cd ~/Infra && ./scripts/bootstrap.sh
```

The script is idempotent and stops on purpose at step 3/5 the first time:
it creates `docker/env/*.env` + `docker/.env` from templates and exits so you
can fill **real values** (var names indexed in [secrets.md](secrets.md); values
come from each service repo's GitHub Environments). `chmod 600` is applied.
Fill them, re-run, and it validates + starts the full stack.

Notes baked into the script: Docker from the official apt repo; **log rotation
in `daemon.json`** (the legacy box never had it); restart policies come from
the compose definition itself.

## 3 — Verify, then cut over

**On-box (no DNS needed):** `docker compose ps` all Up; `curl http://localhost/nope`
returns 308 (Caddy's https redirect — proof the router is live).

**From your laptop, before touching DNS** — point ONLY your request at the new
box:

```bash
curl -sk --resolve services.realdevsquad.com:443:<NEW_IP> \
  https://services.realdevsquad.com/todo/api/schema -o /dev/null -w "%{http_code}\n"
```

`-k` is needed at this stage: Caddy can't get a real certificate until public
DNS points at the box (ACME validates via DNS). Expect the app's real status
codes (todo 200, skilltree 401, tiny 401, discord-service health 200, unknown 404).

**Full-TLS rehearsal (optional but recommended):** add a temporary DNS record
`new-services.realdevsquad.com` → NEW_IP (grey cloud), add that hostname as a
second site address in `caddy/Caddyfile.prod` temporarily, reload — Caddy gets
a real cert for it, and you can exercise the entire stack over valid TLS
without touching production traffic. Remove both afterwards.

**Data (decide per service before cutover):**
- Fresh/empty DBs boot fine (official images init users from env at first boot;
  apps run their own migrations) — enough for testing.
- For real cutover: restore latest S3 dumps (skilltree/tinysite) into the new
  DBs, and plan todo's data path (Atlas is external — todo's Mongo needs
  nothing; its Postgres dual-write target restores from dump/snapshot once a
  dump job for it exists). Rehearse the restore before relying on it.
- Discord profile needs a real `BOT_TOKEN` for current builds (see
  docker/README caveats).

**Cutover:** flip the `services.realdevsquad.com` A record to the new EIP
(grey cloud). Caddy on the new box obtains the real certificate on first
validation. The legacy box keeps running untouched as instant rollback — flip
the record back if anything's wrong. Decommission it only after a comfortable
soak.

## What this deliberately leaves for later

- ~~tofu module for the new instance~~ — exists now: `tofu/` (2026-07-18).
- Dedicated EBS data volumes + fstab (legacy pattern, `docs/host-setup.md`) —
  named Docker volumes on the root disk are fine at current KB–MB data sizes.
- Staging-environment container pairs, CI deploy integration,
  monitoring profile, SSM access — all additive once the base box works.
