# KnonixAI — Installer

Self-host **KnonixAI** from the prebuilt container image. Sovereign AI search
and assistant for U.S. Government and regulated environments — local
open-weight models run inside your boundary, so your data never has to leave.

> This installer pulls a **prebuilt public image** from the GitHub Container
> Registry (GHCR). You do **not** need access to the KnonixAI source code, and
> **no token or login is required** to pull the image.

## Prerequisites

- **Docker + Docker Compose v2** (`docker compose version`)
- **~15–20 GB free disk** for the default local models
- **(Optional) NVIDIA GPU + `nvidia-container-toolkit`** for GPU-accelerated
  local inference (uncomment the `deploy` block under the `ollama` service in
  `docker-compose.yml`)

## Quick start

```bash
# 1. Get this installer (public repo — no source access needed)
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install

# 2. Configure
cp .env.example .env
# Edit .env: set POSTGRES_PASSWORD, and license values if you have them.

# 3. Bring up the stack (no login required — the image is public)
./install.sh
```

The script pulls `ghcr.io/knonix/knonixai`, starts the full stack, and pulls
the default local models. When it finishes:

- App: <http://localhost:3000>
- Admin dashboard: <http://localhost:3000/admin>

### Manual pull (without the script)

```bash
docker compose pull
docker compose up -d
```

### Private image?

If Knonix has provisioned a **private** image for your organization, pass the
access token Knonix gave you (a GHCR token with `read:packages`):

```bash
GHCR_USER=<your-github-username> GHCR_TOKEN=<token-from-knonix> ./install.sh
```

## Pinning a version

Set `KNONIX_IMAGE_TAG` in `.env` to a specific release for reproducible
deployments:

```bash
KNONIX_IMAGE_TAG=v1.2.0
```

Leave it as `latest` to always pull the newest published image.

## Licensing & seats

KnonixAI is **free for 2 active seats**. Beyond that, per-seat licensing
applies ($40 / seat / month). A seat = a user active in the last 30 days.

- **Connected mode** — the install sends a periodic, privacy-preserving
  heartbeat to the Knonix License Service (`https://ai.knonix.com`) so seats are
  metered and billed. Set `KNONIX_LICENSE_MODE=connected` plus the
  `KNONIX_LICENSE_*` values in `.env` (provided by Knonix).
- **Offline / air-gapped mode** — no connectivity. Validates a signed license
  token locally. For **3+ seats offline**, contact **sales@knonix.com** to
  purchase an on-premises offline license.

The heartbeat payload contains **no PII** — only an opaque install hash, the
license key, an integer seat count, and a version string. You can preview
exactly what would be sent:

```bash
curl -H "Authorization: Bearer $KNONIX_HEARTBEAT_SECRET" \
  http://localhost:3000/api/knonix/heartbeat
```

## Frontier APIs (optional, non-sovereign)

Anthropic / OpenAI / Grok / Google are **off by default**. Enabling them sends
data outside your boundary. Set `KNONIX_ALLOW_FRONTIER=true` and the relevant
API key in `.env` only where your compliance boundary allows it.

## Common commands

```bash
docker compose ps                 # service status
docker compose logs -f knonixai   # app logs
docker compose down               # stop the stack (keeps data volumes)
docker compose pull && docker compose up -d   # upgrade to the latest image
```

## Support

- Access / licensing / on-prem offline licenses: **sales@knonix.com**
