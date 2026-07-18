# RDS services server — deployment map

Extracted 2026-07-18 from the five service repos' deploy workflows, GitHub Environment
variables, Dockerfiles, and the box itself ({{INSTANCE_ID}}, ap-south-1, EIP {{EIP}}).

## The shared pipeline template

All five services deploy identically (same workflow skeleton, copy-pasted per repo):

1. `on: push` to `main` (→ `production` env) or `develop` (→ `staging` env);
   GitHub Environments carry required-reviewer protection and all vars/secrets.
2. Buildx builds `linux/arm64`, pushes to Docker Hub `{{DOCKERHUB_USER}}/<repo>`
   tagged `<sha>` + `latest`.
3. `appleboy/ssh-action` into the box: `docker pull :latest` → `docker stop` →
   `docker rm` → `docker run -d` with inline `-e` flags.

Shared flaws (fix once in Infra, fixes all five): deploys `:latest` not the SHA
(cross-env race — staging/production overwrite the same tag); no `--restart` policy;
no post-deploy health check; no `concurrency:` group; no image prune (232 images,
6.3 GB reclaimable as of extraction); four of five pin `appleboy/ssh-action@master`
(unpinned mutable ref on the step holding the SSH key — todo-backend uses `@v1`).

## Service matrix

| Service | Stack | Container listens | Host port prod/stag | Caddy route (services.realdevsquad.com) | Data | Notes |
|---|---|---|---|---|---|---|
| todo-backend | Django + gunicorn | 8000 | 3040 / 4040 | `/todo*`, `/staging-todo*` | Mongo Atlas + on-box postgres 17.6 (`*-todo-postgres`) | migrations run at container boot; `ENV` build-arg bakes settings module into image |
| discord-service | Go | `$PORT` (3050/4050) | 3050 / 4050 (`-p P:P`) | `/discord-service*`, `/staging-discord-service*` | — | Dockerfile `EXPOSE 8080` is stale; talks to rabbitmq + is called by broker |
| skill-tree-backend | Java 17 Spring Boot | 8080 fixed | 3020 / 4020 | `/skilltree*`, `/staging-skilltree*` | on-box MySQL 8.4 (`*-database-skilltree`) | `SPRING_PROFILES_ACTIVE`; MySQL host/creds via secrets |
| tiny-site-backend | Go (Gin) | `$PORT` (3010/4010) | 3010 / 4010 (`-p P:P`) | `/tiny*`, `/staging-tiny*` | on-box postgres 16.3 (`prod-database-tinysite`, `staging-postgres`) | Dockerfile `EXPOSE 4001` stale; `DB_URL` assembled inline, `sslmode=disable` |
| discord-message-broker | Go | none (no ports) | none | none (not routed) | consumes RabbitMQ | calls `http://discord-service-<env>:<port>`; 5-min timeout |

Base layer (not CI-deployed; lives in `/home/ubuntu/`): caddy (compose,
`caddy-reverse-proxy` project), rabbitmq production/staging, six DB containers,
backup cron every 4h → `rds-backup-prod-{skilltree,tinysite}-data` S3 buckets.

## Wiring facts

- Service discovery is Docker container-name DNS on networks `rds-production` /
  `rds-staging`, everywhere: Caddy → apps, broker → discord-service, apps → DBs,
  apps → `amqp://rabbitmq-<env>:5672`.
- The AMQP URL carries no credentials → rabbitmq auth/config must live in
  `/home/ubuntu/rabbitmq/{production,staging}` (NOT yet extracted).
- `api.realdevsquad.com` (website-backend) is referenced as an external URL by
  discord-service and skill-tree — it does not run on this box.
- Queue names are asymmetric: `DISCORD_QUEUE_PRODUCTION` (prod) vs `DISCORD_QUEUE` (staging).
- Host-port publishes (3010–4050 on 0.0.0.0) are unused by routing (Caddy dials
  container ports) — candidates for removal; only the SG keeps them off the internet.

## Security/config observations

- tiny-site tokens: `JWT_VALIDITY_IN_HOURS=8430` (~351 d), `TOKEN_VALIDITY_IN_SECONDS=31536000` (365 d).
- `appleboy/ssh-action@master` unpinned in 4/5 repos (supply-chain exposure for the SSH key).
- Go images run as `USER appuser`; skill-tree runs as root (no USER directive).
- todo-backend staging/production images differ (settings module baked at build) while
  sharing one `latest` tag.

## Still to extract (on-box items)

rabbitmq config dirs; backup scripts (secret-scrub first); DB init/users/schemas;
docker network creation; host setup (docker install, daemon.json, logrotate); the
DLM/snapshot mechanism behind the 42 EBS snapshots; Cloudflare DNS records as data;
secrets.md (env var name → storage location → consumer; names only, never values).
