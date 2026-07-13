#!/usr/bin/env bash
# Shared hardware profile detection for install.sh / optimize scripts.
# Prints: PROFILE MEM_GB GPU CORES
# Profiles:
#   low    — CPU / ≤20 GB RAM / no usable GPU  → 3B chat, tight context
#   medium — 21–47 GB RAM, no GPU              → 7B chat + optional coder
#   high   — 48+ GB RAM and/or NVIDIA GPU      → 7B/8B tools models, larger ctx
#
# shellcheck disable=SC2034
detect_hardware_profile() {
  local mem_kb=0 mem_gb=0 cores=1 gpu=0 vram_mb=0 profile

  if [[ -r /proc/meminfo ]]; then
    mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  fi
  mem_gb=$((mem_kb / 1024 / 1024))
  if [[ "${mem_gb}" -lt 1 ]]; then mem_gb=1; fi

  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)"
  [[ "${cores}" -ge 1 ]] || cores=4

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    gpu=1
    vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
      | head -1 | tr -d ' ' || echo 0)"
    [[ -n "${vram_mb}" ]] || vram_mb=0
  fi

  # Low GPU (< 6 GB) is treated like low/medium CPU for model size so layers
  # don't thrash between VRAM and system RAM.
  if [[ "${gpu}" -eq 1 && "${vram_mb}" -ge 12000 ]]; then
    profile=high
  elif [[ "${gpu}" -eq 1 && "${vram_mb}" -ge 6000 ]]; then
    profile=medium
  elif [[ "${mem_gb}" -ge 48 ]]; then
    profile=high
  elif [[ "${mem_gb}" -ge 21 ]]; then
    profile=medium
  else
    profile=low
  fi

  printf '%s %s %s %s %s\n' "${profile}" "${mem_gb}" "${gpu}" "${cores}" "${vram_mb}"
}

# Apply profile defaults into .env via set_env_if_absent if defined, else set_env.
# Caller must define set_env_if_absent and/or set_env.
apply_hardware_profile_env() {
  local profile="${1:-low}"
  local cores="${2:-4}"
  local set_fn="set_env_if_absent"
  if ! declare -F set_env_if_absent >/dev/null 2>&1; then
    if declare -F set_env >/dev/null 2>&1; then
      set_fn="set_env"
    else
      echo "apply_hardware_profile_env: set_env_if_absent not defined" >&2
      return 1
    fi
  fi

  case "${profile}" in
    high)
      "${set_fn}" KNONIX_MODEL "qwen2.5:7b"
      "${set_fn}" KNONIX_CODING_MODEL "qwen2.5-coder:7b"
      "${set_fn}" OLLAMA_NUM_CTX "4096"
      "${set_fn}" OLLAMA_NUM_PREDICT "1024"
      "${set_fn}" INFERENCE_MAX_OUTPUT_TOKENS "2048"
      "${set_fn}" OLLAMA_KEEP_ALIVE "-1"
      "${set_fn}" OLLAMA_NUM_PARALLEL "1"
      "${set_fn}" OLLAMA_MAX_LOADED_MODELS "2"
      "${set_fn}" OLLAMA_FLASH_ATTENTION "1"
      "${set_fn}" OLLAMA_NUM_THREAD "${cores}"
      ;;
    medium)
      "${set_fn}" KNONIX_MODEL "qwen2.5:7b"
      "${set_fn}" KNONIX_CODING_MODEL "qwen2.5-coder:7b"
      "${set_fn}" OLLAMA_NUM_CTX "2048"
      "${set_fn}" OLLAMA_NUM_PREDICT "512"
      "${set_fn}" INFERENCE_MAX_OUTPUT_TOKENS "1024"
      "${set_fn}" OLLAMA_KEEP_ALIVE "-1"
      "${set_fn}" OLLAMA_NUM_PARALLEL "1"
      "${set_fn}" OLLAMA_MAX_LOADED_MODELS "1"
      "${set_fn}" OLLAMA_FLASH_ATTENTION "1"
      "${set_fn}" OLLAMA_NUM_THREAD "${cores}"
      ;;
    *)
      # low — interactive on 8–16 GB CPU / small VMs
      "${set_fn}" KNONIX_MODEL "qwen2.5:3b"
      # Same model for coding on low RAM: second 7B model thrash kills speed.
      "${set_fn}" KNONIX_CODING_MODEL "qwen2.5:3b"
      "${set_fn}" OLLAMA_NUM_CTX "1536"
      "${set_fn}" OLLAMA_NUM_PREDICT "256"
      "${set_fn}" INFERENCE_MAX_OUTPUT_TOKENS "512"
      "${set_fn}" OLLAMA_KEEP_ALIVE "-1"
      "${set_fn}" OLLAMA_NUM_PARALLEL "1"
      "${set_fn}" OLLAMA_MAX_LOADED_MODELS "1"
      "${set_fn}" OLLAMA_FLASH_ATTENTION "1"
      "${set_fn}" OLLAMA_NUM_THREAD "${cores}"
      ;;
  esac
}

profile_description() {
  case "${1:-low}" in
    high)   echo "high (GPU or 48+ GB RAM) — 7B tools models, larger context" ;;
    medium) echo "medium (21–47 GB RAM) — 7B chat, one model loaded" ;;
    *)      echo "low (CPU / ≤20 GB RAM / small GPU) — 3B chat for interactive speed" ;;
  esac
}
