# KnonixAI on macOS & MacBook Pro

KnonixAI is a **Linux/Docker** stack. On Apple hardware it almost always runs as:

1. **Docker Desktop for Mac** (Linux VM under the hood), or  
2. A **Linux guest** (Ubuntu in UTM / Parallels / VMware Fusion) on a MacBook Pro — like this install (`ai.knonix.com` on Ubuntu inside QEMU).

In both cases **Apple Metal is not available to the Ollama container**. Inference is **CPU-only** (unless you attach a real NVIDIA GPU to a bare-metal Linux host).

That is expected. The installer is tuned so Mac and nested VMs stay **interactive**, not “cloud-fast.”

---

## Recommended Mac setups

| Setup | When to use | Notes |
| ----- | ----------- | ----- |
| **Ubuntu / Debian VM on MacBook** (current) | Lab, DMZ, always-on enclave | Give the VM **8 vCPU · 16 GB RAM · 60+ GB disk**; use **low** profile (3B) |
| **Docker Desktop on macOS** | Local dev / demos | Docker → Settings → Resources: **≥ 6 CPUs, 12–16 GB RAM, 60 GB disk** |
| **Native Linux on Apple Silicon** | Advanced | Use `linux/arm64` images; still no NVIDIA unless eGPU/passthrough |
| **Dedicated Linux + NVIDIA** | Production team / CMMC | Best quality; Mac is fine as admin laptop only |

### MacBook Pro resource guide (shared with macOS)

| Mac RAM | VM / Docker RAM | Profile | Default model |
| ------- | --------------- | ------- | ------------- |
| 16 GB | 8–10 GB | **low** | `qwen2.5:3b` |
| 32 GB | 16–20 GB | **low** (safe) or medium if VM ≥21 GB | 3B or 7B |
| 36–64 GB | 24–32 GB | **medium** | `qwen2.5:7b` |
| 96 GB+ | 48+ GB | **high** (only if not thrashing host) | 7B + coder |

**Leave RAM for macOS.** Over-allocating the VM so the Mac swaps makes chat feel frozen.

---

## Install (Docker Desktop on Mac)

```bash
# Install Docker Desktop, then:
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
chmod +x install.sh
./install.sh
```

The installer detects low RAM and virtualization and picks **3B** automatically.

### Optimize anytime

```bash
./scripts/optimize-cpu-speed.sh low     # force 3B + short context (MacBook-safe)
# or auto:
./scripts/optimize-cpu-speed.sh
```

On this Ubuntu-on-Mac host you can also print detection:

```bash
source scripts/hardware-profile.sh
detect_hardware_profile
host_environment_hint
```

---

## What the stack does for Mac / VMs

1. **Profile auto-detect** (`scripts/hardware-profile.sh`)  
   - Nested VMs with &lt; ~28 GB guest RAM → **low** (3B)  
   - Caps **high** profile when there is no GPU inside a VM  
   - Sets `OLLAMA_NUM_THREAD` to **leave 1–2 cores free** for the host OS  

2. **One model loaded** (`OLLAMA_MAX_LOADED_MODELS=1`)  
   Avoid loading both 7B chat and 7B coder on a laptop VM.

3. **Short context on low** (`OLLAMA_NUM_CTX=1536`)  
   Long contexts thrash RAM on 16 GB Macs.

4. **Compose binds** heavy services to loopback; Caddy still publishes 80/443 for your domain.

---

## Performance tips (MacBook)

1. Prefer **Quick** mode for everyday chat; Deep research is heavy.  
2. Do **not** keep `qwen3:8b` / dual 7B models warm on a 16 GB Mac VM.  
3. Close unused browser tabs and heavy Mac apps while generating.  
4. Put Docker / VM disk on **APFS SSD**; avoid external HDD volumes.  
5. Docker Desktop: disable unused features (Kubernetes, etc.) to free RAM.  
6. For best coding UX on Mac, use **Cursor / Claude Code** with local or cloud models; keep KnonixAI for **org Spaces, RAG, and sovereign chat**.

---

## Apple Silicon (M1/M2/M3/M4)

| Path | Architecture |
| ---- | ------------ |
| Docker Desktop (Apple Silicon) | `linux/arm64` containers |
| UTM Ubuntu aarch64 | `linux/arm64` |
| UTM Ubuntu x86_64 (emulated) | Slow — prefer aarch64 guest |

```bash
# Prefer native arch pulls
docker pull --platform linux/arm64 ghcr.io/knonix/knonixai:latest
```

If you only see multi-arch tags, Docker usually picks the right one. Avoid forcing `linux/amd64` on Apple Silicon (Rosetta emulation is slower).

---

## This host (ai.knonix.com)

Detected pattern: **Ubuntu guest under QEMU**, ~**8 vCPU · 15 GB RAM**, no NVIDIA → **low / Mac-hosted VM** profile.

Recommended env (applied by optimize script):

```env
KNONIX_MODEL=qwen2.5:3b
KNONIX_CODING_MODEL=qwen2.5:3b
OLLAMA_NUM_CTX=1536
OLLAMA_NUM_PREDICT=256
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_NUM_PARALLEL=1
OLLAMA_NUM_THREAD=6   # leave ~2 of 8 for host / Docker
```

Re-apply:

```bash
./scripts/optimize-cpu-speed.sh low
```

---

## Security / sovereign note

Running on a personal MacBook is fine for **lab and operator** use. For **CMMC / multi-user production**, prefer a dedicated Linux host or GPU server; keep the Mac as the admin client only.
