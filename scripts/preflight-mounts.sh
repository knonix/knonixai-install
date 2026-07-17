#!/usr/bin/env bash
# preflight-mounts.sh — Fail fast if compose bind-mount sources are missing.
# Missing sources become empty directories under Docker and break SearXNG / heartbeat.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
need_files=(
  "searxng/settings.yml"
  "scripts/heartbeat-cron.sh"
  "scripts/knonix-entrypoint.sh"
  "init-auth-db.sql"
  "init-rag-db.sql"
  "kong.yml"
)

echo "==> Preflight: required bind-mount sources"
for f in "${need_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL  missing file: $f"
    fail=1
  elif [[ -d "$f" ]]; then
    echo "FAIL  path is a directory (bad bind-mount): $f"
    fail=1
  else
    echo "OK    $f"
  fi
done

# Detect Docker-created empty dirs that clobbered files previously
for f in searxng/settings.yml scripts/heartbeat-cron.sh; do
  if [[ -d "$f" ]]; then
    echo "FAIL  $f is a directory — remove it and restore the real file from git"
    fail=1
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "==> Preflight FAILED. Fix missing files before docker compose up."
  exit 1
fi
echo "==> Preflight OK"
