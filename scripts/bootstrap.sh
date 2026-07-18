#!/usr/bin/env bash
# Bootstrap a FRESH Ubuntu (arm64) box into the RDS services server.
# Step 2 of the 1-2-3 rebuild (see docs/new-box-bootstrap.md).
# Idempotent: safe to re-run. Never run against the legacy box.
#
# Usage (from the repo root, on the new box):
#   ./scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/docker"

step() { echo; echo "==> $1"; }

# Gate: this provisions an EC2 box. Refuse anywhere else (laptops!) so the
# local flow and the box flow can never be mixed. Non-AWS server escape
# hatch: BOOTSTRAP_FORCE=1.
if [ "${BOOTSTRAP_FORCE:-}" != "1" ]; then
  TOK=$(curl -s -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
  IID=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $TOK" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)
  case "$IID" in
    i-*) : ;; # on EC2 — proceed
    *)
      echo "STOP: no EC2 metadata service — this is not an EC2 instance."
      echo "bootstrap.sh provisions a fresh box. On a laptop use the local flow:"
      echo "  docker/README.md quickstart (cp env examples, then 'make up')."
      echo "Provisioning a non-AWS server on purpose? Re-run with BOOTSTRAP_FORCE=1."
      exit 3
      ;;
  esac
fi

step "1/6 Swap (2G) — headroom for JVM + MySQL, essential on small instances"
if ! swapon --show --noheadings | grep -q swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  echo "    2G swapfile active + persisted in fstab."
else
  echo "    swap already active: $(swapon --show --noheadings | head -1)"
fi

step "2/6 Docker engine (official apt repo)"
if ! command -v docker >/dev/null 2>&1; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "    docker installed. NOTE: re-login (or 'newgrp docker') for group to apply."
else
  echo "    docker already present: $(docker --version)"
fi

step "3/6 Docker log rotation (daemon.json) — the legacy box lacked this"
if [ ! -f /etc/docker/daemon.json ]; then
  echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' \
    | sudo tee /etc/docker/daemon.json >/dev/null
  sudo systemctl restart docker
  echo "    log rotation configured (10m x 3 per container)."
else
  echo "    /etc/docker/daemon.json exists — leaving as-is."
fi

step "4/6 Environment files"
missing=0
for ex in env/*.env.example; do
  live="${ex%.example}"
  if [ ! -f "$live" ]; then
    cp "$ex" "$live"
    chmod 600 "$live"
    echo "    created $live from example — FILL REAL VALUES (index: docs/secrets.md)"
    missing=1
  fi
done
if [ ! -f .env ]; then
  cat > .env <<'EOF'
DOCKERHUB_USER=CHANGEME
COMPOSE_FILE=compose.yaml:compose.prod.yaml
COMPOSE_PROFILES=todo,skilltree,tinysite,discord
ENV_PROVIDER=manual
EOF
  chmod 600 .env
  echo "    created .env — set DOCKERHUB_USER"
  missing=1
fi
if [ "$missing" -eq 1 ]; then
  echo
  echo "    STOP: fill the env files above with real values, then re-run."
  echo "    (Prod values live in each repo's GitHub Environments; names in docs/secrets.md.)"
  exit 2
fi
grep -q "CHANGEME" .env && { echo "    STOP: .env still has CHANGEME values."; exit 2; }

step "5/6 Validate + start"
docker compose config --quiet && echo "    compose config: VALID"
docker compose up -d

step "6/6 Smoke check"
sleep 10
docker compose ps --format '{{.Name}}: {{.Status}}'
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://localhost/nope || true)
echo "    caddy fallthrough via :80 -> HTTP $code (308 = https redirect active, healthy)"
echo
echo "Done. Full verification + DNS cutover: docs/new-box-bootstrap.md"
