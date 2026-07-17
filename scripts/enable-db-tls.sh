#!/usr/bin/env bash
# Turn on Postgres SSL for the install (.env + restart postgres).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/gen-db-tls.sh

set_env() {
  local key="$1" val="$2"
  if grep -qE "^[[:space:]]*${key}=" .env 2>/dev/null; then
    sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${val}|" .env && rm -f .env.bak
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

set_env POSTGRES_SSL true
set_env DATABASE_SSL_DISABLED false
set_env DATABASE_SSL_QUERY '?sslmode=require'
# GoTrue also needs sslmode in its URL when SSL is required
if grep -qE '^[[:space:]]*GOTRUE_DB_DATABASE_URL=' .env 2>/dev/null; then
  :
fi
echo "==> .env updated for Postgres TLS"
echo "    Recreate: docker compose up -d --force-recreate postgres knonixai supabase-auth"
