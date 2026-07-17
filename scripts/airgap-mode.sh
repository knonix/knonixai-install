#!/usr/bin/env bash
# Configure .env for air-gapped / GCC High installs (audit P0-3, P2-2, §5.1).
# - No outbound seat heartbeats
# - Never pull images from GHCR on up
# - Prefer invite-only auth on public domains
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] || { echo "ERROR: .env missing"; exit 1; }

set_env() {
  local key="$1" val="$2"
  if grep -qE "^[[:space:]]*${key}=" .env 2>/dev/null; then
    sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${val}|" .env && rm -f .env.bak
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

set_env KNONIX_LICENSE_MODE offline
set_env KNONIX_IMAGE_PULL_POLICY never
set_env KNONIX_ALLOW_FRONTIER false
# Optional: pin current local image id if present
if docker image inspect ghcr.io/knonix/knonixai:latest >/dev/null 2>&1; then
  DIGEST="$(docker image inspect ghcr.io/knonix/knonixai:latest --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  if [[ -n "${DIGEST}" && "${DIGEST}" == *@* ]]; then
    # Keep tag for readability; pull_policy never avoids refresh
    echo "    Local image digest: ${DIGEST}"
  fi
fi

DOMAIN="$(grep -E '^[[:space:]]*KNONIX_DOMAIN=' .env 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"' || true)"
if [[ -n "${DOMAIN}" && "${DOMAIN}" != "localhost" ]]; then
  set_env KNONIX_AUTH_DISABLE_SIGNUP true
  echo "    Signup disabled (create users via invite / admin after first owner)."
fi

echo "==> Air-gap / offline posture written to .env"
echo "    KNONIX_LICENSE_MODE=offline  (no heartbeat-cron profile)"
echo "    KNONIX_IMAGE_PULL_POLICY=never"
echo "    Bring up without --profile connected:"
echo "      docker compose -f docker-compose.yml --profile auth up -d"
