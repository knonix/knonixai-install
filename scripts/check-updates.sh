#!/usr/bin/env bash
# check-updates.sh — Tell operators when a newer installer or app image is available.
set -euo pipefail
cd "$(dirname "$0")/.."

REMOTE_REPO="${KNONIX_INSTALL_REPO:-https://raw.githubusercontent.com/knonix/knonixai-install/main}"
IMAGE="${KNONIX_APP_IMAGE:-ghcr.io/knonix/knonixai}"
TAG="${KNONIX_IMAGE_TAG:-latest}"

LOCAL_VER="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "0.0.0")"
echo "==> KnonixAI update check"
echo "    Local installer VERSION: ${LOCAL_VER}"

# --- Installer VERSION from GitHub ---
REMOTE_VER=""
if command -v curl >/dev/null 2>&1; then
  REMOTE_VER="$(curl -fsSL --max-time 12 "${REMOTE_REPO}/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
fi
if [[ -z "${REMOTE_VER}" ]] && command -v wget >/dev/null 2>&1; then
  REMOTE_VER="$(wget -qO- --timeout=12 "${REMOTE_REPO}/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
fi

if [[ -n "${REMOTE_VER}" ]]; then
  echo "    Remote installer VERSION: ${REMOTE_VER}"
  if [[ "${REMOTE_VER}" != "${LOCAL_VER}" ]]; then
    echo "    → Installer update available: ${LOCAL_VER} → ${REMOTE_VER}"
    echo "      git pull origin main"
    echo "      See CHANGELOG.md for what changed."
    INSTALLER_UPDATE=1
  else
    echo "    → Installer is up to date."
    INSTALLER_UPDATE=0
  fi
else
  echo "    (Could not fetch remote VERSION — offline or repo not public yet.)"
  INSTALLER_UPDATE=0
fi

# --- App image: compare local digest to registry ---
echo
echo "    App image: ${IMAGE}:${TAG}"
LOCAL_DIGEST=""
REMOTE_DIGEST=""
if docker image inspect "${IMAGE}:${TAG}" >/dev/null 2>&1; then
  LOCAL_DIGEST="$(docker image inspect "${IMAGE}:${TAG}" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  echo "    Local:  ${LOCAL_DIGEST:-present (no repo digest)}"
else
  echo "    Local:  not present on this host"
fi

if docker manifest inspect "${IMAGE}:${TAG}" >/dev/null 2>&1; then
  # Best-effort remote digest
  REMOTE_DIGEST="$(docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{json .Manifest}}' 2>/dev/null | head -c 200 || true)"
  echo "    Remote: registry reachable for ${IMAGE}:${TAG}"
  # Pull only metadata via create --dry-run isn't available; recommend pull check
  IMAGE_UPDATE=0
  if [[ -n "${LOCAL_DIGEST}" ]]; then
    # Try to re-pull and compare Id
    BEFORE_ID="$(docker image inspect "${IMAGE}:${TAG}" --format '{{.Id}}' 2>/dev/null || true)"
    if docker pull "${IMAGE}:${TAG}" >/dev/null 2>&1; then
      AFTER_ID="$(docker image inspect "${IMAGE}:${TAG}" --format '{{.Id}}' 2>/dev/null || true)"
      if [[ -n "${BEFORE_ID}" && -n "${AFTER_ID}" && "${BEFORE_ID}" != "${AFTER_ID}" ]]; then
        echo "    → App image updated from registry (new layers pulled)."
        IMAGE_UPDATE=1
      else
        echo "    → App image matches registry (or already latest)."
      fi
    else
      echo "    (docker pull failed — login may be required for private packages, or offline.)"
    fi
  else
    echo "    → Run: docker pull ${IMAGE}:${TAG}"
    IMAGE_UPDATE=1
  fi
else
  echo "    (Could not inspect remote manifest — may need: docker login ghcr.io)"
  IMAGE_UPDATE=0
fi

echo
if [[ "${INSTALLER_UPDATE:-0}" -eq 1 || "${IMAGE_UPDATE:-0}" -eq 1 ]]; then
  echo "==> Action recommended"
  echo "    1. git pull origin main"
  echo "    2. docker compose pull"
  echo "    3. docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile auth up -d"
  echo "    4. Hard-refresh the browser"
  echo "    Changelog: CHANGELOG.md"
  exit 2
fi

echo "==> No updates required"
exit 0
