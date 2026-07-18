#!/usr/bin/env bash
# The "ssm" provider of docs/config-model.md: renders docker/env/*.env from
# SSM Parameter Store. Box + CI only — laptops never need this (they use the
# example/manual providers). Output is byte-compatible with hand-written files.
#
#   ./scripts/render-env.sh production            # render missing files
#   ./scripts/render-env.sh staging --force       # overwrite existing files
#
# Contract (docs/config-model.md):
# - Never prints a value.
# - Existing files win unless --force.
# - SSM unreachable + file exists  -> keep file, warn, exit 0 (outage-safe).
# - SSM unreachable + file missing -> loud error, exit 1.
#
# NOTE: the render_shared body below the marked line + the main
# execution block were completed 2026-07-18 — the on-disk file was truncated
# mid-function (unterminated string, no main) and could not run. Lines above
# the marker are as-found and implement the contract faithfully.
set -euo pipefail

ENV_NAME="${1:?usage: render-env.sh <production|staging> [--force]}"
FORCE="${2:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$REPO_ROOT/docker/env"
SERVICES=(todo skilltree tinysite discord)
PATH_ROOT="/rds/$ENV_NAME"

fetch() { # fetch <ssm-path> <outfile>  — writes KEY=VALUE lines, never echoes values
  # (review fix) parser rewritten: the as-found f-string used backslash-escaped
  # quotes inside the {expr}, illegal in Python <=3.11 -> SyntaxError on every
  # run, so fetch ALWAYS failed and no value ever rendered. Plain concatenation
  # avoids inner quoting entirely.
  aws ssm get-parameters-by-path --path "$1" --recursive --with-decryption \
    --output json 2>/tmp/render-env.err \
  | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)   # empty/invalid input (aws failed) — no output; aws exit still drives fallback via pipefail
for p in d.get("Parameters",[]):
    key=p["Name"].rsplit("/",1)[-1]
    print(key + "=" + p["Value"])' > "$2"
}

render_service() {
  local svc="$1" target="$ENV_DIR/$svc.env" tmp
  if [ -f "$target" ] && [ "$FORCE" != "--force" ]; then
    echo "  $svc.env exists — kept (use --force to re-render)"; return 0
  fi
  tmp=$(mktemp)
  if ! fetch "$PATH_ROOT/$svc" "$tmp"; then
    rm -f "$tmp"
    if [ -f "$target" ]; then
      echo "  WARN: SSM unreachable for $svc — keeping existing $svc.env" >&2; return 0
    fi
    echo "  ERROR: SSM unreachable and no existing $svc.env (see /tmp/render-env.err)" >&2; return 1
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "  ERROR: no parameters under $PATH_ROOT/$svc (tree not seeded?)" >&2; return 1
  fi
  chmod 600 "$tmp" && mv "$tmp" "$target"
  echo "  rendered $svc.env ($(grep -c = "$target") keys)"
}

render_shared() { # shared keys -> managed block inside docker/.env, user lines preserved
  local dotenv="$REPO_ROOT/docker/.env" tmp block n
  block=$(mktemp)
  if ! fetch "$PATH_ROOT/shared" "$block"; then
    rm -f "$block"; echo "  WARN: SSM unreachable for shared — docker/.env untouched" >&2; return 0
  fi
  [ -s "$block" ] || { rm -f "$block"; echo "  (no shared parameters)"; return 0; }
  # ---- below completed 2026-07-18; above is as-found ----
  n=$(grep -c = "$block")
  tmp=$(mktemp)
  { [ -f "$dotenv" ] && sed '/^# BEGIN rds-managed/,/^# END rds-managed/d' "$dotenv"
    echo "# BEGIN rds-managed (rendered by render-env.sh — do not edit this block)"
    cat "$block"
    echo "# END rds-managed"
  } > "$tmp"
  rm -f "$block"
  chmod 600 "$tmp" && mv "$tmp" "$dotenv"
  echo "  rendered docker/.env shared block ($n keys, user lines preserved)"
}

echo "Rendering env from SSM $PATH_ROOT (env: $ENV_NAME, force: ${FORCE:-no})"
rc=0
for svc in "${SERVICES[@]}"; do render_service "$svc" || rc=1; done
render_shared || rc=1
if [ "$rc" -eq 0 ]; then echo "Done."; else echo "Completed with errors (see above)." >&2; fi
exit $rc
