#!/usr/bin/env bash
# Back-compat wrapper → scripts/release.sh
# Prefer: ./scripts/release.sh [version]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IMAGE="${IMAGE:-ghcr.io/knonix/knonixai}"
export BASE_IMAGE="${BASE_IMAGE:-${IMAGE}:latest}"
export PUSH="${PUSH:-true}"
exec "$ROOT/scripts/release.sh" "$@"
