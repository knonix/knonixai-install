#!/usr/bin/env bash
# Provision a customer license record in the central License Service (Knonix-internal).
# Run on the platform host (ai.knonix.com) from knonixai-install/.
#
# Usage:
#   ./scripts/provision-customer-license.sh --account acme-corp
#   ./scripts/provision-customer-license.sh --account acme-corp --status active \
#       --stripe-customer cus_XXX --stripe-subscription sub_XXX
#
# Prints KNONIX_LICENSE_KEY and a ready-to-paste customer .env block.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing .env in $ROOT" >&2
  exit 1
fi

# shellcheck disable=SC1091
source <(grep -E '^(POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_DB|KNONIX_LICENSE_SERVICE_URL|KNONIX_LICENSE_SERVICE_TOKEN)=' .env | sed 's/^/export /')

ACCOUNT=""
STATUS="free"
FREE_SEATS="${KNONIX_FREE_SEATS:-1}"
STRIPE_CUSTOMER=""
STRIPE_SUB=""
STRIPE_ITEM=""
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account) ACCOUNT="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --free-seats) FREE_SEATS="$2"; shift 2 ;;
    --stripe-customer) STRIPE_CUSTOMER="$2"; shift 2 ;;
    --stripe-subscription) STRIPE_SUB="$2"; shift 2 ;;
    --stripe-subscription-item) STRIPE_ITEM="$2"; shift 2 ;;
    --dry-run) DRY_RUN="--dry-run"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ACCOUNT" ]]; then
  echo "--account is required (e.g. acme-corp)" >&2
  exit 1
fi

PG_USER="${POSTGRES_USER:-knonixai}"
PG_PASS="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing from .env}"
PG_DB="${POSTGRES_DB:-knonixai}"
DB_URL="postgresql://${PG_USER}:${PG_PASS}@postgres:5432/${PG_DB}"

ARGS=(--account "$ACCOUNT" --status "$STATUS" --free-seats "$FREE_SEATS")
[[ -n "$STRIPE_CUSTOMER" ]] && ARGS+=(--stripe-customer "$STRIPE_CUSTOMER")
[[ -n "$STRIPE_SUB" ]] && ARGS+=(--stripe-subscription "$STRIPE_SUB")
[[ -n "$STRIPE_ITEM" ]] && ARGS+=(--stripe-subscription-item "$STRIPE_ITEM")
[[ -n "$DRY_RUN" ]] && ARGS+=("$DRY_RUN")

echo "==> Provisioning license for account: $ACCOUNT (status=$STATUS)"
OUTPUT=$(sudo docker run --rm --network knonixai_default \
  -e KNONIX_LICENSE_DATABASE_URL="$DB_URL" \
  -e KNONIX_LICENSE_DATABASE_SSL_DISABLED=true \
  knonix/license-service:local \
  bun run services/license-service/src/seed-license.ts "${ARGS[@]}")

echo "$OUTPUT"

LICENSE_KEY=$(echo "$OUTPUT" | sed -n 's/^KNONIX_LICENSE_KEY=//p')
if [[ -z "$LICENSE_KEY" ]]; then
  exit 0
fi

SERVICE_URL="${KNONIX_LICENSE_SERVICE_URL:-https://ai.knonix.com}"
SERVICE_TOKEN="${KNONIX_LICENSE_SERVICE_TOKEN:-}"

cat <<EOF

# --- Paste into customer .env (connected mode) ---
KNONIX_LICENSE_MODE=connected
KNONIX_LICENSE_KEY=${LICENSE_KEY}
KNONIX_LICENSE_SERVICE_URL=${SERVICE_URL}
KNONIX_LICENSE_SERVICE_TOKEN=${SERVICE_TOKEN}

# Customer should also run heartbeat-cron (included in knonixai-install docker-compose)
# or schedule: curl -X POST https://<their-host>/api/knonix/heartbeat \\
#   -H "Authorization: Bearer <KNONIX_HEARTBEAT_SECRET on their host>"

EOF