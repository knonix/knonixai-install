#!/usr/bin/env bash
# Generate self-signed Postgres TLS certs for in-cluster SSL (audit P1-4).
# Usage:
#   ./scripts/gen-db-tls.sh
#   # then:
#   POSTGRES_SSL=true DATABASE_SSL_DISABLED=false DATABASE_SSL_QUERY='?sslmode=require' \
#     docker compose up -d postgres
# Or: ./scripts/enable-db-tls.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${ROOT}/secrets/postgres-ssl"
mkdir -p "$DIR"
chmod 700 "${ROOT}/secrets" 2>/dev/null || true

if [[ -f "${DIR}/server.crt" && -f "${DIR}/server.key" ]]; then
  echo "==> Certs already exist in ${DIR}"
  exit 0
fi

openssl req -new -x509 -days 825 -nodes \
  -subj "/CN=postgres/O=KnonixAI/C=US" \
  -addext "subjectAltName=DNS:postgres,DNS:localhost,IP:127.0.0.1" \
  -keyout "${DIR}/server.key" \
  -out "${DIR}/server.crt"
chmod 600 "${DIR}/server.key"
chmod 644 "${DIR}/server.crt"
echo "==> Wrote ${DIR}/server.crt and server.key"
echo "    Enable with: ./scripts/enable-db-tls.sh"
