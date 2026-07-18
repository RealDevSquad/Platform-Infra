# RabbitMQ (production + staging)

Verbatim mirrors of `/home/ubuntu/rabbitmq/{production,staging}/docker-compose.yml`
on the box (extracted 2026-07-18; they contain no secrets). Each broker's mnesia data
lives beside its compose file at `./data` on the box's root disk.

## Auth model (the "credential-less AMQP" answer)

Consumers connect with `amqp://rabbitmq-<env>:5672` — no username/password. That works
because the **official rabbitmq Docker image disables the guest user's
loopback-only restriction** in its shipped defaults, so `guest/guest` (the implicit
AMQP default) is accepted from any host. Exposure is bounded by the docker bridge
network: the brokers publish no host ports, so only containers on
`rds-production`/`rds-staging` can reach them.

Acceptable on a private bridge; creating a dedicated user and pinning
`loopback_users` explicitly is a reasonable future hardening (track internally if
picked up — do not change the box outside an approved change).

## Consumers

- `discord-service-<env>` — publishes (queue `DISCORD_QUEUE_PRODUCTION` prod / `DISCORD_QUEUE` staging)
- `discord-message-broker-<env>` — consumes, calls `http://discord-service-<env>:<port>`
