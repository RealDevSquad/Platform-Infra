#!/bin/bash
# Scheduled Docker image cleanup for the services box.
# Long-term auditable fix: this script is versioned in the Infra repo and
# installed once (see runbook); it then self-maintains via cron. Contrast with
# a one-off `docker image prune`, which reclaims space once and re-accumulates.
#
# Conservative by design: only removes unused images OLDER THAN 7 days, so an
# image pulled mid-deploy is never a candidate. In-use images are always kept.
set -euo pipefail

LOG_TAG="docker-prune"
log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $1"; }

log "starting; disk before:"
df -h / | awk 'NR==2 {print "  root " $3 " used / " $2 " (" $5 ")"}'

# Remove unused images older than 7 days (168h). -a includes unreferenced
# tagged images (the dangling todo-backend layers), not just <none> ones.
reclaimed=$(docker image prune -af --filter "until=168h" | awk '/Total reclaimed space/ {print}')
log "${reclaimed:-Total reclaimed space: 0B}"

log "disk after:"
df -h / | awk 'NR==2 {print "  root " $3 " used / " $2 " (" $5 ")"}'
log "done"
