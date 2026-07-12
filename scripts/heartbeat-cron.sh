#!/bin/sh
# Daily license heartbeat — reports seat usage to the central License Service.
# Runs inside the heartbeat-cron container; calls the install-side trigger API.
set -eu
SECRET="${KNONIX_HEARTBEAT_SECRET:?KNONIX_HEARTBEAT_SECRET is required}"
URL="${KNONIX_HEARTBEAT_URL:-http://knonixai:3000/api/knonix/heartbeat}"
echo "[heartbeat-cron] $(date -Iseconds) sending heartbeat to ${URL}"
curl -fsS -X POST "${URL}" \
  -H "Authorization: Bearer ${SECRET}" \
  -H 'Content-Type: application/json' \
  -d '{}' \
  && echo "[heartbeat-cron] ok" \
  || echo "[heartbeat-cron] failed (will retry next interval)"