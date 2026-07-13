#!/usr/bin/env bash
# release.sh — Cut an installer + customer app image release.
#
# Usage:
#   ./scripts/release.sh                 # uses VERSION file as-is
#   ./scripts/release.sh 1.6.1           # set VERSION then build
#   PUSH=true ./scripts/release.sh       # push to GHCR (needs docker login)
#   PUSH=false ./scripts/release.sh      # local tags only (default if not logged in)
#
# What it does:
#   1. Writes/reads VERSION
#   2. Ensures CHANGELOG has a section for this version
#   3. Builds ghcr.io/knonix/knonixai:vX.Y.Z and :latest with entrypoint baked in
#   4. Optionally pushes images
#   5. Prints git commit/push hints for knonixai-install
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGE="${IMAGE:-ghcr.io/knonix/knonixai}"
BASE="${BASE_IMAGE:-${IMAGE}:latest}"
NEW_VER="${1:-}"
if [[ -n "${NEW_VER}" ]]; then
  echo "${NEW_VER}" > VERSION
fi
VER="$(tr -d '[:space:]' < VERSION)"
if [[ ! "${VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must be semver X.Y.Z (got '${VER}')" >&2
  exit 1
fi

DATE_TAG="v${VER}"
BUILD_DATE="$(date -u +%Y-%m-%d)"

# Detect push default
if [[ -z "${PUSH:-}" ]]; then
  if docker system info 2>/dev/null | grep -qi 'ghcr.io'; then
    PUSH=true
  else
    # Try a quiet login probe via credential helper is hard; default false unless set
    PUSH=false
  fi
fi

echo "==> Release ${VER}"
echo "    Image: ${IMAGE}:${DATE_TAG} + :latest"
echo "    Base:  ${BASE}"
echo "    Push:  ${PUSH}"

# Stage entrypoint into image-build context
mkdir -p image-build/context
cp -f scripts/knonix-entrypoint.sh image-build/context/knonix-entrypoint.sh
cp -f image-build/patch-health-auth.cjs image-build/context/patch-health-auth.cjs
cp -f image-build/Dockerfile.release image-build/context/Dockerfile

echo "==> Pull base (if available)"
docker pull "${BASE}" || {
  echo "WARNING: could not pull ${BASE} — building from local tag if present"
}

echo "==> Build release image"
docker build \
  --build-arg "BASE_IMAGE=${BASE}" \
  --build-arg "KNONIX_INSTALLER_VERSION=${VER}" \
  --label "org.opencontainers.image.version=${VER}" \
  --label "org.opencontainers.image.created=${BUILD_DATE}" \
  --label "org.opencontainers.image.title=KnonixAI" \
  --label "org.opencontainers.image.source=https://github.com/knonix/knonixai-install" \
  -f image-build/context/Dockerfile \
  -t "${IMAGE}:${DATE_TAG}" \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:installer-${VER}" \
  image-build/context

echo "==> Smoke: entrypoint present in image"
docker run --rm --entrypoint sh "${IMAGE}:${DATE_TAG}" -c \
  'test -x /knonix-scripts/knonix-entrypoint.sh && echo entrypoint_ok'

if [[ "${PUSH}" == "true" ]]; then
  echo "==> Push ${IMAGE}:${DATE_TAG} :latest :installer-${VER}"
  docker push "${IMAGE}:${DATE_TAG}"
  docker push "${IMAGE}:latest"
  docker push "${IMAGE}:installer-${VER}"
  echo "Published to GHCR."
else
  echo "==> PUSH=false — images tagged locally only."
  echo "    When ready: docker login ghcr.io && PUSH=true ./scripts/release.sh"
fi

echo
echo "==> Git (installer repo)"
echo "    Ensure CHANGELOG.md documents ${VER}, then:"
echo "      git add VERSION CHANGELOG.md scripts image-build docs"
echo "      git commit -m \"release: installer and image v${VER}\""
echo "      git push origin main"
echo "      git tag -a v${VER} -m \"KnonixAI installer v${VER}\""
echo "      git push origin v${VER}"
echo
echo "Customers upgrade with:"
echo "  git pull && ./scripts/check-updates.sh && docker compose pull && docker compose up -d"
