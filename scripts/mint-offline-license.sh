#!/usr/bin/env bash
# Mint an offline (air-gapped) license token for a customer. Knonix-internal only.
# Usage: ./scripts/mint-offline-license.sh --account acme-airgap --seats 25 --days 365
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="$ROOT/secrets/knonix-license-private.pem"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE — run key generation first." >&2
  exit 1
fi

SEATS=""
DAYS="365"
ACCOUNT=""
TIER="enterprise"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seats) SEATS="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --account) ACCOUNT="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --account NAME --seats N [--days 365] [--tier enterprise]"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$SEATS" && -n "$ACCOUNT" ]] || { echo "--account and --seats required" >&2; exit 1; }

PRIV_KEY=$(cat "$KEY_FILE")
sudo docker run --rm \
  -e KNONIX_LICENSE_SIGNING_KEY="$PRIV_KEY" \
  knonix/license-service:local \
  bun run services/license-service/src/mint-offline-license.ts \
    --seats "$SEATS" --tier "$TIER" --days "$DAYS" --account "$ACCOUNT"