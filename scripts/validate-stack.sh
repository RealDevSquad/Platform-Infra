#!/usr/bin/env bash
# Validate the running stack by BEHAVIOR only — never reads env files, never
# prints a secret or token. Safe to run with dummy or real credentials.
#
#   ./scripts/validate-stack.sh                    # layer 1+2 (+3 where possible)
#   TODO_TOKEN=... SKILLTREE_TOKEN=... TINY_TOKEN=... ./scripts/validate-stack.sh
#     ^ optional: paste tokens from a logged-in staging browser session to run
#       the authenticated layer. Values are used in request headers only and
#       are never echoed.
#
# Layers:
#   1. Containers up + routing matrix (expected per-service codes)
#   2. Wiring: broker<->rabbitmq consumption, DB health
#   3. Authenticated requests (only with real creds/tokens; skips gracefully)
set -uo pipefail

BASE="${BASE_URL:-http://localhost}"
pass=0; fail=0; skip=0

say()  { printf '%-58s %s\n' "$1" "$2"; }
chk()  { # chk <desc> <url> <expected-codes-regex> [curl-args...]
  local desc="$1" url="$2" want="$3"; shift 3
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$@" "$url" 2>/dev/null)
  [ -n "$code" ] || code="000"
  if [[ "$code" =~ ^($want)$ ]]; then say "$desc" "PASS ($code)"; pass=$((pass+1));
  else say "$desc" "FAIL (got $code, want $want)"; fail=$((fail+1)); fi
}

echo "== Layer 1: containers =="
running=$(docker ps --filter "label=com.docker.compose.project=rds-services" --format '{{.Names}}' | wc -l | tr -d ' ')
not_up=$(docker ps -a --filter "label=com.docker.compose.project=rds-services" --format '{{.Names}} {{.State}}' | awk '$2!="running"{print $1}' | grep -v mongo-init || true)
if [ "$running" -eq 0 ]; then say "stack not running (0 containers — run make up)" "FAIL"; fail=$((fail+1))
elif [ -z "$not_up" ]; then say "all non-init containers running ($running)" "PASS"; pass=$((pass+1))
else say "containers not running: $not_up" "FAIL"; fail=$((fail+1)); fi

echo "== Layer 1: routing matrix (through caddy) =="
chk "todo    GET /todo/api/schema"          "$BASE/todo/api/schema"          "200"
chk "skilltree GET /skilltree/ (JWT-gated)" "$BASE/skilltree/"               "401"
chk "tinysite GET /tiny/v1/users/self"      "$BASE/tiny/v1/users/self"       "401"
chk "tinysite GET /tiny/v1/urls/zzz (DB round-trip)" "$BASE/tiny/v1/urls/zzz" "404"
chk "discord GET /discord-service/health"   "$BASE/discord-service/health"   "200"
chk "caddy fallthrough /definitely-nope"    "$BASE/definitely-nope"          "404|308"

echo "== Layer 2: wiring =="
if docker logs --tail 60 discord-message-broker 2>&1 | grep -q "Consumer connected\|Established a connection to RabbitMQ"; then
  say "broker consuming from rabbitmq" "PASS"; pass=$((pass+1))
else say "broker consuming from rabbitmq" "FAIL (no connection line in recent logs)"; fail=$((fail+1)); fi
unhealthy=$(docker ps --filter "label=com.docker.compose.project=rds-services" --filter "health=unhealthy" --format '{{.Names}}' || true)
if [ -z "$unhealthy" ]; then say "no unhealthy containers" "PASS"; pass=$((pass+1))
else say "unhealthy: $unhealthy" "FAIL"; fail=$((fail+1)); fi

echo "== Layer 3: authenticated (skips without real creds/tokens) =="
if [ -n "${TODO_TOKEN:-}" ]; then
  chk "todo authed GET /todo/v1/users/self" "$BASE/todo/v1/users/self" "200" -H "Cookie: staging-todo-access=${TODO_TOKEN}"
else say "todo authed request" "SKIP (set TODO_TOKEN)"; skip=$((skip+1)); fi
if [ -n "${SKILLTREE_TOKEN:-}" ]; then
  chk "skilltree authed GET /skilltree/api/v1/" "$BASE/skilltree/api/v1/" "200|404" -H "Authorization: Bearer ${SKILLTREE_TOKEN}"
else say "skilltree authed request" "SKIP (set SKILLTREE_TOKEN)"; skip=$((skip+1)); fi
if [ -n "${TINY_TOKEN:-}" ]; then
  chk "tinysite authed GET /tiny/v1/users/self" "$BASE/tiny/v1/users/self" "200" -H "Cookie: token=${TINY_TOKEN}"
else say "tinysite authed request" "SKIP (set TINY_TOKEN)"; skip=$((skip+1)); fi
# discord full-chain (needs a real BOT_TOKEN in env + unpinned image): POST /queue
# is exercised implicitly by the broker consuming; a real Discord round-trip is
# observable in `docker logs discord-service` after staging events fire.

echo
echo "RESULT: $pass pass, $fail fail, $skip skipped"
[ "$fail" -eq 0 ]
