# wave2-box-fixes — reviewed change package

**Covers:** restart policies, image prune, Caddy hygiene, backup-script
hardening.
**Status:** Proposed — awaiting review. Nothing here has touched the box.
**Target:** the services box, SSH alias `rds-services` (user `ubuntu`).

## Principle: every change converges the box to a versioned declaration

Nothing here is an ad-hoc mutation of live state. Each fix ships as a file in
this repo that is copied to the box *whole*; the box ends up matching a
declaration we can diff and roll back. Where a step must touch running state
(restart policies), it is a **convergence to a committed declaration**, not a
free-hand edit, and it is recorded in the CHANGELOG section below.

## Artifacts

| Artifact | Lands on box as | Change | Long-term home |
|---|---|---|---|
| `caddy/Caddyfile` | `/home/ubuntu/caddy/Caddyfile` | drop test vhost; explicit 404 fallthrough (8 service routes byte-identical) | this file until deploys move to the compose definition |
| `backup-scripts/backup_mysql_data_to_s3_skilltree.sh` | `/home/ubuntu/backup-scripts/…` | password from container env; absolute `BACKUP_DIR`; mode 700 | this file (a later cleanup parameterizes + renames) |
| `backup-scripts/backup_mysql_data_to_s3_tinysite.sh` | `/home/ubuntu/backup-scripts/…` | absolute `BACKUP_DIR`; mode 700 | this file |
| `host/docker-prune.sh` + `host/docker-prune.cron` | `/home/ubuntu/host/` + `/etc/cron.d/docker-prune` | **scheduled** weekly prune of unused images >7d | these files |

## Why the restart-policy and prune fixes changed shape from the first draft

The first draft applied restart policies and pruning as one-off `docker update`
/ `docker image prune` commands. Both were **imperative drift** — nothing in the
repo declared the desired end-state, and the prune re-accumulates. Fixed:

- **Image prune** is now a **versioned scheduled job** (`host/`), installed
  once, self-maintaining, logged. Auditable (files in repo) and long-term (runs
  weekly forever), vs. a manual reclaim that silently refills.
- **Restart policies** — the permanent, fully-auditable home is
  **prod running from the committed compose definition** (`docker/compose.yaml`
  already declares `restart: unless-stopped` on every service); that migration
  is **the compose-deploy move** and is out of scope here (it recreates containers = higher
  risk, its own package). This package performs only the **safe interim
  convergence**: `docker update` changes the restart policy on the *existing*
  containers (no recreate, no downtime) to match the committed declaration.
  Recorded below as convergence, not as the fix of record.

---

## Pre-review diffs (local, box untouched)

`mirror/` equals the box as-extracted. Restore real values so only intentional
changes show, diff, then re-anonymize:

```bash
cd ~/Workspaces/Real-Dev-Squad/Infra
./scripts/sanitize.sh --restore
diff mirror/caddy/Caddyfile                              runbooks/wave2-box-fixes/caddy/Caddyfile
diff mirror/backup-scripts/backup_mysql_data_to_s3_skilltree.sh runbooks/wave2-box-fixes/backup-scripts/backup_mysql_data_to_s3_skilltree.sh
diff mirror/backup-scripts/backup_mysql_data_to_s3_tinysite.sh  runbooks/wave2-box-fixes/backup-scripts/backup_mysql_data_to_s3_tinysite.sh
./scripts/sanitize.sh
```

`host/` has no mirror counterpart — it is net-new, review the two files directly.

---

## Application (after approval; run from the real-values state)

Preconditions:
- `./scripts/sanitize.sh --restore` has been run (artifacts carry real bucket names).
- Executor can `ssh rds-services` (a human, or Claude with a user-granted
  `Bash(ssh rds-services:*)` rule).
- Skilltree DB exposes its password to the hardened script — MUST print `PRESENT`:
  ```bash
  ssh rds-services 'docker exec prod-database-skilltree printenv MYSQL_ROOT_PASSWORD >/dev/null && echo PRESENT || echo MISSING'
  ```
  If `MISSING`, STOP: keep the current skilltree script; the rest of the package is unaffected.

### Step 1 — Caddyfile (whole-file copy, validate, graceful reload)

