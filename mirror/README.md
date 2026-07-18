# mirror/ — as-is snapshots of the hand-built box (reference only)

These are **verbatim copies of what runs on the production box today**, extracted
2026-07-18, preserving the box's own on-disk layout (`/home/ubuntu/caddy/`,
`/home/ubuntu/rabbitmq/`, `/home/ubuntu/backup-scripts/`). The box was built by
hand over time, so its layout is fragmented — one folder per thing. This
directory inherits that fragmentation *on purpose*: it documents reality.

**Nothing here is a way to bring a machine up.** The canonical, unified
definition lives in [`../docker/`](../docker/) (one Compose project, profiles
per service — rabbitmq and caddy are services in it like everything else) plus
[`../tofu/`](../tofu/) for the AWS layer.

Why keep the mirrors at all:
- `caddy/Caddyfile` is the **live routing authority of production** until prod
  itself migrates to the compose definition. Any change made on the
  box should be reflected here (and vice versa) so drift is visible.
- Diffing target-state against as-is is how the migration gets reviewed.
- The backup scripts document current behavior (and current flaws — see the
  hardening tickets) until replaced.

Once production runs from `docker/` (the deploy-workflow migration), this directory becomes
historical and can be deleted.
