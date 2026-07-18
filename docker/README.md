# docker/ — the box as one Compose project

Same definitions target three uses: local subsets on a laptop (works today),
a full box rebuild, and — once deploy workflows consume this repo — production deploys.

## Local quickstart (Apple Silicon runs the arm64 CI images natively)

```bash
cd docker
cp env/todo.env.example env/todo.env        # repeat per profile you enable
cat > .env <<'EOF'
DOCKERHUB_USER=<the docker hub namespace images are pushed to>
COMPOSE_FILE=compose.yaml:compose.local.yaml
ENV_PROVIDER=manual
EOF
COMPOSE_PROFILES=todo docker compose up -d
curl -s localhost/todo/api/schema | head -3     # acceptance check
curl -s localhost/nope                          # -> "no route" 404
```

Profiles: `todo` (backend + postgres + mongo replica-set), `skilltree` (backend +
mysql 8.4), `tinysite` (backend + postgres 16.3), `discord` (service + broker +
rabbitmq). Combine freely: `COMPOSE_PROFILES=todo,tinysite`.

## HTTP and HTTPS, locally

The local overlay serves both: plain `http://localhost/...` and real-TLS
`https://localhost/...` (Caddy's **internal CA** — `auto_https disable_redirects`
keeps :80 on HTTP while issuing a local cert for :443).

```bash
curl        http://localhost/todo/api/schema     # plain
curl -k     https://localhost/todo/api/schema    # TLS, skip trust check
```

To drop the `-k` (browser + curl trust the cert), install Caddy's local root once:
`docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-root.crt`
then trust `caddy-root.crt` in your OS keychain. This is the *transport* half of
prod TLS; the *public-issuance* (ACME) half is what the sandbox subdomain tests.

## Design notes

- **Caddy is the always-on base**; the local overlay publishes only `:80` and mounts
  `caddy/Caddyfile.local` (same `handle_path` routes as prod, upstreams by compose
  service name, `auto_https off`, explicit 404 fallthrough).
- **Mode is declared, not guessed**: `ENV_PROVIDER=manual|ssm` in `.env`. The
  AWS-side tooling (`render-env.sh`) hard-refuses unless a machine declares
  `ssm`, and `bootstrap.sh` refuses off-EC2 — a laptop can never half-run the
  AWS path by accident (`docs/config-model.md`).
- **Container names are the service-discovery contract** (Caddy dials
  `todo-backend:8000` etc.), mirroring how prod works today with `-production`/
  `-staging` suffixed names.
- **Everything carries `restart: unless-stopped` and DB healthchecks** — the fixes
  the hand-built box lacks are the defaults here.
- `env/*.env` files are gitignored at publish time; the committed `.env.example`
  copies hold only local-dev dummy values (mirroring the public CI test env).

## Known caveats

- **Never run compose here without profiles active** — `COMPOSE_PROFILES` is set in
  `.env` for exactly this reason; don't remove that line. A profile-less invocation
  (e.g. `docker compose up -d caddy`) builds a model containing only caddy, classifies
  every profile-gated container as an *orphan*, and current Compose **stops them all**
  on `up` (observed 2026-07-18: entire stack killed in one second by a caddy-only
  recreate). With profiles in `.env`, every invocation sees the full project.

- **`:latest` is ambiguous** — staging and production builds share the tag, and
  todo-backend bakes its Django settings module at build time. For deterministic
  local runs pin `TODO_TAG=<sha>` (a develop-branch build) in `.env`. Fixed
  properly by SHA-tagged deploys.
- **discord profile**: containers run, but real Discord API calls need real creds.
- **discord-service `:latest` crash-loops on dummy creds** — builds since Feb 2025
  register slash commands at boot via a real Discord gateway login, and a dummy
  `BOT_TOKEN` panics with `websocket: close 4004: Authentication failed` (no
  skip flag exists). For local smoke runs pin `DISCORD_TAG` in `.env` to a
  pre-register build (`9739d3fb9ca46a2137f0b913f03074a2818b87b9`, 2025-01-26):
  it still serves `GET /health` (200 via `localhost/discord-service/health`),
  `POST /` and `POST /queue`, and logs `Established a connection to RabbitMQ`.
  Running `:latest` requires a real staging `BOT_TOKEN` in `env/discord.env`.
- **skilltree profile: `RDS_PUBLIC_KEY` must be a real parseable RSA public key**
  (a throwaway one is fine — see the generate command in
  `env/skilltree.env.example`). The app base64-decodes it as X.509/SPKI DER at
  bean init (PEM headers/whitespace are stripped first), so a placeholder string
  crashes boot. Every route — including `/actuator/health` — sits behind RDS JWT
  auth: an app-JSON **401** from `localhost/skilltree/...` is the local
  "working" signal (matches prod).
- **tinysite profile: there is no health endpoint** — the Go/Gin backend registers
  only `/v1/users|auth|tinyurl|urls|redirect` routes, so `localhost/tiny/v1/health`
  returns Gin's plain `404 page not found`. Proof-of-life is an app-generated
  response: `localhost/tiny/v1/users/self` → `{"message":"Unauthorized"}` 401, or
  `localhost/tiny/v1/urls/<anything>` → `{"message":"URL not found"}` 404 (this one
  round-trips the DB). The image's entrypoint waits on `DB_HOST:DB_PORT`, runs bun
  migrations, then starts the server — first boot needs postgres healthy first.
- **Image pulls can hang forever on a wedged Docker Desktop credential helper** —
  `docker compose up` sits at `Pulling` with zero progress because every pull
  (even of public images) first calls the configured `credsStore` helper
  (`docker-credential-desktop` processes pile up). Probe with a direct
  `docker pull` of a small public image: timing out with `error getting
  credentials` confirms it. Workaround: pull anonymously with an empty client
  config, then re-run `up` (images now local, no pull needed):
  `mkdir -p /tmp/docker-noauth && echo '{}' > /tmp/docker-noauth/config.json &&
  DOCKER_CONFIG=/tmp/docker-noauth DOCKER_HOST=unix://$HOME/.docker/run/docker.sock docker pull <image>`
  — or restart Docker Desktop.
- **Prod overlay** (`compose.prod.yaml`) exists and is proven single-env (local
  + sandbox). Still future: the prod+staging *pair* layout (`-production`/
  `-staging` names, per-env external networks), EBS bind-mount data paths, and
  env from the real secret store.