```bash
ssh rds-services 'cp /home/ubuntu/caddy/Caddyfile /home/ubuntu/caddy/Caddyfile.bak.$(date +%Y%m%d-%H%M%S)'
scp runbooks/wave2-box-fixes/caddy/Caddyfile rds-services:/home/ubuntu/caddy/Caddyfile
ssh rds-services 'docker exec caddy caddy validate --config /etc/caddy/Caddyfile'   # STOP if this fails; running config untouched
ssh rds-services 'docker exec caddy caddy reload  --config /etc/caddy/Caddyfile'
curl -s -o /dev/null -w "todo %{http_code}\n"    https://services.realdevsquad.com/todo/api/schema
curl -s -o /dev/null -w "unknown %{http_code}\n" https://services.realdevsquad.com/zzz-nope   # expect 404
```

### Step 2 — backup scripts (whole-file copy, mode, dry-run)

```bash
ssh rds-services 'cp -r /home/ubuntu/backup-scripts /home/ubuntu/backup-scripts.bak.$(date +%Y%m%d-%H%M%S)'
scp runbooks/wave2-box-fixes/backup-scripts/backup_mysql_data_to_s3_skilltree.sh rds-services:/home/ubuntu/backup-scripts/
scp runbooks/wave2-box-fixes/backup-scripts/backup_mysql_data_to_s3_tinysite.sh  rds-services:/home/ubuntu/backup-scripts/
ssh rds-services 'chmod 700 /home/ubuntu/backup-scripts/*.sh && ls -l /home/ubuntu/backup-scripts/*.sh'
ssh rds-services 'bash /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_skilltree.sh'   # expect exit 0, checksum-verified upload
ssh rds-services 'bash /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_tinysite.sh'
```

### Step 3 — scheduled prune (install versioned job)

```bash
ssh rds-services 'mkdir -p /home/ubuntu/host'
scp runbooks/wave2-box-fixes/host/docker-prune.sh rds-services:/home/ubuntu/host/
ssh rds-services 'chmod 700 /home/ubuntu/host/docker-prune.sh'
scp runbooks/wave2-box-fixes/host/docker-prune.cron rds-services:/tmp/docker-prune.cron
ssh rds-services 'sudo install -m 644 -o root -g root /tmp/docker-prune.cron /etc/cron.d/docker-prune && rm /tmp/docker-prune.cron'
ssh rds-services 'bash /home/ubuntu/host/docker-prune.sh'   # run once now: reclaims the ~6GB backlog, proves the script
```

### Step 4 — restart policy convergence (interim; permanent = compose-deploy move)

Converge existing containers to the `restart: unless-stopped` declared in
`docker/compose.yaml`. `docker update` does NOT recreate containers.

```bash
ssh rds-services 'docker update --restart unless-stopped $(docker ps -q)'
ssh rds-services 'docker ps -q | xargs docker inspect --format "{{.Name}} {{.HostConfig.RestartPolicy.Name}}"'   # expect all unless-stopped
```
> This is convergence to a committed declaration, not the fix of record. The
> fix of record is the compose-deploy move (prod recreated from the compose definition), after
> which this policy is guaranteed by the versioned file, not by a live command.

---

## Rollback (per step, independent)

- **Step 1:** `scp` the `Caddyfile.bak.<ts>` back, `docker exec caddy caddy reload`.
- **Step 2:** restore from `backup-scripts.bak.<ts>/`.
- **Step 3:** `sudo rm /etc/cron.d/docker-prune` (pruned images re-pull on next deploy).
- **Step 4:** `docker update --restart no <names>` (unless-stopped is strictly safer; usually leave).

## Post-application

1. Fill the CHANGELOG below (this is the audit record — commit it).
2. `./scripts/sanitize.sh` (re-anonymize), then sync `mirror/` from the applied
   Caddyfile + backup scripts and re-anonymize.
3. Mark the Caddyfile, backup-script, and prune items done in the tracker; restart
   policies = "interim done — permanent via the compose-deploy move".
4. The kernel-patch reboot is now unblocked — restart policies exist, so a
   reboot tests them rather than causing an outage.

## CHANGELOG (audit record — fill on application, commit)

```
# not yet applied
# date (UTC) | operator | step | result / verification output
```
