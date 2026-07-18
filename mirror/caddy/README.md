# mirror/caddy — as-is snapshot (reference only)

Verbatim copies from the box (extracted 2026-07-18): `Caddyfile` from
`/home/ubuntu/caddy/Caddyfile` — **the live routing authority of production**
until the deploy-workflow migration moves prod to `docker/` — and the `docker-compose.yml` that
runs the caddy container there (project `caddy-reverse-proxy`).

Any change made on the box must be reflected here so drift stays visible.
The local-mode equivalent lives at `docker/caddy/Caddyfile.local`.
