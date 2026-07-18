# secrets.md — configuration inventory (names only)

Every value the box's services consume: **name → kind → where it lives → consumer.**
Values NEVER appear in this repo. GitHub items live per-repo under Settings →
Environments (`production` / `staging`), each gated by required reviewers.

## Shared by all five service repos (GitHub Environment secrets)

| Name | Kind | Purpose |
|---|---|---|
| `DOCKERHUB_USERNAME` | secret | Docker Hub account images push to (`{{DOCKERHUB_USER}}/*`) |
| `DOCKERHUB_TOKEN` | secret | Docker Hub push auth |
| `AWS_EC2_HOST` | secret | box address for deploy SSH |
| `AWS_EC2_USERNAME` | secret | `ubuntu` |
| `AWS_EC2_SSH_PRIVATE_KEY` | secret | deploy key — target of the SSM/OIDC migration |

## todo-backend (Django) — container `todo-backend-<env>`

Secrets: `SECRET_KEY`, `DB_NAME`, `MONGODB_URI` (Atlas), `GOOGLE_OAUTH_CLIENT_ID`,
`GOOGLE_OAUTH_CLIENT_SECRET`, `PUBLIC_KEY`, `PRIVATE_KEY` (JWT signing pair),
`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.

Variables: `ENV`, `PORT` (3040/4040), `DOCKER_NETWORK` (rds-production/rds-staging),
`ALLOWED_HOSTS`, `GOOGLE_OAUTH_REDIRECT_URI`, `ACCESS_LIFETIME`, `REFRESH_LIFETIME`,
`ACCESS_TOKEN_COOKIE_NAME`, `REFRESH_TOKEN_COOKIE_NAME`, `COOKIE_DOMAIN`,
`COOKIE_SECURE`, `COOKIE_HTTPONLY`, `COOKIE_SAMESITE`, `TODO_BACKEND_BASE_URL`,
`TODO_UI_BASE_URL`, `TODO_UI_REDIRECT_PATH`, `CORS_ALLOWED_ORIGINS`,
`SWAGGER_UI_PATH`, `ADMIN_EMAILS`, `FRONTEND_URL`, `DUAL_WRITE_ENABLED`,
`DUAL_WRITE_SYNC_MODE`, `DUAL_WRITE_RETRY_ATTEMPTS`, `DUAL_WRITE_RETRY_DELAY`.

## discord-service (Go) — container `discord-service-<env>`

Secrets: `DISCORD_PUBLIC_KEY`, `BOT_TOKEN`, `GUILD_ID`, `BOT_PRIVATE_KEY`.
Variables: `ENV`, `PORT` (3050/4050), `DOCKER_NETWORK`, `QUEUE_NAME`
(`DISCORD_QUEUE_PRODUCTION` / `DISCORD_QUEUE` — asymmetric), `QUEUE_URL`
(`amqp://rabbitmq-<env>:5672`, credential-less), `RDS_BASE_API_URL`, `MAIN_SITE_URL`.

## skill-tree-backend (Spring Boot) — container `skill-tree-backend-<env>`

Secrets: `RDS_PUBLIC_KEY`, `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DB_USERNAME`,
`MYSQL_DB_PASSWORD`.
Variables: `ENV`, `PORT` (3020/4020), `DOCKER_NETWORK`, `DB_NAME` (skilltree),
`RDS_BACKEND_BASE_URL`, `SKILL_TREE_BACKEND_BASE_URL`, `SKILL_TREE_FRONTEND_BASE_URL`,
`SPRING_PROFILES_ACTIVE`. Hardcoded in workflow: `API_V1_PREFIX=/api/v1`.

## tiny-site-backend (Go/Gin) — container `tiny-site-backend-<env>`

Secrets: `JWT_SECRET`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`,
`DB_HOST`, `DB_PORT`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
(workflow assembles `DB_URL=postgresql://…?sslmode=disable` from these).
Variables: `ENV`, `PORT` (3010/4010), `DOCKER_NETWORK`, `GIN_MODE`, `JWT_ISSUER`,
`JWT_VALIDITY_IN_HOURS` (8430 — flagged), `TOKEN_VALIDITY_IN_SECONDS`
(31536000 — flagged), `DOMAIN`, `AUTH_REDIRECT_URL`, `GOOGLE_REDIRECT_URL`,
`ALLOWED_ORIGINS`, `DB_MAX_OPEN_CONNECTIONS`, `USER_MAX_URL_COUNT`, `WEB_APP_BASE_URL`.

## discord-message-broker (Go) — container `discord-message-broker-<env>`

No secrets beyond the shared set.
Variables: `ENV`, `DOCKER_NETWORK`, `QUEUE_NAME`, `QUEUE_URL`,
`DISCORD_SERVICE_URL` (`http://discord-service-<env>:<port>`).

## On-box (pending extraction — box access blocked at time of writing)

| Where | What (expected) |
|---|---|
| `/home/ubuntu/backup-scripts/*.sh` | DB dump credentials (known-bad: hardcoded MySQL root password, world-readable — to be externalized) |
| `/home/ubuntu/rabbitmq/{production,staging}` | RabbitMQ user/auth config (AMQP URLs carry no creds, so auth lives here) |
| `~/.aws` on the box | possible static AWS keys predating the instance profile (to be removed) |
| DB containers | how users/schemas were initialized — undocumented anywhere |
