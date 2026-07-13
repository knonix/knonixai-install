# KnonixAI — Installer

Self-host **KnonixAI** from the prebuilt container image. Sovereign AI search
and assistant for U.S. Government and regulated environments — local
open-weight models run inside your boundary, so your data never has to leave.

> This installer pulls a **prebuilt public image** from the GitHub Container
> Registry (GHCR). You do **not** need access to the KnonixAI source code, and
> **no token or login is required** to pull the image.
>
> **Customer installs stay clean:** `./install.sh` never enables platform/fleet
> owner mode, never requires a `:local` image, and always verifies
> `/api/knonix/health` reports `ready=true` (including auth). See
> [image-build/README.md](./image-build/README.md) for how maintainers publish
> bug-free app images.

| Doc | Audience |
|-----|----------|
| **[GETTING_STARTED.md](./GETTING_STARTED.md)** | New users — doc map, first hour, day-1 prompts |
| **[EASY_SETUP.md](./EASY_SETUP.md)** | Non-technical install (3 steps + first-day checklist) |
| **[FEATURES.md](./FEATURES.md)** | Full product features (Spaces, SKILL.md, productivity, connectors, …) |
| **[COMPARISON.md](./COMPARISON.md)** | **Buyers — vs Copilot, ChatGPT, Claude, Glean, Perplexity, OpenClaw, Cursor** |
| **[docs/OPENSOURCE_LEARNINGS.md](./docs/OPENSOURCE_LEARNINGS.md)** | **Engineering — lessons from Open WebUI, LibreChat, AnythingLLM, Dify** |
| **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)** | **CMMC / DFARS / NIST mapping, readiness runbook, competitive matrix** |
| **[SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md)** | **Hardware tiers, GPU sizing, NVIDIA Jetson** |
| **[MIGRATION.md](./MIGRATION.md)** | **Move install to a larger host (`migrate.sh`)** |
| **[TERMS_OF_USE.md](./TERMS_OF_USE.md)** | **Legal terms — use at your own risk; liability limits** |
| **[PRIVACY_POLICY.md](./PRIVACY_POLICY.md)** | **Privacy — self-hosted data stays with you** |
| **[INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)** | Every `.env` setting explained |
| **[docs/PUBLIC_VS_PLATFORM.md](./docs/PUBLIC_VS_PLATFORM.md)** | **Public vs Knonix fleet — who sees installs & seats for billing** |
| **[CHANGELOG.md](./CHANGELOG.md)** | **What changed — upgrade notes for each version** |
| **[docs/PUSH_TO_GITHUB_AND_GHCR.md](./docs/PUSH_TO_GITHUB_AND_GHCR.md)** | Maintainers — reconnect GitHub / publish images |
| **[docs/SECURITY_AND_OPS_AUDIT.md](./docs/SECURITY_AND_OPS_AUDIT.md)** | Security surface and ops checklist |

**Current installer version:** see [`VERSION`](./VERSION) · check for updates: `./scripts/check-updates.sh`

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
  - **Edge / Jetson:** Orin NX **16 GB+** or AGX Orin (NVMe) — Orin Nano 8 GB is demo-only  
- **(Optional) NVIDIA GPU + `nvidia-container-toolkit`** for faster local inference
  (uncomment the `deploy` block under `ollama` in `docker-compose.yml`). ARM64 / Jetson images: pull `linux/arm64` tags.

---

## Quick start (recommended)

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
./install.sh
```

This pulls the **public** prebuilt image `ghcr.io/knonix/knonixai:latest` (no
source access, no login for the default package). Set `KNONIX_IMAGE_TAG` in
`.env` only if you need a pinned release.

**Customers never run** `docker-compose.platform.yml` or `scripts/platform-up.sh`.
Those are **Knonix-only** (fleet board + billing). Your public install is local
software only; if you paste an enrollment token, it **sends** optional seat
heartbeats to Knonix for accurate billing — you never access fleet/licensing
systems beyond your own `/admin`. Details: **[docs/PUBLIC_VS_PLATFORM.md](./docs/PUBLIC_VS_PLATFORM.md)**.

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

# Check for newer installer or app image
./scripts/check-updates.sh

# LLM tools check (research chat requires Ollama "tools" capability)
./scripts/verify-ollama-llms.sh --catalog

# Optional API chat smoke (creates an ephemeral test user)
./scripts/qa-chat-smoke.sh
```

