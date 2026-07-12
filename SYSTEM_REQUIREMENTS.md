# KnonixAI — System Requirements

Sizing guide for **sovereign self-hosted** installs. Plan capacity for **Docker data**
(the partition where images, models, and database volumes live), not just the OS
root disk.

> **Marketing takeaway:** KnonixAI runs from a small evaluation VM up to GPU
> workstations, **NVIDIA Jetson** edge boxes, and air-gapped racks. **CMMC
> programs** should size for the **Production / team** tier (or Jetson Orin 16
> GB+) so compliance workflows (RAG + multi-model + connectors) stay responsive.

Full CMMC / DFARS positioning: **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)**  
Comparisons: **[COMPARISON.md](./COMPARISON.md)**

---

## Quick pick

| Your goal | Min hardware | Recommended models |
| --------- | ------------ | ------------------ |
| **Demo / single evaluator** | 4 vCPU · 16 GB RAM · 50 GB disk | `qwen3:8b` + embed |
| **Smooth team / CMMC space** | **16 vCPU · 64 GB RAM · 200 GB disk** | `qwen3:8b` + coder + R1 + embed |
| **Fast local “best quality”** | 16+ cores · 64 GB · **24 GB NVIDIA dGPU** · 200 GB+ | Qwen3 14B/32B or R1 32B |
| **Edge / Jetson** | **Orin NX 16 GB+** or **AGX Orin 32/64 GB** · 128 GB+ NVMe | `qwen3:8b` or smaller tools model |
| **Near-frontier open weights** | Multi-GPU 40–80 GB · 128 GB RAM · 500 GB | 70B / MoE class |

---

## Minimum (evaluation / single user)

| Resource             | Minimum                                                              |
| -------------------- | -------------------------------------------------------------------- |
| **CPU**              | 4 vCPU (x86_64 or ARM64)                                             |
| **RAM**              | 16 GB (32 GB strongly preferred for 7B–9B models on CPU)             |
| **Docker data disk** | **50 GB free**                                                       |
| **OS root disk**     | 20 GB                                                                |
| **GPU**              | None required                                                        |
| **Network**          | Outbound HTTPS for image/model pulls; ports 80/443 for public domain |

**Expect:** usable chat on 7B–8B tools models; multi-minute answers on 2–4 vCPU; avoid large multi-model catalogs.

---

## Recommended (production / small team / CMMC program)

| Resource             | Recommended                                                    |
| -------------------- | -------------------------------------------------------------- |
| **CPU**              | **16+ vCPU**                                                   |
| **RAM**              | **64 GB**                                                      |
| **Docker data disk** | **200 GB free** (NVMe preferred)                               |
| **OS root disk**     | 30 GB+                                                         |
| **GPU**              | Optional **NVIDIA 16–24 GB** for snappy 14B–32B inference      |
| **Users**            | ~5–25 concurrent seats depending on model size and concurrency |

**Expect:** smooth Quick/Adaptive/Pro research, CMMC readiness sweeps with RAG + SharePoint, multiple tools-capable models installed.

---

## Performance tier (best local quality)

| Resource   | Target                                                              |
| ---------- | ------------------------------------------------------------------- |
| **CPU**    | 16–32 cores                                                         |
| **RAM**    | 64–128 GB                                                           |
| **GPU**    | **NVIDIA 24 GB+** (RTX 4090 / L4 / A10 class)                       |
| **Disk**   | **300–500 GB NVMe**                                                 |
| **Models** | `qwen3:14b` / `qwen3:32b`, `deepseek-r1:32b`, `gemma3:27b` (vision) |

**Expect:** near–cloud quality for agent loops; still fully sovereign if frontier APIs stay off.

---

## Enterprise / multi-GPU (70B / MoE)

| Resource   | Target                                            |
| ---------- | ------------------------------------------------- |
| **GPU**    | **48–80 GB+** VRAM (A6000, dual 4090, H100-class) |
| **RAM**    | 128 GB+                                           |
| **Disk**   | 500 GB–2 TB                                       |
| **Models** | Llama 3.3 70B, DeepSeek-V3 class, large VL        |

Required for marketing-list “frontier open” weights (not consumer 8B defaults).

---

## NVIDIA Jetson — can it run KnonixAI?

