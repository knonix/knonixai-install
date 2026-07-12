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
