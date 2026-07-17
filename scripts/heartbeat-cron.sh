#!/bin/sh
# Daily license heartbeat — privacy-preserving seat count to Knonix (connected mode only).
# Runs inside the heartbeat-cron container. Non-zero curl failures are logged (not silent).
set -eu

SECRET="${KNONIX_HEARTBEAT_SECRET:-}"
URL="${KNONIX_HEARTBEAT_URL:-http://knonixai:3000/api/knonix/heartbeat}"
# Optional direct central URL (if install triggers via central service instead of local API):
# CENTRAL="${KNONIX_LICENSE_SERVICE_URL:-}"

if [ -z "${SECRET}" ]; then
  echo "[heartbeat-cron] ERROR: KNONIX_HEARTBEAT_SECRET is empty" >&2
  exit 1
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
echo "[heartbeat-cron] ${TS} POST ${URL}"

# --max-time / --connect-timeout: fail fast instead of hanging the cron loop
HTTP_CODE="$(
  curl -sS -o /tmp/hb_body.txt -w '%{http_code}' \
    --connect-timeout 10 \
    --max-time 60 \
    -X POST "${URL}" \
    -H "Authorization: Bearer ${SECRET}" \
    -H 'Content-Type: application/json' \
    -d '{}' \
    || echo "000"
)"

if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "204" ]; then
  echo "[heartbeat-cron] ok http=${HTTP_CODE}"
  exit 0
fi

echo "[heartbeat-cron] FAILED http=${HTTP_CODE} body=$(head -c 200 /tmp/hb_body.txt 2>/dev/null || true)" >&2
exit 1
