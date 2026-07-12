# Getting Started with KnonixAI

**Public installer (this repo):** [github.com/knonix/knonixai-install](https://github.com/knonix/knonixai-install)  
Installs the prebuilt image from GHCR — **no source access or token required**.

---

## Documentation map

| Doc | Audience | Contents |
| --- | -------- | -------- |
| **[README.md](./README.md)** | Everyone | Install wizard, first login, commands |
| **[EASY_SETUP.md](./EASY_SETUP.md)** | Non-technical | 3-step setup |
| **[FEATURES.md](./FEATURES.md)** | All users | Full product feature list |
| **[COMPARISON.md](./COMPARISON.md)** | Buyers | Competitive matrix vs Copilot, ChatGPT, Claude, Glean, Perplexity, OpenClaw, Cursor |
| **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)** | Compliance / capture | CMMC/DFARS/NIST mapping, SSP/POA&M suite, competitive compliance table |
| **[SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)** | IT / ops | CPU/RAM/disk/GPU, **NVIDIA Jetson**, model sizing |
| **[INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)** | Ops | Every `.env` variable |
| **[.env.example](./.env.example)** | Ops | Annotated config template |

---

## Install in 60 seconds

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
./install.sh
```

- **No domain** → http://localhost:3000  
- **Domain set** → `https://<your-domain>/` and `/admin`  

Non-technical path: **[EASY_SETUP.md](./EASY_SETUP.md)**.

---

## First hour after install

1. Sign up at `/auth/sign-up` (first user = org owner) → open `/admin`  
2. Confirm a **local tools-capable model** is active (e.g. `qwen3:8b`)  
3. Create a **Space** → apply **CMMC & DFARS Expert** skill pack if needed  
4. Upload policies / SSP drafts to **Knowledge** or Space **Vault**  
5. Optional: link **Microsoft 365** under Admin → Connectors  
6. Chat: **Quick** for speed; **Pro / Adaptive / Deep** for research and compliance packages  

Verify:

```bash
./scripts/verify-install.sh
curl -fsS http://localhost:3000/api/knonix/health
```

---

## Day-1 prompts (examples)

- “What is DFARS 252.204-7012 in plain language?”  
- “Assess our CMMC Level 2 readiness using this space’s vault and knowledge.”  
- “Draft a System Security Plan (SSP) from our enclave documents.”  
- “Write a POA&M from these gaps and format as a table.”  
- “Paste https://example.com/docs and summarize for our ISSO.”  

---

## Configuration quick links

| Goal | Setting |
| ---- | ------- |
| Public HTTPS | `KNONIX_DOMAIN`, `KNONIX_ACME_EMAIL` |
| Default chat model | `KNONIX_MODEL` (Admin can override) |
| Context / length | `OLLAMA_NUM_CTX`, `OLLAMA_NUM_PREDICT` |
| GCC High Graph | `KNONIX_MS_CLOUD_ENVIRONMENT=gcc_high` |
| Frontier APIs (leaves boundary) | `KNONIX_ALLOW_FRONTIER=true` + API keys |
| License fleet | `KNONIX_LICENSE_SERVICE_TOKEN` / seat token |
| Jetson / low RAM | `OLLAMA_NUM_CTX=4096`, single small tools model |

Full table: **[INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)**.

---

## Hardware at a glance

| Goal | Min hardware |
| ---- | ------------ |
| Demo / single user | 4 vCPU · 16 GB RAM · 50 GB disk |
| Team / CMMC program | **16 vCPU · 64 GB · 200 GB** |
| Edge (Jetson) | **Orin NX 16 GB+** or **AGX Orin** (NVMe) |
| Fast local quality | 24 GB+ NVIDIA dGPU |

**Can an NVIDIA Jetson run this?** Yes — Orin NX 16 GB+ / AGX Orin recommended. Orin Nano 8 GB is demo-only. Full matrix: **[SYSTEM_REQUIREMENTS.md § NVIDIA Jetson](./SYSTEM_REQUIREMENTS.md#nvidia-jetson--can-it-run-knonixai)**.

---

## Support boundaries

- **Sovereign mode** (default): local models — slower on small CPUs, data stays put.  
- **Frontier mode** (opt-in): cloud speed — **not** for CUI unless policy allows.  
- **CMMC docs** are decision-support drafts, not C3PAO certification.  

Sales / licensing: **sales@knonix.com**
