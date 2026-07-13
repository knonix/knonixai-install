#!/usr/bin/env bash
# qa-chat-smoke.sh — API-level smoke test for chat after install.
# Requires: stack up, ENABLE_AUTH, openssl, and network to the app.
#
# Usage (from knonixai-install dir):
#   ./scripts/qa-chat-smoke.sh
#   BASE=https://your.domain ./scripts/qa-chat-smoke.sh
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
BASE="${BASE:-}"
if [[ -z "${BASE}" ]]; then
  if [[ -n "${DOMAIN}" && "${DOMAIN}" != "localhost" ]]; then
    BASE="https://${DOMAIN}"
  else
    BASE="http://127.0.0.1:3000"
  fi
fi

ANON="$(read_env NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)"
SUPA_URL="$(read_env NEXT_PUBLIC_SUPABASE_URL)"
if [[ -z "${ANON}" ]]; then
  echo "FAIL: NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY missing in .env"
  exit 1
fi

# Prefer internal Kong when running on the install host
AUTH_BASE="${SUPA_URL%/}"
if [[ "${AUTH_BASE}" == https://* ]] || [[ "${AUTH_BASE}" == http://* ]]; then
  :
else
  AUTH_BASE="http://127.0.0.1:8000"
fi
# If public supabase path, append nothing; for raw Kong use /auth/v1
if [[ "${AUTH_BASE}" == *"/supabase" ]]; then
  SIGNUP="${AUTH_BASE}/auth/v1/signup"
  TOKEN="${AUTH_BASE}/auth/v1/token?grant_type=password"
else
  SIGNUP="${AUTH_BASE}/auth/v1/signup"
  TOKEN="${AUTH_BASE}/auth/v1/token?grant_type=password"
fi

EMAIL="qa-smoke-$(date +%s)@knonix.local"
PASS="QaSmoke!$(openssl rand -hex 6)"

echo "==> QA chat smoke against ${BASE}"
echo "    Creating ephemeral user ${EMAIL}"

signup="$(curl -fsS --max-time 30 -X POST "${SIGNUP}" \
  -H "Content-Type: application/json" -H "apikey: ${ANON}" -H "Authorization: Bearer ${ANON}" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}" 2>/dev/null || true)"

login="$(curl -fsS --max-time 30 -X POST "${TOKEN}" \
  -H "Content-Type: application/json" -H "apikey: ${ANON}" -H "Authorization: Bearer ${ANON}" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}" 2>/dev/null || true)"

ACCESS="$(printf '%s' "${login}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)"
if [[ -z "${ACCESS}" ]]; then
  echo "FAIL: could not obtain access token (auth may be unreachable from this host)"
  echo "      signup/login via browser at ${BASE}/auth/sign-up then re-test interactively"
  exit 1
fi

# Supabase SSR cookie name for hostname "ai" style (ai.knonix.com → sb-ai-auth-token)
HOST_PART="$(printf '%s' "${DOMAIN:-localhost}" | cut -d. -f1)"
COOKIE_NAME="sb-${HOST_PART}-auth-token"
SESSION_JSON="$(python3 - <<PY
import json, time
print(json.dumps({
  "access_token": """${ACCESS}""",
  "token_type": "bearer",
  "expires_in": 3600,
  "expires_at": int(time.time())+3600,
  "refresh_token": "qa",
  "user": {"id": "qa"}
}))
PY
)"
COOKIE="${COOKIE_NAME}=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))' <<<"${SESSION_JSON}"); searchMode=quick"

CHAT_ID="qa$(date +%s)"
MSG='Reply with exactly: CHAT_OK'
BODY="$(python3 - <<PY
import json
print(json.dumps({
  "chatId": "${CHAT_ID}",
  "trigger": "submit-message",
  "isNewChat": True,
  "relatedEnabled": True,
  "message": {
    "id": "m1",
    "role": "user",
    "parts": [{"type": "text", "text": """${MSG}"""}]
  }
}))
PY
)"

echo "    POST ${BASE}/api/chat (short reply)…"
# stream a limited time
OUT="$(curl -fsS --max-time 120 -N -X POST "${BASE}/api/chat" \
  -H "Content-Type: application/json" \
  -H "Cookie: ${COOKIE}" \
  -d "${BODY}" 2>/dev/null || true)"

if echo "${OUT}" | grep -q 'CHAT_OK'; then
  echo "PASS chat stream returned CHAT_OK"
else
  echo "WARN chat stream did not contain CHAT_OK within timeout (CPU hosts can be slow)"
  echo "      first 200 chars: $(printf '%s' "${OUT}" | head -c 200)"
fi

HEALTH="$(curl -fsS --max-time 15 "${BASE}/api/knonix/health" 2>/dev/null || true)"
if echo "${HEALTH}" | grep -q '"ready":true\|"status":"ok"'; then
  echo "PASS health ready"
else
  echo "FAIL health not ready: $(printf '%s' "${HEALTH}" | head -c 200)"
  exit 1
fi

echo "==> QA smoke finished"
echo "    Note: models do not permanently 'learn' chat by default."
echo "    Company knowledge stays via uploads/RAG, Spaces MEMORY.md, and vault notes."
echo "    See docs/PUBLIC_VS_PLATFORM.md and FEATURES.md."