**Yes — with the right Jetson and expectations.** KnonixAI is Docker-based and
supports **ARM64** hosts. Ollama officially documents Jetson Orin family devices
for local LLMs (GPU-accelerated when JetPack + NVIDIA container runtime are set up).

### Jetson fit matrix

| Device | Unified memory | Can run KnonixAI? | Realistic model | Experience |
| ------ | -------------- | ----------------- | --------------- | ---------- |
| **Jetson Orin Nano 8 GB** | 8 GB | **Tight / demo only** | 3B–4B tools model or tiny 7B with low `num_ctx` | Slow if RAM-starved; stack (Postgres+app+Ollama) competes for the same 8 GB |
| **Jetson Orin Nano Super / 8 GB well-tuned** | 8 GB | **Possible** with lean compose | `qwen2.5:3b` / small tools model | Single-user chat; disable unused models |
| **Jetson Orin NX 16 GB** | 16 GB | **Yes (recommended min edge)** | `qwen3:8b` Q4 + embed | Good single-user / light team; NVMe required |
| **Jetson AGX Orin 32 GB** | 32 GB | **Yes — strong edge** | 8B–14B class | Smooth local agents; CMMC draft work |
| **Jetson AGX Orin 64 GB** | 64 GB | **Yes — best Jetson** | 14B–32B quantized | Near workstation quality at the edge |
| **Older Jetson (Xavier, Nano, TX2)** | ≤16 GB often | **Not recommended** for full stack | — | Prefer Orin generation |

### Jetson requirements checklist

| Item | Guidance |
| ---- | -------- |
| **JetPack** | JetPack 6.x (L4T r36) preferred for current Ollama GPU paths |
| **Storage** | **NVMe SSD 128 GB+** (SD card is too slow/small for models + Docker) |
| **Runtime** | `nvidia-container-toolkit` / Jetson container runtime so Ollama uses GPU |
| **Docker images** | Use **linux/arm64** images (`docker pull --platform linux/arm64 …`) |
| **Models** | Prefer **tools-capable** tags (`qwen3:8b`, etc.); avoid loading 5 large models at once |
| **Context** | Start with `OLLAMA_NUM_CTX=4096` on 8–16 GB devices; raise only if free RAM allows |
| **Swap** | Optional zram/swap helps 8 GB boards avoid OOM; GPU still preferred for tokens |

### What works well on Jetson

- Sovereign chat with a **single** 7B–8B tools model  
- RAG with `nomic-embed-text`  
- Light Spaces / CMMC **drafting** (not concurrent heavy Deep research for many users)  
- Air-gapped field kits and SCIF-adjacent edge demos  

### What does **not** fit Jetson well

- Hosting **many** concurrent users on one Orin Nano  
- Multiple simultaneous 14B+ models  
- Full “cloud-fast” multi-agent Deep mode without a larger AGX Orin or discrete GPU  

### Example lean Jetson profile

```bash
KNONIX_MODEL=qwen3:8b          # or a smaller tools-capable model on 8 GB
OLLAMA_NUM_CTX=4096
OLLAMA_NUM_PREDICT=1536
OLLAMA_KEEP_ALIVE=-1
# Pull only: chat model + nomic-embed-text
```

**Bottom line:**  
- **Orin NX 16 GB+ or AGX Orin** → practical Jetson platform for KnonixAI.  
- **Orin Nano 8 GB** → evaluation / single-user only, carefully sized.  
- For team CMMC production, prefer a **server + dGPU** (or Jetson AGX 32/64 as an edge node).

---

## Disk breakdown (typical install)

| Component                   | Approx. size | Notes                                                                      |
| --------------------------- | ------------ | -------------------------------------------------------------------------- |
| Container images            | 12–15 GB     | Ollama (~8 GB), KnonixAI app (~3 GB), Postgres, Redis, Caddy, Kong, GoTrue |
| Ollama models               | 5–15 GB each | Each tools model ≈ 5 GB quantized; **plan headroom before every pull**     |
| Postgres + Redis + app data | 1–20 GB      | Grows with chat history, vault, and knowledge index                        |
| Docker build cache          | 0–10 GB      | When using `KNONIX_IMAGE_TAG=local`                                        |
| Headroom                    | **20+ GB**   | Pulls, upgrades, temp layers — **critical**                                |

### Example model catalogs

