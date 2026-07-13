#!/usr/bin/env bash
# Smoke-test the central License Service on this host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source <(grep -E '^(KNONIX_HEARTBEAT_SECRET|KNONIX_LICENSE_ADMIN_TOKEN|KNONIX_LICENSE_KEY|KNONIX_LICENSE_SERVICE_URL)=' .env | sed 's/^/export /')

BASE="${KNONIX_LICENSE_SERVICE_URL:-https://ai.knonix.com}"
HB="${KNONIX_HEARTBEAT_SECRET:?KNONIX_HEARTBEAT_SECRET missing}"
ADMIN="${KNONIX_LICENSE_ADMIN_TOKEN:?KNONIX_LICENSE_ADMIN_TOKEN missing}"
KEY="${KNONIX_LICENSE_KEY:-}"

pass() { echo "  OK  $1"; }
fail() { echo "  FAIL $1"; exit 1; }

echo "==> License stack verification ($BASE)"

curl -fsS "$BASE/healthz" | grep -q '"ok"' && pass "healthz" || fail "healthz"

FLEET=$(curl -fsS "$BASE/v1/licenses" -H "Authorization: Bearer $ADMIN")
echo "$FLEET" | grep -q '"total_licenses"' && pass "fleet API" || fail "fleet API"

if [[ -n "$KEY" ]]; then
  HB_RES=$(curl -fsS -X POST "$BASE/api/knonix/heartbeat" -H "Authorization: Bearer $HB")
  echo "$HB_RES" | grep -q '"ok":true' && pass "install heartbeat trigger" || fail "heartbeat"

  VAL=$(curl -fsS -X POST "$BASE/v1/validate" \
    -H "Authorization: Bearer $HB" \
    -H 'Content-Type: application/json' \
    -d "{\"license_key\":\"$KEY\",\"active_user_count\":1}")
  echo "$VAL" | grep -q '"valid":true' && pass "license validate" || fail "validate"
fi

if grep -q '^STRIPE_SECRET_KEY=.' .env 2>/dev/null; then
  pass "Stripe secret configured"
else
  echo "  WARN Stripe not configured — metering works; billing sync disabled"
fi

echo "==> All checks passed"