### Stay updated (companies / operators)

When Knonix publishes a new installer or `ghcr.io/knonix/knonixai` image:

```bash
cd knonixai-install
git pull origin main
./scripts/check-updates.sh          # shows VERSION + image status
cat CHANGELOG.md | head -80         # what changed
docker compose pull
docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile auth up -d
# Hard-refresh the browser (Ctrl+Shift+R)
```

Maintainers publish with `./scripts/release.sh` (see **[docs/PUSH_TO_GITHUB_AND_GHCR.md](./docs/PUSH_TO_GITHUB_AND_GHCR.md)**).

**How knowledge works:** the app does not permanently retrain from chat. It uses
conversation context, **local RAG** (uploads), and Space **MEMORY.md / vault**.
For precise policy answers, upload source docs or share URLs. See
[docs/OPENSOURCE_LEARNINGS.md](./docs/OPENSOURCE_LEARNINGS.md).

**Important:** Models like **phi4:14b** only support completion — they **cannot** run search/connectors/research. Use **qwen3:8b** (default) or any tag where `ollama show <tag>` lists `tools`.

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
| `KNONIX_MODEL` | Optional | Default chat model (`qwen3:8b` tools-capable) |
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

## HTTPS web server (automatic)

`./install.sh` **auto-starts a Caddy reverse proxy** whenever `KNONIX_DOMAIN` is set.
You do **not** install nginx/Apache separately — the installer wires HTTPS for you.

### Enable production HTTPS

In `.env` (or answer the domain prompt during `./install.sh`):

```bash
KNONIX_DOMAIN=ai.example.com
KNONIX_ACME_EMAIL=admin@example.com
```

```bash
./install.sh
```

That will:

1. Write public URLs (`KNONIX_PUBLIC_URL`, `NEXT_PUBLIC_BASE_URL`) for OAuth callbacks  
2. Apply `docker-compose.proxy.yml` (Caddy on ports **80/443**)  
3. Obtain and renew **Let's Encrypt** certificates automatically  
4. Serve the app at `https://ai.example.com` (no `:3000` in the browser)

**Requirements:** DNS A/AAAA for the domain → this host; ports **80** and **443** open inbound.

```bash
docker compose -f docker-compose.yml -f docker-compose.proxy.yml logs caddy
./scripts/verify-install.sh   # checks Caddy + app health
```

| Mode | Config | Result |
|------|--------|--------|
| **Local only** | `KNONIX_DOMAIN` empty | `http://localhost:3000` (no Caddy) |
| **Local HTTPS** | `KNONIX_DOMAIN=localhost` | Caddy with internal CA |
| **Public HTTPS** | real FQDN + ACME email | Caddy + Let's Encrypt |

If you set a domain **after** the first install, re-run `./install.sh` — it re-syncs public URLs and brings Caddy up.

---

## Manual pull / compose-only path

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
cp .env.example .env
# Edit: POSTGRES_PASSWORD, optional domain + fleet token, KNONIX_IMAGE_TAG
docker compose up -d
docker compose exec ollama ollama pull qwen3:8b
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

## Migrate to another machine

**Full guide:** **[MIGRATION.md](./MIGRATION.md)** (hardware targets, DNS cutover, platform vs customer, troubleshooting).

