# Configuration model — local-first, provider-pluggable

**The rule:** the only thing that consumes configuration is a service container,
and the only interface a container sees is its **env file** (`docker/env/<svc>.env`).
Nothing downstream of the env file knows or cares where the values came from.
That makes the env file the *contract* and every source a swappable **provider**.

```
                     ┌─ provider: example  (cp *.env.example — offline, dummy)
 value source  ──────┼─ provider: manual   (you paste staging values)
 (pluggable)         ├─ provider: 1password (op inject — maintainer, staging)
                     └─ provider: ssm      (render-env.sh — box & CI only)
                                   │
                                   ▼
                     docker/env/<svc>.env   ◄── THE CONTRACT (mode 600)
                                   │
                                   ▼
                     docker compose  ──►  containers
```

## Why this order matters (local-first)

A laptop has no SSM, no instance role, no AWS at all — and must still bring the
whole box up. So SSM can never be a dependency; it is one optional provider that
happens to be how the *server* fills the same files a laptop fills by hand.
Consequence: **every environment, including production, is just "env files +
compose."** SSM disappears from the run path entirely — it ran earlier, produced
files, and exited. If SSM is down, a box with already-rendered env files still
boots.

## The providers (all produce the identical target: `docker/env/*.env`)

| Provider | Who / when | Needs | Command |
|---|---|---|---|
| **example** | any laptop, first run, offline | nothing | `cp env/x.env.example env/x.env` (bootstrap does this) |
| **manual** | laptop wanting staging-tier values | the values | edit `env/x.env` by hand |
| **1password** | maintainer laptop, staging values, no hand-typing | `op` CLI + vault access | `op inject -i env/x.env.tpl -o env/x.env` (future, optional) |
| **ssm** | the box + CI only | instance role / OIDC | `scripts/render-env.sh <env>` |

`.env.example` files are the **schema** every provider fills: they list every
key with a safe dummy default, are committed, and are what `docker compose config`
validates against. `docs/secrets.md` is the human index of the same keys.

## Mode is declared, not guessed

`docker/.env` carries **`ENV_PROVIDER=manual|ssm`** — the machine states its
mode in config. The ssm provider (`render-env.sh`) hard-refuses (exit 2,
changes nothing) unless the machine declares `ssm`; `bootstrap.sh` likewise
refuses to run off-EC2 (no metadata service → stop, with a pointer to the
local flow). So the AWS path *fails at the front door* on a laptop instead of
half-working, and the local path contains no code that can reach AWS at all.

## `scripts/render-env.sh` (the SSM provider) — contract

- Input: an environment name (`production`/`staging`) + the SSM path root.
- Output: `docker/env/*.env`, mode 600 — **byte-compatible with what a human
  would hand-write.** Same keys, same file, different source.
- Never prints a value. Never required off-server. Idempotent.
- Fallback baked in: if SSM is unreachable AND an env file already exists, it
  leaves the existing file and warns (a transient SSM outage never takes the
  box down). If SSM is unreachable and NO file exists, it errors loudly.

## Precedence (when more than one provider could apply)

`docker/.env` sets `COMPOSE_*`; per-service files are `env/<svc>.env`. If a file
exists, no provider overwrites it unless explicitly asked (`render-env.sh
--force`). So: hand-authored local files always win locally; the box re-renders
from SSM on deploy via an explicit `--force`. No provider silently clobbers
another's output.

## What this means for each surface

- **Laptop (offline):** `bootstrap`/`make up` → example provider fills dummies →
  full stack runs. Zero AWS. (Today's proven path.)
- **Laptop (staging values):** manual or 1password provider → same files → real
  auth flows. Still zero SSM.
- **Box / CI:** ssm provider (`render-env.sh --from-ssm`) → same files → same
  compose. The only place SSM appears.

## Non-negotiables (carried from the broader plan)

- Real values never enter git, tfstate, the repo, or an AI transcript. The
  `.env.example` schema is dummy-only; rendered `env/*.env` are gitignored.
- The read-only `rds-LLM` role gets no `ssm:GetParameter` on the secret tree.
- Local dev must work with **no network and no AWS** — the acceptance test for
  this whole model.
