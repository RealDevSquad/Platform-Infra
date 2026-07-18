# backup-scripts (mirrored from the box, credentials redacted)

As-is mirrors of `/home/ubuntu/backup-scripts/*.sh`, run by cron every 4 hours
(see docs/host-setup.md). `REDACTED` marks values that exist only on the box —
these mirrors are documentation, not runnable as-is.

| Script | Engine | Container | Bucket |
|---|---|---|---|
| `backup_mysql_data_to_s3_skilltree.sh` | mysqldump (root) | prod-database-skilltree | `{{BACKUP_BUCKET_SKILLTREE}}/backups/mysql` |
| `backup_mysql_data_to_s3_tinysite.sh` | pg_dump (`postgres` user, no password — in-container trust auth) | prod-database-tinysite | `{{BACKUP_BUCKET_TINYSITE}}/backups/postgresql` |

Both: dump → verify ("Dump completed"/"dump complete" marker + ≥1KB) → gzip →
`aws s3 cp` (instance-profile credentials) → MD5-vs-ETag verify → local cleanup.

Known issues (tracked internally, fix only as approved changes):
- skilltree script hardcodes the MySQL root password on the box and is world-readable
- both use CWD-relative `BACKUP_DIR` (depend on cron's working directory)
- ~90% duplicated code; the "mysql" name on the tinysite script is a misnomer — it dumps Postgres
- production-todo-postgres has NO dump script at all; it is covered only by daily EBS snapshots
- no failure alerting: no MTA, cron output discarded (backup-age alarm still an idea)
