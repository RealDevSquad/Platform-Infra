#!/usr/bin/env bash
# Two-way anonymization for the Infra tree.
#   ./scripts/sanitize.sh            forward: real values -> {{PLACEHOLDER}}
#   ./scripts/sanitize.sh --restore  reverse: {{PLACEHOLDER}} -> real values
#
# The mapping lives OUTSIDE this repo (never committed):
#   <workspace>/.infra-private/values.env   (KEY=value lines; {{KEY}} is the placeholder)
# Override location with INFRA_VALUES=/path/to/values.env.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES="${INFRA_VALUES:-$(cd "$REPO_ROOT/.." && pwd)/.infra-private/values.env}"

MODE="forward"
[ "${1:-}" = "--restore" ] && MODE="restore"
[ "${1:-}" = "--check" ] && MODE="check" # scan-only (pre-commit hook): mutates nothing

if [ ! -f "$VALUES" ]; then
  if [ "$MODE" = "check" ]; then
    echo "warn: mapping not found ($VALUES) — shape/ticket scan only." >&2
    VALUES=""
  else
    echo "mapping file not found: $VALUES" >&2
    exit 1
  fi
fi

FILES=$(find "$REPO_ROOT" -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.sh" -o -name "*.conf" -o -name "*.tf" -o -name "*.example" -o -name "Makefile" -o -name "Caddyfile*" \) ! -path "*/.git/*" ! -path "*/.terraform/*" ! -name "sanitize.sh")

# Process longest values first so a value that is a substring of another
# (e.g. KEY_PAIR_NAME=rds-services-server vs a hypothetical rds-services) is
# replaced before its shorter sibling can mangle it. Comments/blanks dropped.
MAPPING=""
[ -n "$VALUES" ] && MAPPING=$(grep -vE '^[[:space:]]*(#|$)' "$VALUES" \
  | awk -F= '{ v=substr($0, index($0,"=")+1); print length(v)"\t"$0 }' \
  | sort -rn | cut -f2-)

count=0
[ "$MODE" = "check" ] && MAPPING=""   # never substitute in check mode
while IFS='=' read -r key value; do
  [ -z "$key" ] && continue
  for f in $FILES; do
    if [ "$MODE" = "forward" ]; then
      grep -qF "$value" "$f" 2>/dev/null || continue
      perl -pi -e 'BEGIN{$v=shift;$k=shift} s/\Q$v\E/\{\{$k\}\}/g' "$value" "$key" "$f"
    else
      grep -qF "{{$key}}" "$f" 2>/dev/null || continue
      perl -pi -e 'BEGIN{$k=shift;$v=shift} s/\{\{\Q$k\E\}\}/$v/g' "$key" "$value" "$f"
    fi
    count=$((count+1))
  done
done <<< "$MAPPING"

[ "$MODE" = "check" ] && echo "check mode: scan only, no substitutions." \
  || echo "$MODE pass done: $count file-substitutions applied."
if [ "$MODE" != "restore" ]; then
  # Guard: a {{PLACEHOLDER}} inside YAML flow context (e.g. `name: {{X}}`)
  # parses as a nested map and breaks the file. No mapping value should ever
  # collide with real YAML config — if one does, fix the mapping, not the file.
  yaml_bad=$(grep -rnE '\{\{' "$REPO_ROOT" --include="*.yaml" --include="*.yml" --exclude-dir=.terraform 2>/dev/null | grep -v "scripts/sanitize.sh" || true)
  if [ -n "$yaml_bad" ]; then
    echo "ERROR: placeholder left in YAML — a mapping value collides with real config:" >&2
    echo "$yaml_bad" >&2
    echo "Fix: remove or rename that mapping key in the private values file, then re-run." >&2
    exit 3
  fi
  # Residue scan. Deliberately holds NO real identifiers in this (committed)
  # script: part (a) derives its checklist from the private mapping's VALUES;
  # part (b) is generic AWS-identifier shapes only. Output is filenames, never
  # the matched value.
  echo "Residue scan (should print nothing):"
  SCAN_INCLUDES=(--include="*.md" --include="*.yml" --include="*.yaml" --include="*.sh" --include="*.conf" --include="*.tf" --include="*.example" --include="*.cron" --include="Makefile" --include="Caddyfile*")
  bad=0
  if [ -n "$VALUES" ]; then
    while IFS='=' read -r key value; do
      [ -z "$key" ] && continue
      hits=$(grep -rlF "${SCAN_INCLUDES[@]}" --exclude-dir=.terraform -- "$value" "$REPO_ROOT" 2>/dev/null | grep -v "scripts/sanitize.sh" || true)
      if [ -n "$hits" ]; then
        echo "  REAL VALUE for {{$key}} present in:"; echo "$hits" | sed 's/^/    /'
        bad=1
      fi
    done <<< "$(grep -vE '^[[:space:]]*(#|$)' "$VALUES")"
  fi
  hits=$(grep -rlE "${SCAN_INCLUDES[@]}" --exclude-dir=.terraform -- '(^|[^[:alnum:]-])i-0[a-f0-9]{8,}|vol-0[a-f0-9]{8,}|sg-0[a-f0-9]{8,}|subnet-0[a-f0-9]{8,}|vpc-0[a-f0-9]{8,}|eipalloc-[a-f0-9]|eipassoc-[a-f0-9]|policy-0[a-f0-9]{8,}|AIPA[0-9A-Z]{10,}|AROA[0-9A-Z]{10,}|AKIA[0-9A-Z]{16}|RDS-[0-9]+' "$REPO_ROOT" 2>/dev/null | grep -v "scripts/sanitize.sh" || true)
  if [ -n "$hits" ]; then
    echo "  AWS-shaped identifier present in:"; echo "$hits" | sed 's/^/    /'
    bad=1
  fi
  if [ "$bad" -eq 1 ]; then
    echo "ERROR: residue found — anonymize it (add to the private mapping if new), then re-run." >&2
    exit 4
  fi
  echo "  clean."
fi
