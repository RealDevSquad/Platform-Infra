# DNS — realdevsquad.com (as observed 2026-07-18)

Zone hosted on **Cloudflare** (not Route53 — the AWS account has no hosted zones).
Authoritative export from the Cloudflare dashboard is still TODO; below is what
public resolution shows.

## Points at the box (DNS-only / grey cloud)

| Record | Target | Why grey |
|---|---|---|
| `services.realdevsquad.com` | A → {{EIP}} (the EIP) | Caddy does its own TLS via ACME HTTP-01; proxying would break issuance |

All backend traffic rides this one hostname via Caddy path prefixes
(`/todo*`, `/staging-todo*`, `/skilltree*`, `/staging-skilltree*`, `/tiny*`,
`/staging-tiny*`, `/discord-service*`, `/staging-discord-service*`).

`service.realdevsquad.com` (singular) also resolves here — leftover test vhost,
scheduled for removal.

## Cloudflare-proxied (orange cloud) — origins NOT this box

`www`, `api`, `staging-api`, `todo`, `staging-todo`, `dashboard`, `calendar`,
`crypto`, `goals`, `learn`, `welcome` → Cloudflare proxy IPs (104.26.x.x /
172.67.x.x). These are frontends/website-backend hosted elsewhere; the `todo` /
`staging-todo` hostnames are the **frontend** sites that call
`services.realdevsquad.com/todo` for their API.

## Other hosts

| Record | Host |
|---|---|
| `status.realdevsquad.com`, `members.realdevsquad.com` | Vercel (`cname.vercel-dns.com`) |
| `my.realdevsquad.com` | Cloudflare Pages (`my-rds.pages.dev`) |
| `backend`, `identity`, `events` | NXDOMAIN (no records) |

## TODO

- Export the full zone from the Cloudflare dashboard (all records + proxy status).
- Decide whether `tofu/` manages the zone via the Cloudflare provider (agreed: yes).
