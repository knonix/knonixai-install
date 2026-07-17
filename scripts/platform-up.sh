#!/usr/bin/env bash
# Bring up the Knonix PLATFORM host (ai.knonix.com) end-to-end.
# Requires root/sudo. Safe to re-run (idempotent).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

echo "==> Platform bring-up in $ROOT"
echo "    Knonix operator host only — fleet + billing for ALL customer installs."
echo "    Customers must use ./install.sh (never this script)."
echo

# 1. Docker group for knonix user
if getent group docker >/dev/null; then
  if ! id -nG knonix 2>/dev/null | grep -qw docker; then
    usermod -aG docker knonix
    echo "    Added knonix to docker group (re-login needed for non-root docker)"
  fi
fi

# 2. Ensure image tag is pullable (not missing :local)
if [[ -f .env ]]; then
  if grep -qE '^[[:space:]]*KNONIX_IMAGE_TAG=local' .env; then
    if ! docker image inspect ghcr.io/knonix/knonixai:local >/dev/null 2>&1; then
      echo "    Switching KNONIX_IMAGE_TAG local -> latest"
      sed -i.bak -E 's|^[[:space:]]*KNONIX_IMAGE_TAG=local|KNONIX_IMAGE_TAG=latest|' .env
      sed -i.bak -E 's|^[[:space:]]*KNONIX_IMAGE_PULL_POLICY=never|KNONIX_IMAGE_PULL_POLICY=always|' .env
      rm -f .env.bak
    fi
  fi
  # Platform flags
  grep -qE '^[[:space:]]*KNONIX_PLATFORM_MODE=' .env || echo 'KNONIX_PLATFORM_MODE=cloud' >> .env
  grep -qE '^[[:space:]]*KNONIX_PLATFORM_OWNER=' .env || echo 'KNONIX_PLATFORM_OWNER=true' >> .env
  sed -i.bak -E 's|^[[:space:]]*KNONIX_PLATFORM_MODE=.*|KNONIX_PLATFORM_MODE=cloud|' .env
  sed -i.bak -E 's|^[[:space:]]*KNONIX_PLATFORM_OWNER=.*|KNONIX_PLATFORM_OWNER=true|' .env
  rm -f .env.bak
fi

# 3. Build + start platform stack
COMPOSE=(docker compose
  -f docker-compose.yml
  -f docker-compose.proxy.yml
  -f docker-compose.platform.yml
  -f docker-compose.fix-health.yml
  --profile auth
  --profile connected)
# NVIDIA GPU host (optional)
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 \
  && [[ -f docker-compose.gpu.yml ]]; then
  COMPOSE+=(-f docker-compose.gpu.yml)
fi

echo "==> Building license-service image"
docker build -t "knonix/license-service:local" ./platform/license-service

echo "==> Pulling app image if needed"
TAG="$(grep -E '^[[:space:]]*KNONIX_IMAGE_TAG=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\"' | tr -d \"'\" || true)"
TAG="${TAG:-latest}"
if [[ "$TAG" != "local" ]]; then
  docker pull "ghcr.io/knonix/knonixai:${TAG}" || true
fi

echo "==> Starting compose stack (platform)"
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> Waiting for health endpoints"
for i in $(seq 1 40); do
  if curl -fsS --max-time 3 http://127.0.0.1:8787/healthz | grep -q '"ok"'; then
    echo "    license-service healthz OK"
    break
  fi
  sleep 2
done

DOMAIN="$(grep -E '^[[:space:]]*KNONIX_DOMAIN=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\"' | tr -d \"'\" || true)"
DOMAIN="${DOMAIN:-ai.knonix.com}"
for i in $(seq 1 40); do
  if curl -fsk --max-time 5 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/api/knonix/health" | grep -q '"status":"ok"'; then
    echo "    app health OK"
    break
  fi
  sleep 2
done

# 4. Models
CHAT_MODEL="$(grep -E '^[[:space:]]*KNONIX_MODEL=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\"' | tr -d \"'\" || true)"
CHAT_MODEL="${CHAT_MODEL:-qwen3:8b}"
CODING_MODEL="$(grep -E '^[[:space:]]*KNONIX_CODING_MODEL=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\"' | tr -d \"'\" || true)"
CODING_MODEL="${CODING_MODEL:-qwen2.5-coder:7b}"
echo "==> Ensuring Ollama models (${CHAT_MODEL}, nomic-embed-text, ${CODING_MODEL})"
for m in "${CHAT_MODEL}" nomic-embed-text "${CODING_MODEL}"; do
  echo "    pull $m"
  "${COMPOSE[@]}" exec -T ollama ollama pull "$m" || echo "    WARN: pull failed for $m"
done

# 5. Org-only Spaces: every active membership gets space_members access
if [[ -x scripts/sync-org-space-access.sh ]]; then
  echo "==> Syncing Spaces access for org members"
  bash scripts/sync-org-space-access.sh || echo "    WARN: space access sync failed (non-fatal)"
elif [[ -f scripts/sync-org-space-access.sh ]]; then
  echo "==> Syncing Spaces access for org members"
  bash scripts/sync-org-space-access.sh || echo "    WARN: space access sync failed (non-fatal)"
fi

# 6. Verify
echo "==> Stack status"
"${COMPOSE[@]}" ps

echo "==> Smoke checks"
curl -fsS http://127.0.0.1:8787/healthz && echo
ADMIN="$(grep -E '^[[:space:]]*KNONIX_LICENSE_ADMIN_TOKEN=' .env | tail -1 | cut -d= -f2-)"
if [[ -n "$ADMIN" ]]; then
  curl -fsS http://127.0.0.1:8787/v1/licenses -H "Authorization: Bearer ${ADMIN}" | head -c 200
  echo
fi
curl -fsk --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/api/knonix/health" && echo
curl -fsk --resolve "${DOMAIN}:443:127.0.0.1" -o /dev/null -w "fleet_page:%{http_code}\n" "https://${DOMAIN}/admin/fleet"

# 7. DMZ note
echo
echo "==> Done."
echo "    Local:  https://${DOMAIN}/ (SNI to 127.0.0.1)"
echo "    Login:  https://${DOMAIN}/auth/login  as adam.schappell@knonix.com"
echo "    Fleet:  https://${DOMAIN}/admin/fleet"
echo "    Admin:  https://${DOMAIN}/admin"
echo
echo "    Public HTTPS requires gateway DMZ/port-forward 80+443 -> 192.168.0.2"
echo "    Prefer: sudo bash /home/knonix/apply-dmz-ip.sh  (single LAN IP)"
echo
echo "    Owner password was reset to SESSION_CHECKPOINT value if you used the"
echo "    GoTrue admin reset during bring-up — change it after first login."
