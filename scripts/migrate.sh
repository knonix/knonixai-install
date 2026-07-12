#!/usr/bin/env bash
#
# migrate.sh — Backup and restore a full KnonixAI install for machine migration.
#
# Moves:
#   - Install directory config (.env, secrets/, compose, Caddyfile, …)
#   - Docker named volumes (Postgres, Ollama models, Caddy certs, workspaces, …)
#
# Usage (on SOURCE / old host):
#   cd /path/to/knonixai-install
#   ./scripts/migrate.sh export /backup/knonix-migrate
#   ./scripts/migrate.sh export /backup/knonix-migrate --skip-ollama   # smaller
#
# Usage (on TARGET / new host):
#   # 1) Install Docker + compose plugin first
#   # 2) Clone or copy knonixai-install, OR restore config from the export
#   cd /path/to/knonixai-install
#   ./scripts/migrate.sh import /backup/knonix-migrate
#   # 3) Review .env (domain, image tag, OLLAMA_NUM_CTX for more RAM)
#   docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
#   ./scripts/verify-install.sh
#
# Notes:
#   - Compose project name is "knonixai" → volumes are knonixai_<name>
#   - export stops the stack for a consistent Postgres snapshot
#   - Do NOT copy platform secrets (LICENSE_ADMIN_TOKEN / PLATFORM_MODE=cloud)
#     onto a pure customer host — only onto the intended Knonix platform machine
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE_FILE="docker-compose.yml"
PROXY_FILE="docker-compose.proxy.yml"
PROJECT_NAME="knonixai"

# Logical volume names as declared in compose (project prefix added at runtime)
VOLUME_SUFFIXES=(
  postgres_data
  redis_data
  searxng_data
  ollama_data
  knonix_workspaces
  caddy_data
  caddy_config
)

usage() {
  cat <<'EOF'
KnonixAI machine migration

  ./scripts/migrate.sh export <backup-dir> [--skip-ollama] [--keep-running]
  ./scripts/migrate.sh import <backup-dir> [--skip-ollama]
  ./scripts/migrate.sh list-volumes
  ./scripts/migrate.sh help

  export   Stop stack (unless --keep-running), archive config + volumes
  import   Restore config into this directory (if present in backup) + volumes
  list-volumes   Show knonixai Docker volumes and sizes

  --skip-ollama    Omit ollama_data (re-pull models on the new host)
  --keep-running   Do not stop containers during export (riskier for Postgres)

Examples:
  ./scripts/migrate.sh export ~/knonix-backup
  scp -r ~/knonix-backup newhost:/tmp/
  # on new host:
  git clone https://github.com/knonix/knonixai-install.git && cd knonixai-install
  ./scripts/migrate.sh import /tmp/knonix-backup
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
EOF
}

# Prefer docker; fall back to sudo docker
DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "ERROR: cannot talk to Docker. Install Docker or add your user to the docker group." >&2
    exit 1
  fi
fi

compose() {
  # shellcheck disable=SC2068
  "${DOCKER[@]}" compose "$@"
}

compose_files_args() {
  local args=(-f "$COMPOSE_FILE")
  if [[ -f "$PROXY_FILE" ]] && grep -qE '^[[:space:]]*KNONIX_DOMAIN=.' .env 2>/dev/null; then
    local domain
    domain="$(grep -E '^[[:space:]]*KNONIX_DOMAIN=' .env | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
    if [[ -n "$domain" ]]; then
      args+=(-f "$PROXY_FILE")
    fi
  elif [[ -f "$PROXY_FILE" ]]; then
    # Prefer proxy if both files exist and domain might be set elsewhere
    if [[ -n "${KNONIX_DOMAIN:-}" ]]; then
      args+=(-f "$PROXY_FILE")
    fi
  fi
  printf '%s\n' "${args[@]}"
}

volume_full_name() {
  local suffix="$1"
  echo "${PROJECT_NAME}_${suffix}"
}

