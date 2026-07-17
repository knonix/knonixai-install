#!/usr/bin/env bash
#
# verify-install.sh — Post-install health + seat-reporting readiness check.
# Run from the knonixai-install directory after ./install.sh (customer path).
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

echo "-- Install posture (public customer vs Knonix platform) --"
owner="$(read_env KNONIX_PLATFORM_OWNER)"
pmode="$(read_env KNONIX_PLATFORM_MODE)"
admin_tok="$(read_env KNONIX_LICENSE_ADMIN_TOKEN)"
if [[ "${owner}" == "true" && "${pmode}" == "cloud" ]]; then
  echo "INFO  Platform host (Knonix fleet + billing). Customers never use this posture."
  echo "      Fleet board: https://${DOMAIN:-ai.knonix.com}/admin/fleet (admin token)"
  if [[ -z "${admin_tok}" ]]; then
    echo "WARN  KNONIX_LICENSE_ADMIN_TOKEN empty — fleet board will refuse operators."
  else
    echo "OK    LICENSE_ADMIN_TOKEN set (operator-only)"
  fi
else
  # Public / customer install expectations
  if [[ "${owner}" == "true" ]]; then
    echo "FAIL  KNONIX_PLATFORM_OWNER=true — customer installs must stay false."
    echo "      Re-run ./install.sh or set KNONIX_PLATFORM_OWNER=false"
    fail=1
  else
    echo "OK    PLATFORM_OWNER=false (local software only)"
  fi
  if [[ "${pmode}" == "cloud" ]]; then
    echo "FAIL  KNONIX_PLATFORM_MODE=cloud without PLATFORM_OWNER — invalid."
    echo "      Customers: sovereign. Platform host: sudo ./scripts/platform-up.sh"
    fail=1
  else
    echo "OK    PLATFORM_MODE=${pmode:-sovereign/default}"
  fi
  if [[ -n "${admin_tok}" ]]; then
    echo "FAIL  KNONIX_LICENSE_ADMIN_TOKEN is set — operator secret must not live on customer installs."
    echo "      Clear it from .env (fleet board is on the Knonix platform only)."
    fail=1
  else
    echo "OK    LICENSE_ADMIN_TOKEN unset (no fleet admin access)"
  fi
  if "${DOCKER[@]}" ps --format '{{.Names}}' 2>/dev/null | grep -q 'license-service'; then
    echo "WARN  license-service is running on a non-platform posture host."
    echo "      That service is for Knonix fleet/billing only — not customer installs."
  fi
fi
echo

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
  # End-to-end HTTPS health (public URL may fail on LAN hairpin — try resolve too)
  if curl -fsS --max-time 10 "${BASE}/api/knonix/health" >/dev/null 2>&1; then
    echo "OK    HTTPS health responds at ${BASE}/api/knonix/health"
  elif curl -fsSk --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" \
      "https://${DOMAIN}/api/knonix/health" >/dev/null 2>&1; then
    echo "OK    HTTPS health OK via --resolve ${DOMAIN}:443:127.0.0.1 (LAN hairpin)"
  else
    echo "WARN  ${BASE}/api/knonix/health not reachable yet (cert/DNS/hairpin may still be issuing)"
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
if [[ -z "${health_json}" && -n "${DOMAIN}" && "${DOMAIN}" != "localhost" ]]; then
  health_json="$(curl -fsSk --max-time 15 --resolve "${DOMAIN}:443:127.0.0.1" \
    "https://${DOMAIN}/api/knonix/health" 2>/dev/null || true)"
fi
if [[ -z "${health_json}" ]]; then
  health_json="$(curl -fsS --max-time 10 "http://127.0.0.1:3000/api/knonix/health" 2>/dev/null || true)"
fi
if [[ -z "${health_json}" ]]; then
  echo "FAIL  ${BASE}/api/knonix/health did not respond"
  fail=1
