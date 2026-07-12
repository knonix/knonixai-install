# KnonixAI — Product Comparisons

**Who this is for:** buyers evaluating KnonixAI against cloud assistants, enterprise search, and agent platforms.

**Related:** [FEATURES.md](./FEATURES.md) · [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md) · [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)

---

## One-line positioning

> **KnonixAI is a standalone, self-hosted AI enclave for U.S. Government and regulated contractors** — research chat, Spaces, CMMC/NIST documentation, M365/Google connectors, and local models — without defaulting prompts and documents to a public LLM cloud.

---

## Master comparison matrix

| Capability | **KnonixAI** | **Microsoft 365 Copilot** | **ChatGPT Enterprise / Team** | **Claude (API / Work)** | **Glean** | **Perplexity Enterprise** | **OpenClaw / agent shells** | **Cursor / coding IDEs** |
|------------|--------------|---------------------------|-------------------------------|-------------------------|-----------|---------------------------|-----------------------------|--------------------------|
| **Primary deployment** | Self-host Docker (your enclave) | Microsoft cloud | OpenAI cloud | Anthropic cloud | Vendor cloud | Vendor cloud | Desktop / local agent + cloud models | Desktop + cloud (local optional) |
| **Default inference** | **Local open-weight (Ollama)** | Microsoft models | OpenAI | Anthropic | Vendor | Vendor | Often **cloud API** (very fast) | Cloud or local |
| **Data sovereignty by default** | **Yes** | Tenant cloud | No | No | No | No | Depends on model backend | Partial |
| **Air-gapped / offline license** | **Yes** | No | No | No | Limited | No | Possible if fully local | Limited |
| **GCC High / Azure Gov Graph** | **Yes (`.us` routing)** | Native M365 | N/A | N/A | Varies | N/A | N/A | N/A |
| **Built-in CMMC / 800-171 readiness** | **Yes** (expert + domain matrix + enclave evidence) | Generic | Generic | Generic | Search | Research | Custom skills only | N/A |
| **SSP / POA&M / policy drafting** | **Yes** (chat + Studio playbooks) | Templates vary | GPTs | Projects | Limited | Limited | Custom | Limited |
| **Per-space agent personality (SKILL.md)** | **Yes** | Copilot Studio (cloud) | Custom GPTs | Projects | Workflows | Collections | Skills / agents | Rules |
| **Human approve-to-write** | **Yes** (MEMORY, SKILL, artifacts) | Policy-dependent | N/A | N/A | Varies | N/A | Often auto | Git local |
| **M365 connectors** | Read/search (mail, SP, OD, Teams) | Deep M365 | Plugins | MCP/plugins | Many SaaS | Limited | Integrations vary | GitHub |
| **Google Workspace** | Read/search (Gmail, Drive, Calendar) | Limited | Plugins | Plugins | Yes | Limited | Varies | Limited |
| **Local RAG (your Postgres)** | **pgvector on install** | Graph/SharePoint | Vendor storage | Vendor | Vendor index | Vendor | Varies | Code index |
| **In-stack web search** | **SearXNG** (in boundary) | Bing | OpenAI | Anthropic | Vendor | Core product | Varies | N/A |
| **Open-weight model catalog** | Full Ollama (Qwen3, R1, GLM-4, …) | No | No | No | No | No | If Ollama wired | Some local |
| **Frontier models** | Opt-in, labeled **non-sovereign** | Always cloud | Always | Always | Cloud | Cloud | Typical default | Cloud |
| **Seat licensing** | 2 free + metered seats | M365 add-on | Per seat | Per seat | Enterprise | Per seat | N/A / DIY | Per seat |
| **Best fit** | **DIB / CMMC / sovereign AI platform** | M365-native productivity | General enterprise chat | High-quality cloud assistants | Intranet search | Web research UX | Fast agent tinkering | Software engineering |

---

## Why KnonixAI can feel slower than OpenClaw

| Factor | KnonixAI (typical sovereign install) | OpenClaw-style apps |
|--------|--------------------------------------|---------------------|
| **Where tokens are generated** | Local Ollama (often **CPU** on small VMs) | Hosted **GPU** APIs or a gaming GPU |
| **Speed class** | ~5–20 tok/s on 2–8 CPU cores | Often **50–200+ tok/s** on cloud GPU |
| **Work per turn** | Agent tools, URL prefetch, RAG, multi-mode research | Often thinner tool loops or pure chat API |
| **Tradeoff** | Prompts/docs stay in **your boundary** | Speed first; data may leave the box |

**To feel “OpenClaw-fast” on KnonixAI:** enable frontier APIs (Admin) for non-CUI work, or run on a **Jetson Orin / RTX GPU** with a 7–8B tools model. See [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md#nvidia-jetson--can-it-run-knonixai).

---

## When to choose what

| You need… | Choose |
|-----------|--------|
| CMMC / DFARS program AI **inside** the enclave | **KnonixAI** |
| Day-to-day Office productivity in M365 only | Copilot |
| Best pure cloud chat quality | ChatGPT Enterprise / Claude |
| Company-wide “search everything” UX | Glean |
| Web research product UX | Perplexity |
| Fast local agent experiments on a workstation | OpenClaw + strong GPU/API |
| IDE coding agent | Cursor |

Many teams run **KnonixAI for regulated / CMMC work** and a cloud assistant for non-sensitive tasks.

---

## Feature depth (KnonixAI alone)

| Area | What you get |
|------|----------------|
| **Chat** | Quick / Pro / Adaptive / Deep; sources; follow-ups; activity trail |
| **URL paste** | Server visits sites before the model answers |
| **Spaces** | SKILL.md, MEMORY.md, vault, pipelines, CUI classification |
| **Compliance** | CMMC expert, readiness matrix AC–SI, SSP/POA&M/policies |
| **Studio** | Playbooks: readiness sweep, draft SSP, draft POA&M, policy pack |
| **Admin** | Models, connectors, knowledge, seats, setup checklist |
| **Code** | `/code` with Git remotes under workspace root |

Full detail: [FEATURES.md](./FEATURES.md).

---

## Specs snapshot (hardware)

| Tier | CPU / memory | Disk | GPU | Typical models |
| ---- | ------------ | ---- | --- | -------------- |
| Evaluation | 4 vCPU · 16 GB | 50 GB | None | `qwen3:8b` + embed |
| Production / CMMC team | **16 vCPU · 64 GB** | **200 GB** | Optional 16–24 GB | 8B tools + coder + R1 |
| Performance | 16–32 cores · 64–128 GB | 300–500 GB NVMe | **24 GB+ NVIDIA** | 14B–32B |
| **Jetson edge** | Orin NX 16 GB+ / AGX Orin | **NVMe 128 GB+** | Integrated | 8B (NX) · 14B–32B (AGX 64) |
| Enterprise open frontier | 128 GB+ RAM | 500 GB–2 TB | 48–80 GB+ VRAM | 70B / MoE |

Full sizing, Jetson matrix, disk breakdown: **[SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)**.