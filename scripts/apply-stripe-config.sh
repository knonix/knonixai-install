#!/usr/bin/env bash
# Apply Stripe billing config from .env and restart the License Service.
# Prerequisites: STRIPE_SECRET_KEY and KNONIX_SEAT_PRICE_ID in .env.
# After first run, register webhook in Stripe dashboard (see script output).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source <(grep -E '^(STRIPE_SECRET_KEY|KNONIX_SEAT_PRICE_ID|STRIPE_WEBHOOK_SECRET|KNONIX_LICENSE_SERVICE_URL)=' .env 2>/dev/null | sed 's/^/export /' || true)

if [[ -z "${STRIPE_SECRET_KEY:-}" ]]; then
  echo "Add to .env:" >&2
  echo "  STRIPE_SECRET_KEY=sk_live_...   # or sk_test_... for staging" >&2
  echo "  KNONIX_SEAT_PRICE_ID=price_..." >&2
  echo "  STRIPE_WEBHOOK_SECRET=whsec_... # after creating webhook in Stripe" >&2
  exit 1
fi

if [[ -z "${KNONIX_SEAT_PRICE_ID:-}" ]]; then
  echo "KNONIX_SEAT_PRICE_ID is required in .env" >&2
  exit 1
fi

echo "==> Restarting license-service with Stripe config"
sudo docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d license-service

sleep 3
if sudo docker logs knonixai-license-service-1 --tail 5 2>&1 | grep -q 'listening on :8787'; then
  echo "  OK  license-service started"
else
  sudo docker logs knonixai-license-service-1 --tail 20
  exit 1
fi

BASE="${KNONIX_LICENSE_SERVICE_URL:-https://ai.knonix.com}"
cat <<EOF

==> Stripe webhook setup (one-time, in Stripe Dashboard)
  Endpoint URL: ${BASE}/v1/webhook
  Events:
    - customer.subscription.created
    - customer.subscription.updated
    - customer.subscription.deleted
    - invoice.payment_failed
  Then add STRIPE_WEBHOOK_SECRET=whsec_... to .env and re-run this script.

==> Provision customers:
  Open https://ai.knonix.com/admin/fleet → "Provision customer"
  (creates license key + Stripe subscription for billed tier)

EOF