volume_exists() {
  local name="$1"
  "${DOCKER[@]}" volume inspect "$name" >/dev/null 2>&1
}

cmd_list_volumes() {
  echo "==> Docker volumes matching ${PROJECT_NAME}_*"
  "${DOCKER[@]}" volume ls --filter "name=${PROJECT_NAME}_" || true
  echo
  for s in "${VOLUME_SUFFIXES[@]}"; do
    local full
    full="$(volume_full_name "$s")"
    if volume_exists "$full"; then
      local sz
      sz="$("${DOCKER[@]}" run --rm -v "${full}:/v:ro" alpine du -sh /v 2>/dev/null | awk '{print $1}' || echo '?')"
      echo "  $full  $sz"
    else
      echo "  $full  (missing)"
    fi
  done
}

stop_stack() {
  echo "==> Stopping KnonixAI stack for consistent backup"
  local files=()
  mapfile -t files < <(compose_files_args)
  # Always try with proxy overlay if present (covers domain mode)
  if [[ -f "$PROXY_FILE" ]]; then
    compose -f "$COMPOSE_FILE" -f "$PROXY_FILE" down 2>/dev/null || true
  fi
  compose -f "$COMPOSE_FILE" down 2>/dev/null || true
  echo "    Stack stopped (volumes preserved)."
}

export_config() {
  local dest="$1"
  mkdir -p "$dest/config"
  echo "==> Archiving install config → $dest/config/install-config.tgz"
  # Include secrets and .env; exclude git history and local backup dirs
  tar czf "$dest/config/install-config.tgz" \
    --exclude='.git' \
    --exclude='*.tgz' \
    --exclude='knonix-backup*' \
    -C "$(dirname "$ROOT")" \
    "$(basename "$ROOT")"
  # Manifest
  {
    echo "exported_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hostname=$(hostname 2>/dev/null || true)"
    echo "project=${PROJECT_NAME}"
    echo "install_path=${ROOT}"
    if [[ -f .env ]]; then
      echo "domain=$(grep -E '^[[:space:]]*KNONIX_DOMAIN=' .env | tail -1 | cut -d= -f2- | tr -d '"' || true)"
      echo "image_tag=$(grep -E '^[[:space:]]*KNONIX_IMAGE_TAG=' .env | tail -1 | cut -d= -f2- | tr -d '"' || true)"
      echo "platform_mode=$(grep -E '^[[:space:]]*KNONIX_PLATFORM_MODE=' .env | tail -1 | cut -d= -f2- | tr -d '"' || true)"
    fi
  } >"$dest/MANIFEST.txt"
  echo "    Wrote MANIFEST.txt"
}

export_volume() {
  local suffix="$1"
  local dest_dir="$2"
  local full
  full="$(volume_full_name "$suffix")"
  if ! volume_exists "$full"; then
    echo "    SKIP $full (volume does not exist)"
    return 0
  fi
  echo "    Exporting $full …"
  "${DOCKER[@]}" run --rm \
    -v "${full}:/from:ro" \
    -v "${dest_dir}:/to" \
    alpine \
    tar czf "/to/${full}.tgz" -C /from .
  local sz
  sz="$(du -h "${dest_dir}/${full}.tgz" | awk '{print $1}')"
  echo "      → ${full}.tgz ($sz)"
}

