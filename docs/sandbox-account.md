# Sandbox account — stand up the box in your own dev account

Goal: prove the whole Infra repo works by building the box **from scratch in a
separate AWS account** you control — your developer testing ground. Zero risk to
the prod account (it's a different account entirely), and the purest test of the
"clone into any account" thesis: greenfield, no legacy cruft.

Chosen shape: **a real subdomain you own** (real Let's Encrypt cert, most
prod-like) + **single environment** (one set of services, not prod+staging pairs).

## Boundary

This is *your* account. You run every privileged step with your own credentials;
Claude builds the code and this runbook but never has access to the account and
never asks for your keys. Paste command output back for help debugging.

## 1 — Create the AWS shell (OpenTofu, greenfield)

Unlike `../tofu-prod-import/` (which imports the legacy box), `tofu/` **creates**
everything: default-VPC placement, security group (80/443 public; SSH port 22
only if you set `admin_cidr` — default is SSM-only, no SSH port at all), IAM
role with **SSM Session Manager** (keyless shell — the thing the legacy
box lacked), latest Ubuntu 24.04 arm64 AMI (auto-resolved), Elastic IP, and a
backup S3 bucket.

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars   # set subdomain + region
# authenticate to YOUR sandbox account (SSO or profile), then:
tofu init && tofu plan && tofu apply
```

`tofu apply` prints: the EIP, the exact **DNS record to create**, the
`SITE_ADDRESS=` line, and an `aws ssm start-session` command.

## 2 — DNS

Create the A record it printed: `sandbox.yourdomain.com -> <EIP>`. On
Cloudflare, **either cloud color works**:

- **Grey (DNS only)** — simplest: clients talk straight to Caddy.
- **Orange (proxied)** — fine too (enables edge caching/WAF later), with one
  requirement: zone SSL/TLS mode **Full (strict)** — never "Flexible", which
  hits the origin over plain HTTP and loops on Caddy's 308 redirect. Caddy's
  ACME HTTP-01 challenge passes through the proxy, so the origin still gets a
  real certificate. Note: Cloudflare masks origin 5xx bodies with its own terse
  pages (`error code: 502`), so debug those from the box, not the edge.

## 3 — Provision + run the box

Get the repo onto the box (no git origin yet, so copy it):

```bash
scp -r ~/Workspaces/Real-Dev-Squad/Infra ubuntu@<EIP>:~/Infra
# or: aws ssm start-session --target <id>   (keyless), then pull the repo your way
```

On the box:

```bash
cd ~/Infra && ./scripts/bootstrap.sh
# it stops the first time to let you fill values:
#  - docker/env/*.env  ← your STAGING-tier values (manual provider; local dev-safe defaults are in *.env.example)
#  - docker/.env:
#       DOCKERHUB_USER=<hub namespace>
#       COMPOSE_FILE=compose.yaml:compose.prod.yaml
#       SITE_ADDRESS=sandbox.yourdomain.com
#       COMPOSE_PROFILES=todo,skilltree,tinysite,discord
#       ENV_PROVIDER=manual
# re-run bootstrap.sh — it validates + brings the stack up.
```

The same `compose.prod.yaml` + `Caddyfile.prod` prod uses — the only difference
is `SITE_ADDRESS`, which points Caddy at your subdomain instead of the RDS one.
Caddy fetches a real cert for it automatically.

## 4 — Verify

```bash
./scripts/validate-stack.sh                       # behavior matrix, on the box
curl https://sandbox.yourdomain.com/todo/api/schema   # real HTTPS, from anywhere
```

Expected: todo 200, skilltree 401, tinysite 401, discord-service 200, unknown 404 —
the same matrix proven locally, now over real TLS in your own account.

## Notes / decisions deferred

- **`SITE_ADDRESS` covers Caddy only — apps have their own host allowlists.**
  todo-backend (Django) rejects unknown `Host` headers with a bare 400 page:
  append your subdomain to `ALLOWED_HOSTS` in `env/todo.env` (env-driven,
  comma-separated), then `docker compose up -d todo-backend`. Symptom if
  forgotten: real cert, working TLS, and a "Bad Request (400)" body.

- **Secrets:** sandbox uses the `manual` provider (hand-filled env files). The
  SSM provider (`render-env.sh` + `tofu/ssm.tf`) is optional here — the
  instance role is already SSM-param-capable at `/rds/sandbox/*` if you want to
  wire it later.
- **Data:** fresh empty DBs (services migrate themselves on boot) — enough to
  prove the box. Restore from dumps only if you want real data.
- **Discord:** needs a real staging `BOT_TOKEN` for `:latest`, or pin `DISCORD_TAG`
  (see docker/README caveats).
- **Teardown:** `tofu destroy` in `tofu/` removes everything (bucket has
  `force_destroy = true`).
- This module is intentionally separate from `../tofu-prod-import/`; nothing here touches the
  prod account or the legacy box.