else
  echo "${health_json}" | python3 -m json.tool 2>/dev/null || echo "${health_json}"
  status="$(echo "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
  ready="$(echo "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ready',''))" 2>/dev/null || true)"
  auth_cfg="$(echo "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('checks',{}).get('authConfigured',''))" 2>/dev/null || true)"
  if [[ "${status}" != "ok" ]]; then
    echo "FAIL  health status is '${status}' (want ok)"
    fail=1
  fi
  if [[ "${ready}" == "False" || "${ready}" == "false" || -z "${ready}" ]]; then
    echo "FAIL  health ready is not true"
    fail=1
  else
    echo "OK    ready=true"
  fi
  if [[ "${auth_cfg}" == "False" || "${auth_cfg}" == "false" ]]; then
    echo "FAIL  authConfigured=false — Supabase keys missing or image health bug"
    echo "      Confirm NEXT_PUBLIC_SUPABASE_* in .env; ensure scripts/knonix-entrypoint.sh is mounted"
    fail=1
  else
    echo "OK    authConfigured=true"
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
    echo "WARN  Connected mode without enrollment token — seats will NOT report to Knonix for billing."
    echo "      Set KNONIX_LICENSE_SERVICE_TOKEN from your Knonix license email, then:"
    echo "      docker compose up -d knonixai heartbeat-cron"
    fail=1
  fi
  if [[ -z "${hb}" ]]; then
    echo "WARN  KNONIX_HEARTBEAT_SECRET missing — daily seat cron cannot run."
    fail=1
  else
    echo
    echo "-- Heartbeat probe (local → optional outbound seat report to Knonix) --"
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
echo "-- Preflight mounts --"
if [[ -f scripts/preflight-mounts.sh ]]; then
  if bash scripts/preflight-mounts.sh; then
    echo "OK    bind-mount sources present"
  else
    echo "FAIL  missing compose bind-mount sources"
    fail=1
  fi
fi

echo
echo "-- Sessions & Spaces (multi-user / org-only) --"
# DB-level proof: auth sessions are per user_id; Spaces listed via space_members ∩ org.
if "${DOCKER[@]}" compose exec -T postgres psql -U "${POSTGRES_USER:-knonixai}" -d "${POSTGRES_DB:-knonixai}" -v ON_ERROR_STOP=1 -c "
SELECT
  (SELECT count(*) FROM auth.users) AS auth_users,
  (SELECT count(*) FROM auth.sessions) AS auth_sessions,
  (SELECT count(DISTINCT user_id) FROM auth.sessions) AS users_with_sessions,
  (SELECT count(*) FROM memberships WHERE status = 'active') AS active_members,
  (SELECT count(*) FROM spaces) AS spaces,
  (SELECT count(*) FROM space_members) AS space_member_rows;
" 2>/dev/null; then
  # Orphan check: active members missing space_members for org spaces
  missing="$("${DOCKER[@]}" compose exec -T postgres psql -U "${POSTGRES_USER:-knonixai}" -d "${POSTGRES_DB:-knonixai}" -tA -c "
SELECT count(*) FROM spaces s
JOIN memberships m ON m.org_id = s.org_id AND m.status = 'active' AND m.user_id IS NOT NULL AND m.user_id <> ''
WHERE NOT EXISTS (
  SELECT 1 FROM space_members sm WHERE sm.space_id = s.id AND sm.user_id = m.user_id
);
" 2>/dev/null | tr -d '[:space:]')"
  if [[ "${missing}" == "0" ]]; then
    echo "OK    every active org member has space_members access on org Spaces"
  elif [[ -n "${missing}" && "${missing}" != "0" ]]; then
    echo "WARN  ${missing} active org member(s) missing space_members — run: ./scripts/sync-org-space-access.sh"
  fi
  # Session isolation: no session row shared across users (PK is session id)
  shared="$("${DOCKER[@]}" compose exec -T postgres psql -U "${POSTGRES_USER:-knonixai}" -d "${POSTGRES_DB:-knonixai}" -tA -c "
SELECT count(*) FROM (
  SELECT id FROM auth.sessions GROUP BY id HAVING count(DISTINCT user_id) > 1
) x;
" 2>/dev/null | tr -d '[:space:]')"
  if [[ "${shared}" == "0" ]]; then
    echo "OK    auth.sessions are per-user (no shared session ids)"
  else
    echo "FAIL  found sessions linked to multiple users"
    fail=1
  fi
else
  echo "WARN  could not query auth.sessions / space_members (postgres not ready?)"
fi

echo
echo "-- Updates --"
if [[ -f VERSION ]]; then
  echo "    Installer VERSION: $(tr -d '[:space:]' < VERSION)"
fi
if [[ -x ./scripts/check-updates.sh ]]; then
  # Non-fatal: exit 2 means updates available
  set +e
  ./scripts/check-updates.sh
  upd=$?
  set -e
  if [[ "${upd}" -eq 2 ]]; then
    echo "    (Update available — see CHANGELOG.md; not a failure for this check.)"
  fi
else
  echo "    Tip: run ./scripts/check-updates.sh periodically"
fi

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "==> Verification PASSED"
  echo "    Next: open ${BASE}/auth/sign-up → create the first admin account"
  echo "          then open ${BASE}/admin to confirm license + models."
  echo "    Later: ./scripts/check-updates.sh when you want the newest image."
  exit 0
else
  echo "==> Verification found issues (see WARN/FAIL above)."
  echo "    Re-run ./install.sh after fixing .env, or open Admin for details."
  exit 1
fi
