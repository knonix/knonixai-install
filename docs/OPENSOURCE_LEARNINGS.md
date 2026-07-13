# Open-source platform learnings → KnonixAI roadmap

Research snapshot (2025–2026) of **self-hosted** AI chat / agent platforms, mapped to
KnonixAI’s product goals (sovereign by default, CMMC/DIB, Spaces, connectors) and to
bugs we hit on the platform host.

**Peers reviewed:** [Open WebUI](https://github.com/open-webui/open-webui),
[LibreChat](https://github.com/danny-avila/LibreChat),
[AnythingLLM](https://github.com/Mintplex-Labs/anything-llm),
[Dify](https://github.com/langgenius/dify),
[OpenClaw](https://docs.openclaw.ai/) (agent shell; often cloud-backed).

---

## 1. What the best peers do well

| Area | Open WebUI | LibreChat | AnythingLLM | Dify | OpenClaw-style |
|------|------------|-----------|-------------|------|----------------|
| **Install path** | One Docker compose, big community docs | Docker + env; chat-first | Desktop + Docker “workspace” | Docker + workflow studio | Desktop agent + model backend |
| **Model UX** | Always-visible model picker; per-model advanced params (ctx!) | Side-by-side compare; multi-provider | Workspace model defaults | App-level model | Backend-defined; often cloud |
| **Web context** | Built-in web search; **warns Ollama ctx too small for pages** | Search + scraper pipeline (SearxNG / Serper / Firecrawl / Jina) | Doc + site ingest into workspace | Workflow tools | Often API tools / thin local loop |
| **RAG** | Hybrid search, multiple extractors, external embeddings | Files + knowledge | Workspace docs, simpler | Knowledge + pipeline | Varies |
| **Agents / tools** | Tools, functions, MCP growth | Agents + MCP + code interpreter | No-code agent builder | Graph workflows | Skills / tools heavy |
| **Efficiency on CPU** | Docs: small models, raise ctx only when needed, offload embeddings | Separate search/scrape services | Keep workspaces small | Queue workers | Prefer GPU/API |
| **Failure UX** | Often loud config errors | Search pipeline status | Simpler surface | Workflow run logs | Depends |

### Critical peer lesson (Open WebUI docs)

> Ollama’s small context (e.g. 2048) **silently drops** retrieved web/RAG text so the model
> “never saw” the page even when fetch succeeded.

That matches our NIST/POA&M incident: **prefetch OK (4909 chars)** but **ctx=1536 + office tools** → model claimed no page access.

---

## 2. Architectural patterns worth copying

### A. Separate “retrieve” from “reason” (LibreChat web search, Open WebUI RAG)

```
User message
  → deterministic retrieve (search / scrape / RAG)
  → inject cleaned context into prompt
  → LLM answers (optional tools only for gaps)
```

**Knonix already has** server URL prefetch + SearXNG.  
**Peers do better when** retrieval always runs for URLs/web mode and is **visible in UI** (sources strip, visit log), and **tool loops stay empty** if context is already complete.

### B. Hardware-aware defaults (AnythingLLM simplicity + Open WebUI performance guides)

- Auto-pick model size from RAM/GPU.
- One loaded model on low RAM.
- External embeddings (nomic via Ollama) so the app process stays light.

**Knonix now:** `scripts/hardware-profile.sh` (low → 3B, medium → 7B, high → larger).

### C. Explicit product modes (LibreChat agents vs plain chat; Dify workflows)

- **Chat** = fast, few tools, short answer.
- **Research** = search + fetch + sources.
- **Document** = office/export tools only when user asks for a file.

**Knonix risk:** compliance keyword `POAM` enabled **office tools** during a glossary Q&A.

### D. Config that cannot “hide” core UX

- Model selector always on for self-host (Open WebUI).
- Cloud multi-tenant flags must not disable local Ollama UX.

**Knonix bug:** `KNONIX_CLOUD_DEPLOYMENT=true` on platform compose hid the model bubble.

### E. Streaming without buffering (all mature UIs)

- Reverse proxy must not gzip SSE.
- Flush immediately so CPU token streams feel alive.

**Knonix:** Caddy `@compressible` excludes `/api/chat*`.

---

## 3. Efficiency principles (CPU / low GPU)

| Principle | Peer practice | Knonix action |
|-----------|---------------|---------------|
| **Right-size model** | 3B–7B on CPU; 7B–14B on GPU | Hardware profile defaults |
| **Right-size context** | Raise ctx when using web/RAG; don’t keep 16k warm forever on CPU | 4096+ when visiting pages; 1536–2048 for pure chat on tiny hosts |
| **Few tools on local** | Docker research: local tool-calling models fail with large tool schemas | Cap tools; after successful URL visit → **tools=[]** |
| **Prefetch not tool-hope** | Don’t rely on small models to call `fetch` | Server always visits user URLs first |
| **One model loaded** | Avoid thrashing | `OLLAMA_MAX_LOADED_MODELS=1` on low |
| **Embeddings off app heap** | Open WebUI external embedding engine | Keep `nomic-embed-text` in Ollama, not in Node |
| **Honest latency** | UI shows “searching / reading page” | Sources + visitedSources metadata (already partial) |

---

## 4. Correctness checklist (“every aspect works”)

Use as release / QA gate for each image:

### Inference & models
- [ ] Model pill visible when `KNONIX_CLOUD_DEPLOYMENT=false`
- [ ] Switch model updates cookie + next turn uses new tag
- [ ] Cold load message in UI if model not warm
- [ ] Hardware profile picks 3B on ≤20 GB RAM installs

### Web / URL
- [ ] Plain URL in text → server logs `[prefetchUrls] VISITED OK`
- [ ] URL **chip** (`data-sourceUrl`) → same (getTextFromParts must include chips)
- [ ] After successful visit: **no office tools** unless create/draft/docx
- [ ] Answer cites page; refuses “I can’t access” if visit OK
- [ ] `num_ctx` ≥ ~4096 when prefetched content present

### Search
- [ ] SearXNG health + JSON search from app network
- [ ] Quick mode: limited search; Pro/Deep: more steps
- [ ] Fail loud if SEARCH_API misconfigured

### Auth & multi-user
- [ ] First signup becomes org owner
- [ ] Health `authConfigured: true` with runtime Supabase keys (not build-time empty)
- [ ] SSO GCC High still works with cloud=false

### Platform vs customer
- [ ] `./install.sh` never mounts platform compose
- [ ] Platform host: `PLATFORM_OWNER=true`, **cloud=false** for local model UX
- [ ] Customer image: no license-service required

### Ops
- [ ] Caddy does not gzip SSE
- [ ] Health `ready: true`
- [ ] Heartbeat reports seats
- [ ] Logs: prefetch, tool clamp, model id per turn

---

## 5. Priority engineering backlog (main app `knonix/KnonixAI`)

Ship these in source (not only entrypoint patches):

### P0 — Correctness (must ship)
1. **`getTextFromParts`** includes `data-sourceUrl` / pasted / note parts (URL chips).
2. **Office / compliance tools** require create/draft/export verbs — not bare `POAM`/`SSP`.
3. **After successful URL prefetch:** default `tools=[]`, `maxSteps=1` unless explicit file/export.
4. **`KNONIX_CLOUD_DEPLOYMENT`** must not hide model selector on self-host; split “SaaS multi-tenant” flag from “local enclave” flag.
5. **Dynamic `num_ctx`:** when prefetched chars > N, bump ctx to min(8192, env max) for that turn.

### P1 — Efficiency
6. Hardware-aware defaults in app Admin (mirror `hardware-profile.sh`).
7. Tool schema budget: ≤3–4 tools on Ollama; connectors only when intent is tenant.
8. UI: live “Visiting csrc.nist.gov…” from `visitedSources` / prefetch events.
9. Optional Firecrawl/Jina fallback when regular HTML is thin (LibreChat-style scraper layer).

### P2 — Product depth (peers)
10. Side-by-side model compare (LibreChat).
11. Workspace RAG UX closer to AnythingLLM (clear “chat with this folder”).
12. MCP marketplace / Open WebUI-style tool plugins without breaking sovereign defaults.

---

## 6. What we already fixed on this host (runtime)

| Patch / config | Peer parallel |
|----------------|---------------|
| Health authConfigured runtime env | Don’t bake empty public keys |
| URL chip → query text | Retrieve before reason |
| POAM ≠ Word doc | Mode separation |
| Visit success → answer first | Prefetch-as-context |
| Model selector cloud=false | Always-on model UX |
| Hardware profile 3B / Caddy no-gzip SSE | CPU efficiency + streaming |
| `OLLAMA_NUM_CTX=4096` | Open WebUI web/RAG ctx warning |

Entrypoint: `scripts/knonix-entrypoint.sh`.  
Image bake: `image-build/`.

---

## 7. Strategic takeaway

| Don’t copy blindly | Do copy |
|--------------------|---------|
| OpenClaw’s **default cloud speed** (breaks sovereignty) | Their **thin loop** when context is already enough |
| Dify’s full workflow complexity for day-1 chat | Clear mode separation |
| Loading every connector tool every turn | Intent-gated tools (we have this; refine) |
| Huge agent stacks on 3B models | Prefetch + short answer path |

**Knonix differentiator stays:** sovereign defaults, CMMC/Spaces/connectors/fleet.  
**Peer efficiency win:** fewer tools, enough context, visible retrieval, hardware-aware models.

---

## 8. Suggested next implementation sprint (2 weeks)

| Day | Work |
|-----|------|
| 1–2 | Land P0 #1–#4 in `knonix/KnonixAI`; CI smoke tests for URL chip + POAM glossary |
| 3–4 | Dynamic ctx + UI “visiting…” strip |
| 5 | Hardware profile in Admin + install already done |
| 6–7 | Regression suite: auth, model switch, SearXNG, SharePoint smoke, SSE through Caddy |
| 8–10 | Publish GHCR image; remove reliance on entrypoint patches |
| 11–14 | Docs: EASY_SETUP low-end, COMPARISON update, customer verify-install ready=true |

---

## How “learning” works on a customer install (important)

KnonixAI does **not** fine-tune or permanently retrain weights from everyday chat.

| Mechanism | What it does | Where |
|-----------|--------------|--------|
| **Chat context** | Remembers the current conversation turn-by-turn | In-session only |
| **RAG / uploads** | Indexes files so answers ground in *your* documents | Local Postgres + embeddings |
| **Spaces MEMORY.md / vault** | Durable notes the agent can use | Per-space, on the install |
| **Related follow-ups** | After substantive answers, shows 3 tappable next questions | UI + saved message ` ```spec ` |

For accurate compliance answers (POA&M, CMMC, NIST), prefer:

1. Upload official PDFs / pages into the space library, **or** paste the source URL so prefetch/tools can ground the answer  
2. Use a tools-capable model with enough quality (`qwen3:8b` when hardware allows; `qwen2.5:3b` is for low-CPU installs)  
3. Prefer **Pro / Adaptive** research modes when multi-source rigor matters  

Smoke test after install: `./scripts/qa-chat-smoke.sh` and `./scripts/verify-install.sh`.

---

*This document is guidance for product/engineering. It does not change customer legal terms.*
