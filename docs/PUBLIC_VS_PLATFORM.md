# Public installs vs Knonix platform (fleet & billing)

This document is the source of truth for **who can see what**.

## Two different roles

| Role | What they run | What they can see |
|------|----------------|-------------------|
| **Customer** (public) | Local KnonixAI stack via `./install.sh` | Only **their** install: chat, `/admin` for **their** users/models, local free seats |
| **Knonix** (software owner) | Platform host (`ai.knonix.com`) via `./scripts/platform-up.sh` | **All** enrolled customer installs + **active user / seat counts** for billing |

Customers **must not** receive fleet-admin credentials, the fleet board, or unlimited platform-owner seats.

---

## Customer (public) install

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install
./install.sh
```

**Compose files used**

- `docker-compose.yml` — app, Ollama, Postgres, Redis, SearXNG, optional auth, heartbeat-cron  
- `docker-compose.proxy.yml` — Caddy for HTTPS on **their** domain  

**Never applied by `./install.sh`**

- `docker-compose.platform.yml`  
- `Caddyfile.platform`  
- `platform/license-service`  

**Env posture (enforced by installer)**

| Variable | Customer value |
|----------|----------------|
| `KNONIX_PLATFORM_OWNER` | `false` (forced) |
| `KNONIX_PLATFORM_MODE` | `sovereign` |
| `KNONIX_LICENSE_ADMIN_TOKEN` | **empty** (stripped if present) |
| `KNONIX_LICENSE_MODE` | `connected` \| `free` \| `offline` |
| `KNONIX_LICENSE_SERVICE_URL` | `https://ai.knonix.com` when connected |
| `KNONIX_LICENSE_SERVICE_TOKEN` | Enrollment token from Knonix (optional) |

### What leaves a customer machine (connected mode only)

Daily heartbeat to Knonix — **privacy-preserving**:

- Opaque install / instance hash  
- License key  
- **Active user (seat) count**  
- Software version  
- Timestamp  

**Never** in the heartbeat: prompts, documents, chat history, user names/emails, or file contents.

### Local admin customers *do* get

- `https://<their-domain>/admin` — **their** org only (members, models, connectors, local license status)  
- Local free seats (`KNONIX_FREE_SEATS`, default 1)  

They **do not** get:

- `https://ai.knonix.com/admin/fleet`  
- Other customers’ installs  
- Knonix billing console  
- Ability to set `KNONIX_PLATFORM_OWNER=true` via the public installer  

---

## Knonix platform host (owner)

```bash
# On the Knonix-operated server only
sudo ./scripts/platform-up.sh
```

**Extra services**

- `platform/license-service` — central registry of licenses + heartbeats  
- Caddy routes (via `Caddyfile.platform`):  
  - `/v1/*` — customer enrollment / heartbeat / validate  
  - `/admin/fleet` — **operator login required** (`KNONIX_LICENSE_ADMIN_TOKEN`)  
  - `/v1/licenses`, `/v1/billing-summary` — admin bearer only  

**License service is bound to `127.0.0.1` on the host** (plus Docker network). It is not published on the public DMZ interface; public traffic goes through Caddy only.

### Billing visibility

Fleet board and `GET /v1/billing-summary` (admin token) show:

| Metric | Meaning |
|--------|---------|
| Installs enrolled | Customer sites that registered / heartbeated |
| Heartbeats (24h) | Installs that reported recently |
| Active users (all) | Sum of seat counts from last heartbeats |
| Billable over free seats | `max(0, active_users − free_seats)` per install, summed |
| Paid seats granted | Seats already attached via Stripe / provision |

Use these numbers to bill companies for **users beyond the free tier**.

### Operator secrets (never put in customer `.env` or public docs with real values)

| Secret | Who has it |
|--------|------------|
| `KNONIX_LICENSE_ADMIN_TOKEN` | Knonix operators only |
| Shared `KNONIX_LICENSE_SERVICE_TOKEN` | Knonix issues to customers (enrollment); customers use outbound only |
| Stripe keys | Knonix platform host only |

---

## Security checklist

**Customer machine**

- [ ] `./install.sh` only (no `platform-up.sh`)  
- [ ] `KNONIX_PLATFORM_OWNER=false`  
- [ ] No `KNONIX_LICENSE_ADMIN_TOKEN`  
- [ ] Optional enrollment token only if they agreed to connected billing  

**Knonix platform**

- [ ] Strong `KNONIX_LICENSE_ADMIN_TOKEN`  
- [ ] Fleet page requires login (not world-readable)  
- [ ] License service port not open on `0.0.0.0`  
- [ ] Stripe webhook secret set in production  

---

## Diagram

```text
┌─────────────────────────────┐         heartbeat (seats only)
│  Customer site A            │ ────────────────────────────────┐
│  install.sh + local models  │                                 │
│  /admin  (their users only) │                                 ▼
└─────────────────────────────┘                      ┌──────────────────────┐
                                                     │  ai.knonix.com       │
┌─────────────────────────────┐                      │  license-service     │
│  Customer site B            │ ── heartbeat ──────► │  /admin/fleet (auth) │
│  same public package        │                      │  billing summary     │
└─────────────────────────────┘                      │  Knonix operators    │
                                                     └──────────────────────┘
```
