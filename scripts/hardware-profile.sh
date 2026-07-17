#!/usr/bin/env bash
# Shared hardware profile detection for install.sh / optimize scripts.
# Prints: PROFILE MEM_GB GPU CORES VRAM_MB
# Profiles:
#   low    — CPU / ≤20 GB RAM / no usable GPU / most Mac & nested VMs → 3B chat
#   medium — 21–47 GB RAM, no GPU                                  → 7B chat
#   high   — 48+ GB RAM and/or NVIDIA GPU (≥12 GB VRAM)            → 7B/8B tools
#
# Mac / Apple note: Docker Desktop and Linux VMs on MacBook Pro do NOT expose
# Apple Metal/GPU to Ollama. Inference is always CPU (or NVIDIA if you passthrough
# a discrete eGPU, which is rare). Prefer low/medium profiles and leave host
# cores free so macOS stays responsive.
#
# shellcheck disable=SC2034

# Returns 0 if we appear to run inside a VM / containerized Docker Desktop VM.
is_virtualized_host() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local v
    v="$(systemd-detect-virt 2>/dev/null || true)"
    case "${v}" in
      none|"") ;;
      *) return 0 ;;
    esac
  fi
  # Hypervisor flag (common in QEMU/KVM/UTM/Parallels/VMware guests)
  if grep -qE 'hypervisor' /proc/cpuinfo 2>/dev/null; then
    return 0
  fi
  local vendor product
  vendor="$(tr -d '\0' </sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  product="$(tr -d '\0' </sys/class/dmi/id/product_name 2>/dev/null || true)"
  local blob="${vendor,,} ${product,,}"
  case "${blob}" in
    *qemu*|*kvm*|*vmware*|*virtualbox*|*parallels*|*microsoft*|*hyper-v*|*xen*|*bochs*)
      return 0
      ;;
  esac
  return 1
}

# Heuristic: guest is a Linux VM that is likely hosted on Apple Silicon / Mac.
# (x86 Ubuntu under UTM/Parallels/VMware on MacBook is the common Knonix DMZ case.)
is_likely_apple_hosted_vm() {
  is_virtualized_host || return 1
  local vendor product model
  vendor="$(tr -d '\0' </sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  product="$(tr -d '\0' </sys/class/dmi/id/product_name 2>/dev/null || true)"
  model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- || true)"
  # QEMU/Standard PC is the usual UTM/virtio guest on Mac.
  case "${vendor,,}" in
    *qemu*|*parallels*) return 0 ;;
  esac
  case "${product,,}" in
    *standard*pc*|*apple*|*macbook*|*virtual*machine*) return 0 ;;
  esac
  # Emulated "Intel Core Processor (Skylake)" is a common QEMU default on Mac hosts.
  case "${model,,}" in
    *core*processor*skylake*|*qemu*virtual*) return 0 ;;
  esac
  return 1
}

# Leave CPU for the host (macOS UI, browser, Docker Desktop overhead).
effective_inference_threads() {
  local cores="${1:-4}"
  local virt=0
  is_virtualized_host && virt=1
  if [[ "${virt}" -eq 1 ]]; then
    # Keep 25% or at least 1–2 cores free for host + docker.
    local leave=2
    if [[ "${cores}" -le 4 ]]; then leave=1; fi
    local t=$((cores - leave))
    [[ "${t}" -ge 2 ]] || t=2
    [[ "${t}" -le "${cores}" ]] || t="${cores}"
    echo "${t}"
  else
    echo "${cores}"
  fi
}

detect_hardware_profile() {
  local mem_kb=0 mem_gb=0 cores=1 gpu=0 vram_mb=0 profile virt=0

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

  if is_virtualized_host; then virt=1; fi

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

  # Nested VMs / Docker Desktop Linux VMs on laptops (esp. MacBook): never
  # default to high-RAM profiles even if the guest is over-provisioned — host
  # memory is shared with macOS. Cap at medium unless real NVIDIA GPU.
  if [[ "${virt}" -eq 1 && "${gpu}" -eq 0 ]]; then
    if [[ "${mem_gb}" -lt 28 ]]; then
      profile=low
    elif [[ "${profile}" == "high" ]]; then
      profile=medium
    fi
  fi

  # Apple-hosted guests almost never have passthrough GPU; keep interactive.
  if is_likely_apple_hosted_vm && [[ "${gpu}" -eq 0 ]]; then
    if [[ "${mem_gb}" -lt 28 ]]; then
      profile=low
    fi
  fi

  # Threads used for OLLAMA_NUM_THREAD (host headroom when virtualized)
  cores="$(effective_inference_threads "${cores}")"

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

  # Cap threads sensibly even if caller passed raw nproc
  if [[ "${cores}" -gt 12 ]]; then cores=12; fi
  if [[ "${cores}" -lt 2 ]]; then cores=2; fi

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
      # low — interactive on 8–16 GB CPU, MacBook VMs, Docker Desktop
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
    *)      echo "low (CPU / ≤20 GB / Mac & nested VMs) — 3B chat for interactive speed" ;;
  esac
}

host_environment_hint() {
  if is_likely_apple_hosted_vm; then
    echo "apple-hosted-vm (Linux guest on Mac — no Metal GPU for Ollama; CPU low/medium defaults)"
  elif is_virtualized_host; then
    echo "virtualized (leave host CPU free; prefer 3B–7B, one model loaded)"
  else
    echo "bare-metal-or-unknown"
  fi
}
