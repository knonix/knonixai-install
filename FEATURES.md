# KnonixAI product features

Complete feature reference for operators and end users. For install env vars, see
[CONFIGURATION.md](./INSTALL_SETTINGS.md) and the public installer README
([knonix/knonixai-install](https://github.com/knonix/knonixai-install)).

---

## At a glance

| Area | What you get |
|------|----------------|
| **Chat** | Sovereign search + chat with local models (Ollama) by default |
| **Research modes** | **Quick · Pro · Adaptive · Deep** (clarify → tools → citations → follow-ups) |
| **Sources** | Always-visible source strip + Markdown export with links |
| **Spaces** | Team agent boxes — each space has its own personality and tools |
| **SKILL.md** | Per-space personality file (upload or template) |
| **Productivity hub** | Vault, MEMORY.md, skill packs, MCP, approvals, jobs, canvas, tabular, digests |
| **Connectors** | Microsoft 365 + Google (read/search; approve-to-write for durable actions) |
| **Knowledge / RAG** | Local embeddings (pgvector) — documents stay on your install |
| **Code** | `/code` workspace with GitHub / GitLab / local paths |
| **Studio** | Playbooks (when enabled) |
| **Admin** | License, seats, members, models, connectors, fleet |
| **Auth** | Email sign-up; optional Entra (incl. GCC High) / Google SSO |
| **CMMC / compliance** | Expert mode (CMMC, DFARS, FAR, NIST); enclave readiness; Studio playbook |

**CMMC positioning & competitive matrix:** [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)  
**Hardware sizing:** [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)

---

## CMMC, DFARS, NIST & federal compliance

- **Compliance intent** — CMMC / DFARS / FAR / NIST / CUI / readiness questions activate expert structured deliverables
- **Enclave-first evidence** — knowledge → vault → SharePoint/email (when linked) → official web for baselines only
- **Domain readiness matrix** — AC–SI with evidence-based statuses
- **Plugin / skill pack** — *CMMC & Regulation Expert* / *CMMC & DFARS Expert*
- **Space pipeline** — *CMMC Readiness Assessment*
- **Studio playbook** — *CMMC Readiness Sweep*
- **Disclaimer** — decision support; **not** a C3PAO certification

Full mapping: **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)**.

---

## Chat & research

- **Search modes** (composer toggle — cookie `searchMode`):

  | Mode | Cookie | Behavior |
  |------|--------|----------|
  | **Quick** | `quick` | Fast answers; tools when needed |
  | **Pro** | `pro` | Clarifying questions → research → citations → **3 follow-ups** |
  | **Adaptive** | `adaptive` | Balanced agentic research; visible tool steps + follow-ups |
  | **Deep** | `deep` | Multi-search + fetch + long report + sources + **3 dig-deeper follow-ups** |

  Keyboard: cycle modes with the configured **toggle search mode** shortcut.

  Pro / Adaptive / Deep never short-circuit to one-shot local answers (tools stay on).
  Guests on cloud deployments must sign in for Pro / Adaptive / Deep.

- **Source strip** — always-visible list of cited sources under answers (clickable URLs)
- **Export report** — download icon on message actions → Markdown + Sources section
- **Follow-up questions** — Related buttons after answers; click to dig deeper (Pro/Deep always; Adaptive when substantive)
- **Agent activity UI** — live status (thinking, tools, composing) so work is visible while streaming
- **Knowledge search** — `searchKnowledge` over uploaded library files (local RAG)
- **File uploads** — PDF, text/markdown, CSV, JSON, images (max 15MB; extension-friendly; indexed for RAG when storage configured)
- **Model labels** — **Local** (Ollama, sovereign) vs **Frontier** (leaves boundary) in the model picker
- **Tools-capable models only** — Ollama tags without `tools` (e.g. **phi4:14b**, **gemma2:9b**, **olmo2:13b**) are **hidden** from the chat picker and rejected at request time. Research needs tool calling.
- **Optional frontier models** — Anthropic / OpenAI / Grok / Google when
  `KNONIX_ALLOW_FRONTIER=true` (explicitly non-sovereign)

### Local LLM tools matrix (catalog)

| Tag | Tools (research chat) | Notes |
|-----|----------------------|--------|
| **qwen2.5:7b** | **Yes** (default) | Best general research model; verified live |
| qwen2.5:32b | Yes | Larger GPU host |
| qwen2.5-coder:7b | Yes | Code workspace default |
| llama3.1:8b | Yes | Strong CPU all-rounder |
| llama3.3:70b | Yes | Large GPU |
| mistral:7b / mistral-nemo:12b | Yes | Fast / multilingual |
| nemotron-mini:4b / nemotron:70b | Yes | NVIDIA family |
| granite3.1-dense:8b | Yes | Enterprise RAG-oriented |
| deepseek-r1:7b / :32b | Yes* | Reasoning; validate tool quality after pull |
| **phi4:14b** | **No** | Completion only — will error if forced |
| gemma2:9b | No | No tools badge on Ollama |
| olmo2:13b | No | No tools badge on Ollama |
| nomic-embed-text | Embed only | Not for chat |

\* After pull always run: `ollama show <tag>` or `scripts/verify-ollama-llms.sh`.

### How to verify research modes

1. Hard-refresh the app so the mode toggle shows **Quick · Pro · Adaptive · Deep**.
2. Select **Pro** → ask a broad question → expect clarifiers and/or tool trail → sources strip → related follow-ups.
3. Select **Deep** → expect multi-step activity (search/fetch/todos) → multi-section report → sources → follow-ups.
4. Click a **Related** question → new turn continues the thread.
5. Use the **download** icon under an answer → `.md` report with Sources.
6. Confirm model chip shows **Local** for Ollama (default sovereign install).

---

## Spaces (agent boxes)

Each **Space** is an isolated work context for a team or mission.

### Settings tabs

| Tab | Purpose |
|-----|---------|
| **Overview** | Name, description, runtime summary |
| **SKILL.md** | Upload or edit space personality (YAML frontmatter + markdown body) |
| **Productivity** | Vault, memory, skill packs, MCP, approvals, jobs, canvas, tabular, digests, flags |
| **Instructions** | Governance / compliance rules injected every turn |
| **Workers** | Orchestrator workers (knowledge, tenant, web, …) and tool hints |
| **Pipelines** | Multi-stage governed workflows the supervisor can run |

### Personality (SKILL.md)

- One **SKILL.md per space** — other spaces never inherit it
- Upload `.md` / paste / **Insert template**
- Injected as binding “Space personality” in the system prompt
- Spaces list shows **SKILL.md** vs **No skill** badges

### Orchestrator

Supervisor + specialized workers (Intel OPEA–style / Dell pipeline model):

- Knowledge, tenant connectors, web, synthesis, compliance
- Pipelines define ordered stages with worker bindings
- Space meta questions answered from config (no needless web search)

---

## Productivity hub (Space → Settings → Productivity)

### Vault

- Space-only document store (paste text/markdown)
- Agent tool: **`searchSpaceVault`**
- Use for contracts, policies, runbooks that must not mix with other spaces

### MEMORY.md

- Durable facts: decisions, owners, glossary
- Always available to the agent in that space
- Agent can **propose** appending facts via Approvals (`append_memory`)

### Skill packs

Built-in packs (org library, one-click **Apply** → copies into SKILL.md):

| Pack | Use |
|------|-----|
| Compliance Reviewer | CUI-aware, cite sources, formal tone |
| Weekly Status Writer | Executive status structure |
| Incident Postmortem | Blameless timeline + actions |
| Contract Analyst | Parties, terms, risks |

Admins can create additional org skill packs via API.

### MCP connector registry

- Register **Model Context Protocol** server URLs (Jira, SQL, internal tools)
- **Link** servers to a space (allowlist per agent box)
- Org-level registry; space enables which servers apply

### Approvals (approve-to-write)

- Agent tool **`proposeAction`** queues write/durable actions
- Human **Approve / Reject** in the Approvals panel
- Local executions on approve: `save_artifact`, `append_memory`
- External drafts (`draft_email`, `draft_teams`, `create_ticket`, …) queued with full preview — no silent sends

### Scheduled / background jobs

- Name + prompt + optional cron (e.g. `0 7 * * 1`)
- **Run now** produces a canvas artifact with the job prompt for auditability
- Use for weekly digests, standing reviews, overnight research prompts

### Artifact canvas

- Living markdown documents per space
- **Save revision** keeps prior versions (version history)
- Export-friendly for reports and status packs

### Tabular review

- Paste multiple documents separated by a line containing only `---`
- Builds a grid: parties, key terms, risks, CUI flags, summary
- Suited to contract / diligence spaces

### Digests

- **Generate digest now** — vault + artifacts + pending approvals snapshot
- Optional space flag: proactive digests enabled

### Classification & routing flags

| Flag | Values / effect |
|------|------------------|
| **Classification** | `public` · `internal` · `cui` — steers tool guidance and caution language |
| **Digest enabled** | Opt into proactive digest behavior |
| **Adaptive routing** | Prefer fast routing / stronger synthesis when models allow |

---

## Connectors

| Provider | Capabilities (typical) |
|----------|------------------------|
| **Microsoft 365** | Email, OneDrive, SharePoint, Teams, calendar, contacts (search/read) |
| **Google** | Gmail, Drive, calendar (search/read) |

- Admin enables provider + OAuth client under **Admin → Connectors**
- Each user completes their own OAuth (delegated permissions)
- GCC / GCC High / commercial routing via install cloud environment
- See [MICROSOFT_365_SETUP.md](https://github.com/knonix/KnonixAI/blob/main/docs/MICROSOFT_365_SETUP.md)

---

## Knowledge library & RAG

- Upload documents (when object storage is configured) or use Space vault paste
- Local **nomic-embed-text** (or configured embed model) via Ollama
- pgvector hybrid search — content never leaves the install for embeddings
- Space chats can scope knowledge across space members

---

## Code workspace (`/code`)

- Projects: **local path**, **GitHub**, or **GitLab**
- Optional install-wide PATs (`KNONIX_GITHUB_TOKEN`, `KNONIX_GITLAB_TOKEN`)
- Coding model default: `qwen2.5-coder:7b` (configurable)

---

## Studio

- Playbooks for multi-step company workflows (when `KNONIX_STUDIO_ENABLED=true`)
- Runs stay on the install

---

## Admin & platform

| Area | Features |
|------|----------|
| **License & seats** | Free seats + paid expansion; connected / offline / free modes |
| **Members** | Roster, roles, seat consumption |
| **Models** | Pull/list Ollama models; set active defaults |
| **Connectors** | Org policy + OAuth client configuration |
| **Fleet** | Heartbeat seat reporting (no PII) |
| **Setup checklist** | `GET /api/knonix/setup-checklist` — guided day-1 progress |

---

## Auth & access

- Email/password sign-up (first user = org owner)
- Optional **Microsoft Entra** (commercial / GCC / GCC High) and **Google**
- Admin-chosen member roster (not whole-directory by default)
- See [ENTERPRISE_SSO.md](https://github.com/knonix/KnonixAI/blob/main/docs/ENTERPRISE_SSO.md)

---

## APIs (selected)

| Endpoint | Description |
|----------|-------------|
| `GET /api/knonix/health` | Runtime health + setup steps |
| `GET /api/knonix/setup-checklist` | Guided install checklist (authenticated) |
| `GET /api/knonix/license` | Seats, mode, limits |
| `GET /api/knonix/models` | Model catalog |
| `GET/PATCH /api/knonix/spaces/:id` | Space config (incl. SKILL.md) |
| `GET/POST /api/knonix/spaces/:id/productivity` | Full productivity hub |

---

## Sovereignty summary

| Path | Leaves boundary? |
|------|------------------|
| Local Ollama chat / embeddings | No |
| SearXNG search | Depends on SearXNG engines (self-hosted container) |
| M365 / Google connectors | Calls Microsoft/Google as the signed-in user |
| Frontier APIs | **Yes** — off by default |
| Fleet heartbeat | Opaque install hash, seat count, version only — no documents/PII |