cmd_export() {
  local dest="${1:-}"
  shift || true
  local skip_ollama=0
  local keep_running=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-ollama) skip_ollama=1 ;;
      --keep-running) keep_running=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ -z "$dest" ]]; then
    echo "ERROR: export requires a backup directory path." >&2
    usage
    exit 1
  fi

  dest="$(mkdir -p "$dest" && cd "$dest" && pwd)"
  mkdir -p "$dest/volumes"

  echo "==> KnonixAI export"
  echo "    Install: $ROOT"
  echo "    Backup:  $dest"
  echo

  if [[ "$keep_running" -eq 0 ]]; then
    stop_stack
  else
    echo "==> WARNING: --keep-running set; Postgres may be inconsistent under load."
  fi

  export_config "$dest"

  echo "==> Exporting Docker volumes"
  for s in "${VOLUME_SUFFIXES[@]}"; do
    if [[ "$skip_ollama" -eq 1 && "$s" == "ollama_data" ]]; then
      echo "    SKIP ollama_data (--skip-ollama)"
      continue
    fi
    # caddy volumes may not exist if never used proxy mode
    if [[ "$s" == caddy_* ]] && ! volume_exists "$(volume_full_name "$s")"; then
      echo "    SKIP $(volume_full_name "$s") (not present)"
      continue
    fi
    export_volume "$s" "$dest/volumes"
  done

  if [[ "$skip_ollama" -eq 1 ]]; then
    echo "skip_ollama=1" >>"$dest/MANIFEST.txt"
  fi

  # Single tarball convenience (optional large file)
  echo "==> Creating bundle archive"
  local bundle="${dest}/knonix-migrate-bundle.tgz"
  tar czf "$bundle" -C "$dest" MANIFEST.txt config volumes
  echo "    Bundle: $bundle ($(du -h "$bundle" | awk '{print $1}'))"
  echo
  echo "==> Export complete."
  echo
  echo "    Copy to the new machine, for example:"
  echo "      rsync -avP $dest/ user@NEW_HOST:/tmp/knonix-migrate/"
  echo
  echo "    On the new machine:"
  echo "      git clone https://github.com/knonix/knonixai-install.git"
  echo "      cd knonixai-install"
  echo "      ./scripts/migrate.sh import /tmp/knonix-migrate"
  echo "      # review .env — raise OLLAMA_NUM_CTX on larger hosts"
  echo "      docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d"
  echo "      ./scripts/verify-install.sh"
  echo
  if [[ "$keep_running" -eq 0 ]]; then
    echo "    To start this (old) host again:"
    if [[ -f "$PROXY_FILE" ]]; then
      echo "      docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d"
    else
      echo "      docker compose -f docker-compose.yml up -d"
    fi
  fi
}

