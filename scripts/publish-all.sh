#!/usr/bin/env bash
# Publish installer git + GHCR app image (needs a real PAT).
#
#   export GITHUB_TOKEN=ghp_…   # classic: repo + write:packages + read:packages
#   export GHCR_USER=knonix     # GitHub username
#   ./scripts/publish-all.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: Set GITHUB_TOKEN (repo + write:packages)." >&2
  echo "  export GITHUB_TOKEN=ghp_…" >&2
  echo "  export GHCR_USER=knonix" >&2
  exit 1
fi
GHCR_USER="${GHCR_USER:-knonix}"
IMAGE="${IMAGE:-ghcr.io/knonix/knonixai}"
VER="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 1.6.1)"

echo "==> docker login ghcr.io as ${GHCR_USER}"
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin

echo "==> Build release image (bake entrypoint + health patch)"
export PUSH=false
bash scripts/release.sh "${VER}"

echo "==> Tag and push ${IMAGE}:v${VER} :latest :installer-${VER}"
docker tag "${IMAGE}:v${VER}" "${IMAGE}:latest" 2>/dev/null || true
docker push "${IMAGE}:v${VER}"
docker push "${IMAGE}:latest"
docker push "${IMAGE}:installer-${VER}" || true

echo "==> git push origin main"
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" main

if ! git rev-parse "v${VER}" >/dev/null 2>&1; then
  git tag -a "v${VER}" -m "KnonixAI installer v${VER}" || true
fi
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" "v${VER}" || true

echo "==> Published."
echo "    Image: ${IMAGE}:latest (v${VER})"
echo "    Repo:  https://github.com/knonix/knonixai-install"
echo "Customers: git pull && docker compose pull && docker compose up -d"
