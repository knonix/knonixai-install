# KnonixAI — Installer

Self-host **KnonixAI** from the prebuilt container image. Sovereign AI search
and assistant for U.S. Government and regulated environments — local
open-weight models run inside your boundary, so your data never has to leave.

> This installer pulls a **prebuilt public image** from the GitHub Container
> Registry (GHCR). You do **not** need access to the KnonixAI source code, and
> **no token or login is required** to pull the image.

| Doc | Audience |
|-----|----------|
| **[EASY_SETUP.md](./EASY_SETUP.md)** | Non-technical install (3 steps + first-day checklist) |
| **[FEATURES.md](./FEATURES.md)** | Full product features (Spaces, SKILL.md, productivity, connectors, …) |
| **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)** | **CMMC / DFARS / NIST mapping, readiness runbook, competitive matrix** |
| **[INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)** | Every `.env` setting explained |
| **[SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)** | **Hardware tiers for smooth production & GPU sizing** |

---

## What you get after install

| Capability | Description |
|------------|-------------|
| **Sovereign chat** | Local Ollama models by default; web search via in-stack SearXNG |
| **Research modes** | Quick · Pro · Adaptive · Deep (clarify, multi-source, citations, follow-ups) |
| **Sources & export** | Always-visible source strip; Markdown report download |
| **Spaces** | Team agent boxes — each with its own personality and tools |
| **SKILL.md** | Upload a personality file per space |
| **Productivity hub** | Vault · MEMORY.md · skill packs · MCP registry · approve-to-write · jobs · canvas · tabular review · digests · CUI flags |
| **Connectors** | Microsoft 365 + Google (search/read; actions require human approval) |
| **Knowledge / RAG** | Local embeddings — documents stay on your install |
| **Code workspace** | GitHub / GitLab / local projects under `/code` |
| **Admin** | License, seats, members, models, connectors, setup health |
| **Auth** | Email sign-up; optional Entra (incl. GCC High) / Google SSO |
| **CMMC / compliance** | Expert coaching, enclave readiness matrices, Studio readiness sweep |

See **[FEATURES.md](./FEATURES.md)** for the complete feature list and UI map.  
**Selling to federal / DIB?** Start with **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)** (framework matrix + competitive comparison).

---

## Prerequisites

- **Docker Engine** (`docker version`)
- **Docker Compose v2** — `docker compose version` (plugin, not old `docker-compose` v1)

  ```bash
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
  docker compose version
  ```

- **Hardware** — see **[SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)**  
  - Evaluation: 4 vCPU · 16 GB RAM · **50 GB** Docker data  
  - **Smooth team / CMMC: 16 vCPU · 64 GB RAM · 200 GB disk**  
  - Best quality: **24 GB NVIDIA GPU**
- **(Optional) NVIDIA GPU + `nvidia-container-toolkit`** for faster local inference
  (uncomment the `deploy` block under `ollama` in `docker-compose.yml`).

---

## Quick start (recommended)

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
./install.sh
```

Non-technical walkthrough: **[EASY_SETUP.md](./EASY_SETUP.md)**.

### Wizard prompts

| Prompt | Why |
|--------|-----|
| **Postgres password** | Protects your database (required; Enter = secure random) |
| **Public domain** (optional) | Enables HTTPS via Caddy + Let’s Encrypt |
| **Email for certificates** | Cert expiry notices when domain is set |
| **Fleet enrollment token** | From Knonix — seat tracking on the fleet board (blank = free/local mode) |

The installer also **auto-generates** auth JWT keys, heartbeat secret, and
connector encryption keys so you do not hand-edit secrets.

When it finishes:

- **No domain** → <http://localhost:3000>
- **Domain set** → `https://<your-domain>/` and `/admin`

### First login (required)

1. Open **`/auth/sign-up`** — first account becomes the **organization owner**.
2. Open **`/admin`** — License & Seats, local models, health.
3. Open **`/admin/members`** — invite colleagues (each active member = 1 seat).
4. Optional: **Admin → Connectors** for Microsoft 365 / Google.
5. Open **`/spaces`** — create a Space; set **SKILL.md** and **Productivity**.

### Verify

```bash
./scripts/verify-install.sh
curl -fsS http://localhost:3000/api/knonix/health   # or https://your-domain/...

# LLM tools check (research chat requires Ollama "tools" capability)
./scripts/verify-ollama-llms.sh --catalog
```

**Important:** Models like **phi4:14b** only support completion — they **cannot** run search/connectors/research. Use **qwen2.5:7b** (default) or any tag where `ollama show <tag>` lists `tools`.

---

## Install settings (`.env`)

Copy `.env.example` → `.env`, or let `./install.sh` create it.

### Settings you usually care about

| Variable | Required? | Purpose |
|----------|-----------|---------|
| `POSTGRES_PASSWORD` | **Yes** | Database password |
| `KNONIX_LICENSE_SERVICE_TOKEN` | Connected mode | Fleet enrollment token from Knonix |
| `KNONIX_DOMAIN` | Prod HTTPS | Public hostname |
| `KNONIX_ACME_EMAIL` | With domain | Let’s Encrypt notices |
| `KNONIX_IMAGE_TAG` | Prod | Pin release (`v1.x.x`) instead of `latest` |
| `KNONIX_MODEL` | Optional | Default chat model (`qwen2.5:7b`) |
| `KNONIX_CODING_MODEL` | Optional | Coding model (`qwen2.5-coder:7b`) |
| `OLLAMA_NUM_CTX` | Optional | Context size (default tuned for CPU hosts) |
| `KNONIX_FREE_SEATS` | Optional | Free seats per install (default `1`) |
| `KNONIX_LICENSE_MODE` | Optional | `connected` · `free` · `offline` |
| `KNONIX_ALLOW_FRONTIER` | Optional | `false` by default — cloud models leave boundary |
| `KNONIX_RAG_ENABLED` | Optional | Local document search (`true`) |
| `ENABLE_AUTH` | Optional | Multi-user (`true`) |
| `KNONIX_MS_OAUTH_*` | Optional | Microsoft 365 connector app |
| `KNONIX_AUTH_AZURE_*` | Optional | Entra SSO (incl. GCC High URL) |
| `KNONIX_AUTH_GOOGLE_*` | Optional | Google SSO |
| `KNONIX_AUTH_SMTP_*` | Optional | Password-reset mail |
| `KNONIX_GITHUB_TOKEN` / `KNONIX_GITLAB_TOKEN` | Optional | Private repo clones for `/code` |

