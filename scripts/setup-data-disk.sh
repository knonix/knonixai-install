#!/usr/bin/env bash
# Point Docker + containerd persistent storage at the Azure data disk.
#
# KnonixAI installs use a separate 30 GB volume at /mnt/knonix-data so images,
# models (Ollama), Postgres, and layer snapshots do not fill the 29 GB OS disk.
#
# Safe to re-run (idempotent). Requires sudo.
#
# Usage (from knonixai-install/):
#   sudo ./scripts/setup-data-disk.sh
#   sudo ./scripts/setup-data-disk.sh --prune-build-cache
set -euo pipefail

PRUNE_CACHE=false
for arg in "$@"; do
  case "$arg" in
    --prune-build-cache) PRUNE_CACHE=true ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

DATA_MOUNT=/mnt/knonix-data
DOCKER_ROOT="${DATA_MOUNT}/docker"
CONTAINERD_ROOT="${DATA_MOUNT}/containerd"
DAEMON_JSON=/etc/docker/daemon.json
CONTAINERD_CFG=/etc/containerd/config.toml

if ! mountpoint -q "$DATA_MOUNT"; then
  echo "ERROR: ${DATA_MOUNT} is not mounted. Attach/mount the data disk first." >&2
  echo "Expected fstab entry, e.g.:" >&2
  echo "  UUID=... ${DATA_MOUNT} ext4 defaults,nofail,discard 0 2" >&2
  exit 1
fi

echo "==> Data disk: $(df -h "$DATA_MOUNT" | tail -1)"

mkdir -p "$DOCKER_ROOT" "$CONTAINERD_ROOT"

# --- Docker data-root -------------------------------------------------------
need_docker_restart=false
if [[ ! -f "$DAEMON_JSON" ]] || ! grep -q "\"data-root\": \"${DOCKER_ROOT}\"" "$DAEMON_JSON" 2>/dev/null; then
  echo "==> Configuring Docker data-root → ${DOCKER_ROOT}"
  mkdir -p /etc/docker
  if [[ -f "$DAEMON_JSON" ]]; then
    # Merge if other keys exist; simplest path for our installs:
    printf '%s\n' '{' "  \"data-root\": \"${DOCKER_ROOT}\"" '}' >"$DAEMON_JSON"
  else
    printf '%s\n' '{' "  \"data-root\": \"${DOCKER_ROOT}\"" '}' >"$DAEMON_JSON"
  fi
  need_docker_restart=true
else
  echo "==> Docker data-root already ${DOCKER_ROOT}"
fi

# --- containerd root (layer snapshots — this is what fills the OS disk) -----
need_containerd_migrate=false
current_containerd_root=/var/lib/containerd
if grep -qE '^root = "/mnt/knonix-data/containerd"' "$CONTAINERD_CFG" 2>/dev/null; then
  echo "==> containerd root already ${CONTAINERD_ROOT}"
elif [[ -d "$current_containerd_root" ]] && [[ "$(sudo du -s "$current_containerd_root" 2>/dev/null | awk '{print $1}')" -gt 1024 ]]; then
  need_containerd_migrate=true
else
  echo "==> Setting containerd root → ${CONTAINERD_ROOT}"
  if grep -qE '^#?root = ' "$CONTAINERD_CFG"; then
    sed -i "s|^#\\?root = .*|root = \"${CONTAINERD_ROOT}\"|" "$CONTAINERD_CFG"
  else
    printf '\nroot = "%s"\n' "$CONTAINERD_ROOT" >>"$CONTAINERD_CFG"
  fi
  need_containerd_migrate=true
fi

if $need_containerd_migrate; then
  echo "==> Stopping Docker + containerd for storage migration (brief downtime)"
  systemctl stop docker docker.socket 2>/dev/null || true
  systemctl stop containerd 2>/dev/null || true

  free_mb=$(df -m "$DATA_MOUNT" | tail -1 | awk '{print $4}')
  containerd_mb=$(du -sm "${current_containerd_root}" 2>/dev/null | awk '{print $1}')
  if [[ "${free_mb:-0}" -lt $((containerd_mb + 512)) ]]; then
    echo "WARN: Data disk has ~${free_mb}MB free but containerd is ~${containerd_mb}MB." >&2
    echo "      Moving containerd fresh (images re-pull; Postgres/Ollama volumes are safe)." >&2
    if [[ ! -d "${current_containerd_root}.bak" ]]; then
      mv "${current_containerd_root}" "${current_containerd_root}.bak"
    fi
    mkdir -p "${CONTAINERD_ROOT}"
  elif [[ ! -f "${CONTAINERD_ROOT}/io.containerd.snapshotter.v1.overlayfs/metadata.db" ]] \
       && [[ -d "${current_containerd_root}/io.containerd.snapshotter.v1.overlayfs" ]]; then
    echo "==> Moving containerd data to ${CONTAINERD_ROOT}"
    if [[ ! -d "${current_containerd_root}.bak" ]]; then
      mv "${current_containerd_root}" "${CONTAINERD_ROOT}"
      mkdir -p "${current_containerd_root}"
    fi
  fi

  if grep -qE '^#?root = ' "$CONTAINERD_CFG"; then
    sed -i "s|^#\\?root = .*|root = \"${CONTAINERD_ROOT}\"|" "$CONTAINERD_CFG"
  else
    printf '\nroot = "%s"\n' "$CONTAINERD_ROOT" >>"$CONTAINERD_CFG"
  fi
  need_docker_restart=true
fi

if $need_docker_restart; then
  echo "==> Starting containerd + Docker"
  systemctl start containerd
  systemctl start docker
  sleep 3
fi

if $PRUNE_CACHE; then
  echo "==> Pruning unused Docker build cache"
  docker builder prune -af >/dev/null 2>&1 || true
fi

echo ""
echo "==> Disk usage after setup"
df -h / "$DATA_MOUNT"
echo ""
docker info 2>/dev/null | grep -E 'Docker Root Dir|Storage Driver' || true
grep -E '^root = ' "$CONTAINERD_CFG" || true
echo ""
echo "Done. Postgres/Ollama volumes live on the data disk via Docker."
echo "After verifying the stack, you may delete ${current_containerd_root}.bak to reclaim OS disk:"
echo "  sudo rm -rf ${current_containerd_root}.bak"