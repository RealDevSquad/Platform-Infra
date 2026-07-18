# docs/ — what the system is (state) and how we change it (process)

Reading order for a newcomer:

1. **[deployment-map.md](deployment-map.md)** — start here: every service, port, route, and CI pipeline on the box.
2. **[aws-layer.md](aws-layer.md)** — the cloud shell around the box (instance, EIP, SG, IAM, volumes, snapshots, S3).
3. **[host-setup.md](host-setup.md)** — inside the machine: OS, Docker, networks, mounts, cron, DB-init model.
4. **[dns.md](dns.md)** — how traffic finds the box (Cloudflare → EIP → Caddy).
5. **[secrets.md](secrets.md)** — every config value by name, where it lives, who consumes it. Names only, never values.

Process docs:

- **[publishing-plan.md](publishing-plan.md)** — how this repo becomes a (possibly public) git repo: sanitize → gate → fresh init → push.

Conventions: kebab-case filenames; state docs describe **as-is** reality with extraction dates; anything aspirational is marked as future work (tracked internally, no ticket IDs in this repo).