```bash
# Old host
./scripts/migrate.sh list-volumes
./scripts/migrate.sh export ~/knonix-backup
rsync -avP ~/knonix-backup/ user@NEW_HOST:/tmp/knonix-backup/

# New host
git clone https://github.com/knonix/knonixai-install.git && cd knonixai-install
./scripts/migrate.sh import /tmp/knonix-backup
# review .env, then:
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
./scripts/verify-install.sh
```

Export stops the stack for a consistent Postgres snapshot. The backup includes secrets — delete it after cutover.
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

## How KnonixAI compares (summary)

| Capability | **KnonixAI** | Cloud assistants (Copilot / ChatGPT / Claude) |
|------------|--------------|-----------------------------------------------|
| **Default inference** | Local open-weight (Ollama) in **your** enclave | Vendor cloud |
| **Data sovereignty** | Yes by default | Tenant / third-party cloud |
| **CMMC / 800-171 readiness** | Built-in expert + domain matrix + SSP/POA&M drafts | Generic chat |
| **Air-gap / offline license** | Yes | No |
| **GCC High Graph** | Yes (`.us` routing) | Copilot only (M365-native) |

Full matrix (Glean, Perplexity, OpenClaw, Cursor, speed tradeoffs): **[COMPARISON.md](./COMPARISON.md)**.  
Compliance positioning: **[CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md)**.

---

## NVIDIA Jetson

**Yes — Jetson Orin can run KnonixAI** (Docker + ARM64 + Ollama GPU path).

| Device | Verdict |
|--------|---------|
| **Orin NX 16 GB+ / AGX Orin 32–64 GB** | Recommended edge platform |
| **Orin Nano 8 GB** | Demo / single-user only (lean compose) |
| **Older Xavier / Nano / TX2** | Not recommended for full stack |

Details, JetPack notes, and lean env profile: **[SYSTEM_REQUIREMENTS.md § NVIDIA Jetson](./SYSTEM_REQUIREMENTS.md#nvidia-jetson--can-it-run-knonixai)**.

---

## Documentation index

| File | Contents |
|------|----------|
| [GETTING_STARTED.md](./GETTING_STARTED.md) | Doc map, first hour, day-1 prompts, hardware glance |
| [EASY_SETUP.md](./EASY_SETUP.md) | Non-technical 3-step install |
| [FEATURES.md](./FEATURES.md) | Product features (Spaces, productivity, connectors, admin) |
| [COMPARISON.md](./COMPARISON.md) | Competitive matrix vs Copilot, ChatGPT, Claude, Glean, Perplexity, OpenClaw, Cursor |
| [CMMC_COMPLIANCE.md](./CMMC_COMPLIANCE.md) | CMMC/DFARS/NIST, SSP/POA&M, compliance competitive table |
| [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md) | Hardware tiers, disk, GPU, **Jetson** |
| [MIGRATION.md](./MIGRATION.md) | Move install to another host (`scripts/migrate.sh`) |
| [TERMS_OF_USE.md](./TERMS_OF_USE.md) | Terms of use — **AS IS**, no liability for data loss/breaches |
| [PRIVACY_POLICY.md](./PRIVACY_POLICY.md) | Privacy policy — customer-controlled self-hosted data |
| [INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md) | Full `.env` reference |
| [.env.example](./.env.example) | Annotated config template |

Source product docs (developers with private access): [knonix/KnonixAI](https://github.com/knonix/KnonixAI) → `docs/`

---

## Legal

By installing or using KnonixAI you agree to the **[Terms of Use](./TERMS_OF_USE.md)**.  
Privacy practices: **[Privacy Policy](./PRIVACY_POLICY.md)**.

**Summary (not a substitute for the full Terms):** KnonixAI is **self-hosted, use-at-your-own-risk software**. You are solely responsible for security, backups, compliance, and all Customer Data. **Knonix is not liable for data loss, security breaches, incorrect AI outputs, failed assessments, or consequential damages**, to the maximum extent permitted by law.

---

## Support

- Access / licensing / offline licenses: **sales@knonix.com**