import_config() {
  local src="$1"
  local tgz="$src/config/install-config.tgz"
  if [[ ! -f "$tgz" ]]; then
    echo "==> No install-config.tgz in backup — keeping current directory files."
    echo "    Ensure .env and secrets/ are present in $ROOT"
    return 0
  fi
  echo "==> Restoring install config from backup (overwrites matching files in parent of install dir)"
  # Extract to a temp dir, then copy into ROOT carefully
  local tmp
  tmp="$(mktemp -d)"
  tar xzf "$tgz" -C "$tmp"
  # tarball contains a single top-level dir (basename of original install)
  local top
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [[ -z "$top" ]]; then
    echo "ERROR: could not find install root inside install-config.tgz" >&2
    rm -rf "$tmp"
    exit 1
  fi
  # Preserve existing .env if user set IMPORT_KEEP_ENV=1
  if [[ "${IMPORT_KEEP_ENV:-}" == "1" && -f "$ROOT/.env" ]]; then
    cp -a "$ROOT/.env" "$ROOT/.env.pre-import"
    echo "    Saved current .env → .env.pre-import"
  fi
  # Copy contents into ROOT
  shopt -s dotglob
  cp -a "$top"/* "$ROOT"/
  shopt -u dotglob
  rm -rf "$tmp"
  echo "    Config restored into $ROOT"
  if [[ -f "$ROOT/.env" ]]; then
    echo "    Review .env before starting (domain, image tag, PLATFORM_* flags)."
  fi
}

import_volume() {
  local archive="$1"
  local full_name
  full_name="$(basename "$archive" .tgz)"
  if [[ ! -f "$archive" ]]; then
    echo "    SKIP missing $archive"
    return 0
  fi
  echo "    Restoring $full_name …"
  if volume_exists "$full_name"; then
    echo "      Volume exists — data will be merged/overwritten into existing volume."
  else
    "${DOCKER[@]}" volume create "$full_name" >/dev/null
  fi
  # Clear and restore for a clean replace
  "${DOCKER[@]}" run --rm \
    -v "${full_name}:/to" \
    -v "$(dirname "$archive"):/from:ro" \
    alpine \
    sh -c "rm -rf /to/* /to/.[!.]* /to/..?* 2>/dev/null; tar xzf /from/$(basename "$archive") -C /to"
  echo "      OK $full_name"
}

cmd_import() {
  local src="${1:-}"
  shift || true
  local skip_ollama=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-ollama) skip_ollama=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ -z "$src" || ! -d "$src" ]]; then
    echo "ERROR: import requires an existing backup directory." >&2
    usage
    exit 1
  fi
  src="$(cd "$src" && pwd)"

  # Accept either unpacked dir or nested after extracting knonix-migrate-bundle.tgz
  if [[ ! -d "$src/volumes" && -f "$src/knonix-migrate-bundle.tgz" ]]; then
    echo "==> Extracting knonix-migrate-bundle.tgz"
    tar xzf "$src/knonix-migrate-bundle.tgz" -C "$src"
  fi
  if [[ ! -d "$src/volumes" ]]; then
    echo "ERROR: $src/volumes not found. Point import at the export directory." >&2
    exit 1
  fi

  echo "==> KnonixAI import"
  echo "    Backup:  $src"
  echo "    Install: $ROOT"
  if [[ -f "$src/MANIFEST.txt" ]]; then
    echo "    Manifest:"
    sed 's/^/      /' "$src/MANIFEST.txt"
  fi
  echo

  # Refuse to clobber a running stack
  if compose -f "$COMPOSE_FILE" ps -q 2>/dev/null | grep -q .; then
    echo "==> Stopping running stack before import"
    if [[ -f "$PROXY_FILE" ]]; then
      compose -f "$COMPOSE_FILE" -f "$PROXY_FILE" down 2>/dev/null || true
    fi
    compose -f "$COMPOSE_FILE" down 2>/dev/null || true
  fi

  import_config "$src"

  echo "==> Restoring Docker volumes"
  shopt -s nullglob
  local archives=("$src"/volumes/*.tgz)
  shopt -u nullglob
  if [[ ${#archives[@]} -eq 0 ]]; then
    echo "ERROR: no volume archives in $src/volumes" >&2
    exit 1
  fi
  for archive in "${archives[@]}"; do
    local base
    base="$(basename "$archive")"
    if [[ "$skip_ollama" -eq 1 && "$base" == *ollama_data* ]]; then
      echo "    SKIP $base (--skip-ollama)"
      continue
    fi
    import_volume "$archive"
  done

  echo
  echo "==> Import complete."
  echo
  echo "    Next steps:"
  echo "      1. Edit .env if the domain or image tag should change"
  echo "         - Larger host: OLLAMA_NUM_CTX=8192  OLLAMA_NUM_PREDICT=3072"
  echo "         - Customer host: KNONIX_PLATFORM_MODE=sovereign  KNONIX_PLATFORM_OWNER=false"
  echo "         - Platform host only: keep cloud + PLATFORM_OWNER + LICENSE_ADMIN_TOKEN"
  echo "      2. Pull image if needed:"
  echo "           docker pull ghcr.io/knonix/knonixai:\${KNONIX_IMAGE_TAG:-latest}"
  echo "      3. Start:"
  if [[ -f "$PROXY_FILE" ]]; then
    echo "           docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d"
  else
    echo "           docker compose up -d"
  fi
  echo "      4. Verify:"
  echo "           ./scripts/verify-install.sh"
  echo "      5. Point DNS A/AAAA at this machine if the domain moved"
  echo
  echo "    Security: backup contains secrets — delete it when migration is confirmed."
}

# --- main ---
CMD="${1:-help}"
shift || true

case "$CMD" in
  export | backup)
    cmd_export "$@"
    ;;
  import | restore)
    cmd_import "$@"
    ;;
  list-volumes | volumes)
    cmd_list_volumes
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    usage
    exit 1
    ;;
esac
