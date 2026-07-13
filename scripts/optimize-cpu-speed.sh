#!/usr/bin/env bash
# Re-apply low/medium/high inference defaults for the current machine.
# Safe to re-run. Usage:
#   ./scripts/optimize-cpu-speed.sh           # auto profile
#   ./scripts/optimize-cpu-speed.sh low       # force low (3B)
#   ./scripts/optimize-cpu-speed.sh medium    # force medium (7B)
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source "./scripts/hardware-profile.sh"

FORCE_PROFILE="${1:-}"
if [[ -n "${FORCE_PROFILE}" ]]; then
  PROFILE="${FORCE_PROFILE}"
  MEM_GB="$(awk '/MemTotal:/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 16)"
  CORES="$(nproc 2>/dev/null || echo 4)"
  GPU=0
  VRAM=0
else
  read -r PROFILE MEM_GB GPU CORES VRAM < <(detect_hardware_profile)
fi

echo "==> Profile: $(profile_description "${PROFILE}")"
echo "    ${MEM_GB} GB RAM · ${CORES} threads · GPU=${GPU} VRAM≈${VRAM} MB"

# Minimal set_env_if_absent for this script (always rewrite speed knobs when forced).
set_env_if_absent() {
  local key="$1" val="$2"
  if [[ -n "${FORCE_PROFILE}" ]]; then
    if grep -qE "^[[:space:]]*${key}=" .env 2>/dev/null; then
      sed -i "s|^[[:space:]]*${key}=.*|${key}=${val}|" .env
    else
      printf '%s=%s\n' "$key" "$val" >> .env
    fi
    return 0
  fi
  if grep -qE "^[[:space:]]*${key}=" .env 2>/dev/null; then
    # Keep operator overrides unless empty
    local cur
    cur="$(grep -E "^[[:space:]]*${key}=" .env | tail -1 | cut -d= -f2-)"
    [[ -n "${cur}" ]] && return 0
  fi
  if grep -qE "^[[:space:]]*${key}=" .env 2>/dev/null; then
    sed -i "s|^[[:space:]]*${key}=.*|${key}=${val}|" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

# For forced profile, always overwrite speed keys.
if [[ -n "${FORCE_PROFILE}" ]]; then
  set_env() { set_env_if_absent "$@"; }
  apply_hardware_profile_env "${PROFILE}" "${CORES}"
else
  apply_hardware_profile_env "${PROFILE}" "${CORES}"
fi

MODEL="$(grep -E '^[[:space:]]*KNONIX_MODEL=' .env | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
MODEL="${MODEL:-qwen2.5:3b}"

echo "==> Ensuring model ${MODEL}"
docker compose exec -T ollama ollama pull "${MODEL}" || true

echo "==> Stopping models not needed on this profile (free RAM)"
case "${PROFILE}" in
  low)
    for m in qwen3:8b qwen2.5:7b qwen2.5-coder:7b; do
      docker compose exec -T ollama ollama stop "$m" 2>/dev/null || true
    done
    ;;
esac

echo "==> Recreate ollama + knonixai with new env"
if [[ -f docker-compose.proxy.yml ]] && grep -qE '^[[:space:]]*KNONIX_DOMAIN=.+' .env; then
  docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d --force-recreate ollama knonixai
else
  docker compose -f docker-compose.yml up -d --force-recreate ollama knonixai
fi

echo "==> Persist active model"
docker compose exec -T postgres \
  psql -U knonixai -d knonixai \
  -c "UPDATE install_identity SET active_model='${MODEL}', coding_model='${MODEL}';" \
  2>/dev/null || true

echo "==> Warm ${MODEL}"
sleep 4
curl -fsS --max-time 300 http://127.0.0.1:11434/api/generate \
  -d "{\"model\":\"${MODEL}\",\"prompt\":\"ready\",\"stream\":false,\"keep_alive\":-1,\"options\":{\"num_predict\":2,\"num_ctx\":512}}" \
  >/dev/null && echo "    Warm OK" || echo "    Warm skipped/failed"

echo "==> Done. Chat should stream in Quick mode. Profile=${PROFILE} model=${MODEL}"