**Lean (evaluation)**

| Model              | Size      | Role                            |
| ------------------ | --------- | ------------------------------- |
| `qwen3:8b`         | ~5.2 GB   | Default chat (tools + thinking) |
| `nomic-embed-text` | ~0.3 GB   | RAG embeddings                  |
| **Total**          | **~6 GB** |                                 |

**Program (recommended)**

| Model              | Size       | Role                          |
| ------------------ | ---------- | ----------------------------- |
| `qwen3:8b`         | ~5.2 GB    | Default chat                  |
| `deepseek-r1:8b`   | ~5.2 GB    | Reasoning / math              |
| `glm4:9b`          | ~5.5 GB    | GLM-family stand-in           |
| `qwen2.5-coder:7b` | ~4.7 GB    | Coding workspace              |
| `gemma3:4b`        | ~3.3 GB    | Vision (no tools)             |
| `nomic-embed-text` | ~0.3 GB    | Embeddings                    |
| **Total**          | **~25 GB** | Needs **80–200 GB** data disk |

A **30 GB Docker data partition fills up quickly**. **Use 50 GB minimum; 200 GB+ for production CMMC-style use.**

---

## Network & identity

| Need                 | Guidance                                                                             |
| -------------------- | ------------------------------------------------------------------------------------ |
| **Public HTTPS**     | Domain + Caddy/Let’s Encrypt (installer wizard)                                      |
| **Entra / GCC High** | `KNONIX_MS_CLOUD_ENVIRONMENT=gcc_high`; redirect URIs on `.us`                       |
| **Air gap**          | Pre-load images + models; offline license mode                                       |
| **Outbound**         | Only for GHCR/model pulls and optional fleet heartbeat (**never** sends prompts/CUI) |

### Public URL / OAuth (per install)

The app binds to `0.0.0.0:3000` inside Docker. Browsers and Microsoft/Google
OAuth use the **public origin**:

| Variable               | Purpose                                        |
| ---------------------- | ---------------------------------------------- |
| `KNONIX_DOMAIN`        | Your FQDN (e.g. `ai.customer.gov`)             |
| `KNONIX_PUBLIC_URL`    | Full public origin (`https://ai.customer.gov`) |
| `NEXT_PUBLIC_BASE_URL` | Same as above                                  |
| `KNONIX_AUTH_SITE_URL` | Post-login landing URL                         |

**M365 connector redirect URI:**

```text
https://<KNONIX_DOMAIN>/api/knonix/connectors/microsoft/callback
```

---

## Docker data directory

If Docker stores data on a small volume (e.g. `/mnt/knonix-data`), either:

1. **Expand the data disk** (recommended for production), or
2. Run periodic maintenance: `./scripts/disk-maintenance.sh`

See installer [README.md — Disk maintenance](./README.md#disk-maintenance).

---

## Compliance / boundary notes

- **GCC High**: set `KNONIX_MS_CLOUD_ENVIRONMENT=gcc_high` and use Entra apps in
  the `.us` cloud. Register redirect URIs on the government endpoint.
- **Frontier APIs** (`KNONIX_ALLOW_FRONTIER=true`) send prompts **outside** your
  boundary. **Off by default** on sovereign installs — keep off for CUI-heavy programs unless ATO/policy allows.
- **CMMC readiness** still requires **your** policies, SSP, and assessment — see
  [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md).

---

## Hardware ↔ feature map

| Feature                           | Min tier             | Smooth tier    |
| --------------------------------- | -------------------- | -------------- |
| Chat (7–8B tools model)           | Evaluation           | Production     |
| CMMC readiness + RAG + SharePoint | Evaluation (slow)    | **Production** |
| Multi-model catalog (5+ LLMs)     | Production disk      | Production     |
| 14B–32B local quality             | Performance GPU      | Performance    |
| 70B / MoE open frontier           | Enterprise multi-GPU | Enterprise     |

---

## Moving to a larger host

If this install is slow (small CPU/RAM), migrate config + Docker volumes to a
production-tier machine:

**[MIGRATION.md](./MIGRATION.md)** — `./scripts/migrate.sh export` / `import`

On the new host, raise `OLLAMA_NUM_CTX` / `OLLAMA_NUM_PREDICT` only after you
have free memory headroom (see Performance tier above).
