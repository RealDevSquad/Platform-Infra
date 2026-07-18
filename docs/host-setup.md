# Host setup — services server (as-is, extracted 2026-07-18)

What a from-scratch rebuild must reproduce at the host level. Everything below was
read off the live box (`ubuntu@{{EIP}}`), read-only.

## OS / runtime

| Item | Value |
|---|---|
| OS | Ubuntu 22.04.4 LTS (arm64), kernel `6.5.0-1017-aws` (uptime 788 d at extraction — kernel patching pending) |
| Docker | 26.1.3 (apt); **no `/etc/docker/daemon.json`** → default `json-file` logging, unbounded (log rotation is a known gap) |
| Snaps | `amazon-ssm-agent 3.3.4793` (present but **unregistered** — no SSM policy on the role), `aws-cli 2.35.21`, lxd, cores |
| `~/.aws/` | contains only the `cli/` cache dir — **no static credentials**; S3 uploads use the instance profile |

## Docker networks (create before anything else)

| Network | Driver | Subnet |
|---|---|---|
| `rds-production` | bridge | 172.20.0.0/16 |
| `rds-staging` | bridge | 172.18.0.0/16 |

Both are `external: true` in every compose file — created once by hand today
(`docker network create --subnet ...` equivalent). Caddy sits on both.

## EBS data volumes → mountpoints → containers

| EBS volume (aws-layer.md) | Host device | Mountpoint | Bind-mounted into |
|---|---|---|---|
| todo-production-postgres-db (5G) | nvme5n1 | `/data/todo` | `production-todo-postgres` (`/data/todo/postgresql` → pgdata) |
| skilltree-production-db (5G) | nvme4n1 | `/data/skilltree` | `prod-database-skilltree` (`/data/skilltree/mysql` → /var/lib/mysql) |
| tinysite-prod-db (5G) | nvme2n1 | `/data/tinysite` | `prod-database-tinysite` (`/data/tinysite/postgresql` → pgdata) |
| tinysite-staging-db (1G, tag `rds-staging-data`) | nvme1n1 | `/mnt/ebs-staging-data` | **shared**: `staging-todo-postgres` (`…/todo-postgresql`) + `staging-postgres` (`…/postgresql`) |
| skilltree-staging-db (1G) | nvme3n1 | `/mnt/staging-skill-tree-db` | `staging-database-skilltree` (`…/mysql`) |
| root (30G gp2) | nvme0n1 | `/` | everything else, incl. both RabbitMQ mnesia dirs (`/home/ubuntu/rabbitmq/<env>/data`) |

Note the misleading Name tag: the 1G "tinysite-staging-db" volume actually hosts BOTH
staging Postgres instances (todo + tinysite).

### fstab (data mounts — all XFS, by UUID, `defaults,nofail`)

```
UUID={{UUID_STAGING_SHARED}}  /mnt/ebs-staging-data        xfs  defaults,nofail  0 2
UUID={{UUID_TINYSITE_PROD}}   /data/tinysite               xfs  defaults,nofail  0 2
UUID={{UUID_SKILLTREE_STG}}   /mnt/staging-skill-tree-db   xfs  defaults,nofail  0 2
UUID={{UUID_SKILLTREE_PROD}}  /data/skilltree              xfs  defaults,nofail  0 2
UUID={{UUID_TODO_PROD}}       /data/todo                   xfs  defaults,nofail  0 2
```

Rebuild note: a restored volume from snapshot keeps its UUID; a *newly created* volume
does not — the bootstrap script must mkfs.xfs and write fstab with the new UUIDs.
Live mount options are XFS defaults (`rw,relatime,attr2,inode64,…`) — nothing custom.

## Cron (user `ubuntu`)

```
0 */4 * * * /bin/bash /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_skilltree.sh
0 */4 * * * /bin/bash /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_tinysite.sh
```

No MTA installed → cron output is discarded (backup failures are silent; alarm idea
tracked as backup-age check).

## Database initialization (the "where did the users come from" answer)

The DB containers are official `postgres`/`mysql` images started once by hand (they
appear in no CI workflow). Official images create the superuser/database from
`POSTGRES_*` / `MYSQL_*` env vars **only at first boot of an empty data dir**; ever
since, identities live inside the persisted data dirs on the EBS volumes. So:

- Rebuild-with-data: attach/restore the EBS volume (or restore the S3 dump) — users
  come along; env vars are then ignored.
- From-scratch: first boot with env from the secret store recreates users, then
  restore the dump. The compose layer must encode these env names.

## Package set + user (bootstrap inputs)

- Docker from the official apt repo: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`. Also present: `chrony`, `cron`,
  `curl`, `ca-certificates`, `ec2-instance-connect` (a second SSH path via AWS APIs).
- `ubuntu` user is in `docker` and `sudo` groups (deploys run docker without sudo).
- `/home/ubuntu/caddy/site/` (mounted to caddy `/srv`) is **empty** — vestigial mount.
- The empty `skilltree/`/`tinysite/` dirs in `$HOME` are the backup scripts'
  CWD-relative `BACKUP_DIR`s (cron runs from `$HOME`); the same-named dirs inside
  `backup-scripts/` are relics of manual runs. Dumps are deleted after S3 upload.

## Reboot survivors (as-is)

Only caddy, rabbitmq ×2, and the two MySQL containers have `restart=unless-stopped`;
the other 14 containers have no restart policy (fix pending approval).