**Full table of every variable:** **[INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)**  
Also see comments in **[.env.example](./.env.example)**.

### Licensing modes (summary)

| Mode | Env | Behavior |
|------|-----|----------|
| **Connected** (default) | `KNONIX_LICENSE_MODE=connected` + fleet token | Daily heartbeat (no PII); seats on fleet board |
| **Free / local** | No token → installer may set `free` | Local free seats only |
| **Offline / air-gap** | `offline` + license token/public key from sales | No network to Knonix |

---

## HTTPS on your domain

In `.env`:

```bash
KNONIX_DOMAIN=ai.example.com
KNONIX_ACME_EMAIL=admin@example.com
```

```bash
./install.sh
```

**Requirements:** DNS A/AAAA to this host; ports **80** and **443** open.

```bash
docker compose -f docker-compose.yml -f docker-compose.proxy.yml logs caddy
```

Local HTTPS test: `KNONIX_DOMAIN=localhost` (internal CA, no public DNS).

---

## Manual pull / compose-only path

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
cp .env.example .env
# Edit: POSTGRES_PASSWORD, optional domain + fleet token, KNONIX_IMAGE_TAG
docker compose up -d
docker compose exec ollama ollama pull qwen2.5:7b
docker compose exec ollama ollama pull nomic-embed-text
```

Database migrations run **automatically** when the `knonixai` container starts.

### Private image?

```bash
GHCR_USER=<github-user> GHCR_TOKEN=<token-from-knonix> ./install.sh
```

---

## Day-1 product tour (after install)

1. **Sign up** at `/auth/sign-up`
2. **Admin** — confirm license + models at `/admin`
3. **Members** — add seats
4. **Connectors** (optional) — link M365 / Google
5. **Chat research modes** (composer toggle):
   - **Quick** — fast answers  
   - **Pro** — clarifying questions → research → citations → follow-ups  
   - **Adaptive** — balanced multi-step research  
   - **Deep** — multi-source report, **Sources** strip, dig-deeper follow-ups  
   - Download icon under an answer exports Markdown (+ sources)  
   - Model picker shows **Local** (Ollama) on sovereign installs  
6. **Spaces** → create a space  
   - **Settings → SKILL.md** — upload personality or use template  
   - **Settings → Productivity**  
     - **Vault** — paste policies/contracts  
     - **Memory** — durable facts  
     - **Skill packs** — Apply “Compliance Reviewer” etc.  
     - **Approvals** — approve agent write proposals  
     - **Jobs / Canvas / Tabular / Digest / Flags** as needed  
7. Start a **space chat** and ask a real work question  

Setup progress API (signed-in): `GET /api/knonix/setup-checklist`  
Health: `GET /api/knonix/health`  

Full product reference: **[FEATURES.md](./FEATURES.md)**

---

## Pinning a version & updates

```bash
# .env
KNONIX_IMAGE_TAG=v1.2.0
```

```bash
git pull
docker compose pull
docker compose up -d
```

Data lives in Docker volumes and is **preserved**. Migrations run on startup.
Prefer version tags over `latest` in production.

With HTTPS:

```bash
docker compose -f docker-compose.yml -f docker-compose.proxy.yml pull
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

Or simply re-run `./install.sh`.

---

## Frontier APIs (optional, non-sovereign)

```bash
KNONIX_ALLOW_FRONTIER=true
# OPENAI_API_KEY=...  ANTHROPIC_API_KEY=...  GROK_API_KEY=...
```

**Off by default.** Enabling sends data outside your boundary.

---

## Disk maintenance

```bash
./scripts/disk-maintenance.sh
./scripts/disk-maintenance.sh --prune
docker compose exec ollama ollama list
```

See [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md).

---

## OAuth redirect URIs

When `KNONIX_DOMAIN` is set, the installer configures public URLs for callbacks.

**M365 connectors:**

```text
https://<KNONIX_DOMAIN>/api/knonix/connectors/microsoft/callback
```

**SSO (Entra / Google):**

```text
<NEXT_PUBLIC_SUPABASE_URL>/auth/v1/callback
```

---

## Common commands

```bash
docker compose ps
docker compose logs -f knonixai
docker compose down                 # stops stack; keeps volumes
docker compose pull && docker compose up -d
./scripts/verify-install.sh
```

---

## Documentation index

| File | Contents |
|------|----------|
| [EASY_SETUP.md](./EASY_SETUP.md) | Non-technical 3-step install |
| [FEATURES.md](./FEATURES.md) | Product features (Spaces, productivity, connectors, admin) |
| [INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md) | Full `.env` reference |
| [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md) | Hardware sizing |
| [.env.example](./.env.example) | Annotated config template |

Source product docs (developers): [knonix/KnonixAI](https://github.com/knonix/KnonixAI) → `docs/`

---

## Support

- Access / licensing / offline licenses: **sales@knonix.com**
