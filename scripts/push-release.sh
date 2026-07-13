#!/usr/bin/env bash
# push-release.sh — Login to GHCR + push git main + push image tags.
#
# Usage (classic PAT with scopes: repo, write:packages, read:packages):
#   export GITHUB_TOKEN=ghp_...
#   export GHCR_USER=knonix   # GitHub username that owns the package
#   ./scripts/push-release.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: export GITHUB_TOKEN first (classic PAT: repo + write:packages)." >&2
  exit 1
fi
GHCR_USER="${GHCR_USER:-knonix}"
IMAGE="${IMAGE:-ghcr.io/knonix/knonixai}"
VER="$(tr -d '[:space:]' < VERSION)"

echo "==> docker login ghcr.io as ${GHCR_USER}"
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin

echo "==> Ensure release image tags exist (build if missing)"
if ! docker image inspect "${IMAGE}:v${VER}" >/dev/null 2>&1; then
  PUSH=false ./scripts/release.sh
fi

echo "==> Push image tags: v${VER} latest installer-${VER}"
docker push "${IMAGE}:v${VER}"
docker push "${IMAGE}:latest"
docker push "${IMAGE}:installer-${VER}"

echo "==> Push git main (installer)"
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" main

if git rev-parse "v${VER}" >/dev/null 2>&1; then
  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" "v${VER}" || true
else
  git tag -a "v${VER}" -m "KnonixAI installer v${VER}"
  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/knonix/knonixai-install.git" "v${VER}" || true
fi

echo "==> Done."
echo "    Image: ${IMAGE}:latest (v${VER})"
echo "    Repo:  https://github.com/knonix/knonixai-install"
echo "    Customers: docker compose pull && docker compose up -d"
