#!/usr/bin/env bash
#
# verify-install.sh — Post-install health + fleet readiness check.
# Run from the knonixai-install directory after ./install.sh.
#
set -euo pipefail

cd "$(dirname "$0")/.."

read_env() {
  local key="$1" v
  v="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" .env 2>/dev/null \
        | grep -vE "^[[:space:]]*#" | tail -1 | cut -d= -f2- || true)"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

DOMAIN="$(read_env KNONIX_DOMAIN)"
if [[ -n "${DOMAIN}" && "${DOMAIN}" != "localhost" ]]; then
  BASE="https://${DOMAIN}"
elif [[ "${DOMAIN}" == "localhost" ]]; then
  BASE="https://localhost"
else
  BASE="http://localhost:3000"
fi

echo "==> KnonixAI install verification"
echo "    Target: ${BASE}"
echo

fail=0

# Prefer plain docker; fall back to sudo when the user is not in the docker group.
DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  fi
fi

echo "-- Docker services --"
if "${DOCKER[@]}" compose ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null; then
  :
else
  echo "WARNING: docker compose ps failed (permission or compose not available)"
  fail=1
fi
echo

echo "-- Web server (HTTPS reverse proxy) --"
if [[ -n "${DOMAIN}" ]]; then
  # Domain mode uses the proxy overlay; include it so `compose ps caddy` works.
  COMPOSE_PS=("${DOCKER[@]}" compose -f docker-compose.yml)
  if [[ -f docker-compose.proxy.yml ]]; then
    COMPOSE_PS+=(-f docker-compose.proxy.yml)
  fi
  caddy_running=0
  if "${COMPOSE_PS[@]}" ps caddy 2>/dev/null | grep -qiE 'Up|running'; then
    caddy_running=1
  elif "${DOCKER[@]}" ps --format '{{.Names}} {{.Status}}' 2>/dev/null \
    | grep -qiE 'caddy.*(Up|running)'; then
    # Orphan / alternate project name still counts as healthy web server
    caddy_running=1
  fi
  if [[ "${caddy_running}" -eq 1 ]]; then
    echo "OK    Caddy is running for domain ${DOMAIN}"
  else
    echo "FAIL  KNONIX_DOMAIN=${DOMAIN} but Caddy is not running"
    echo "      Re-run: ./install.sh   (auto-applies docker-compose.proxy.yml)"
    echo "      Or: docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d"
    fail=1
  fi
  # Ports 80/443 should be published on the host when Caddy is active
  if command -v ss >/dev/null 2>&1; then
    if ss -lnt 2>/dev/null | grep -qE ':(80|443)\b'; then
      echo "OK    Host is listening on 80 and/or 443"
    else
      echo "WARN  Ports 80/443 not detected listening — HTTPS may fail from the internet"
    fi
  fi
  # End-to-end HTTPS health (same as users hit)
  if curl -fsS --max-time 10 "${BASE}/api/knonix/health" >/dev/null 2>&1; then
    echo "OK    HTTPS health responds at ${BASE}/api/knonix/health"
  else
    echo "WARN  ${BASE}/api/knonix/health not reachable yet (cert/DNS may still be issuing)"
  fi
else
  echo "OK    Local mode (no KNONIX_DOMAIN) — app on http://localhost:3000"
  echo "      To enable automatic HTTPS web server, set in .env:"
  echo "        KNONIX_DOMAIN=ai.yourcompany.com"
  echo "        KNONIX_ACME_EMAIL=you@yourcompany.com"
  echo "      then re-run ./install.sh"
fi
echo

echo "-- App health --"
health_json="$(curl -fsS --max-time 15 "${BASE}/api/knonix/health" 2>/dev/null || true)"
if [[ -z "${health_json}" ]]; then
  echo "FAIL  ${BASE}/api/knonix/health did not respond"
  fail=1
else
  echo "${health_json}" | python3 -m json.tool 2>/dev/null || echo "${health_json}"
  status="$(echo "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
  ready="$(echo "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ready',''))" 2>/dev/null || true)"
  if [[ "${status}" != "ok" && "${status}" != "degraded" ]]; then
    fail=1
  fi
  # Prefer structured ready flag when present
  if [[ "${ready}" == "False" || "${ready}" == "false" ]]; then
    fail=1
  fi
fi
echo

echo "-- Ollama models --"
if "${DOCKER[@]}" compose exec -T ollama ollama list 2>/dev/null; then
  :
else
  echo "WARNING: could not list Ollama models (check ollama container)"
  # Don't hard-fail if health already reports models installed
fi
echo

echo "-- Fleet / license config (no secrets printed) --"
mode="$(read_env KNONIX_LICENSE_MODE)"; mode="${mode:-connected}"
url="$(read_env KNONIX_LICENSE_SERVICE_URL)"
token="$(read_env KNONIX_LICENSE_SERVICE_TOKEN)"
hb="$(read_env KNONIX_HEARTBEAT_SECRET)"
key="$(read_env KNONIX_LICENSE_KEY)"
echo "    KNONIX_LICENSE_MODE=${mode}"
echo "    KNONIX_LICENSE_SERVICE_URL=${url:-<empty>}"
echo "    KNONIX_LICENSE_SERVICE_TOKEN set: $([[ -n "${token}" ]] && echo yes || echo NO)"
echo "    KNONIX_LICENSE_KEY set: $([[ -n "${key}" ]] && echo yes || echo 'no (assigned on first admin sign-up)')"
echo "    KNONIX_HEARTBEAT_SECRET set: $([[ -n "${hb}" ]] && echo yes || echo NO)"

if [[ "${mode}" == "connected" ]]; then
  if [[ -z "${token}" ]]; then
    echo "WARN  Connected mode without fleet token — seats will NOT report to Knonix."
    echo "      Set KNONIX_LICENSE_SERVICE_TOKEN from your Knonix license email, then:"
    echo "      docker compose up -d knonixai heartbeat-cron"
    fail=1
  fi
  if [[ -z "${hb}" ]]; then
    echo "WARN  KNONIX_HEARTBEAT_SECRET missing — daily seat cron cannot run."
    fail=1
  else
    echo
    echo "-- Heartbeat probe (local) --"
    hb_out="$(curl -fsS --max-time 20 -X POST "${BASE}/api/knonix/heartbeat" \
      -H "Authorization: Bearer ${hb}" \
      -H 'Content-Type: application/json' -d '{}' 2>/dev/null || true)"
    if [[ -n "${hb_out}" ]]; then
      echo "${hb_out}" | python3 -m json.tool 2>/dev/null || echo "${hb_out}"
    else
      echo "WARN  Heartbeat endpoint did not succeed (app may still be starting)."
      fail=1
    fi
  fi
fi

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "==> Verification PASSED"
  echo "    Next: open ${BASE}/auth/sign-up → create the first admin account"
  echo "          then open ${BASE}/admin to confirm license + models."
  exit 0
else
  echo "==> Verification found issues (see WARN/FAIL above)."
  echo "    Re-run ./install.sh after fixing .env, or open Admin for details."
  exit 1
fi
