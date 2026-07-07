# KnonixAI — Installer

Self-host **KnonixAI** from the prebuilt container image. Sovereign AI search
and assistant for U.S. Government and regulated environments — local
open-weight models run inside your boundary, so your data never has to leave.

> This installer pulls a **prebuilt public image** from the GitHub Container
> Registry (GHCR). You do **not** need access to the KnonixAI source code, and
> **no token or login is required** to pull the image.

## Prerequisites

- **Docker Engine** (`docker version`)
- **Docker Compose v2** — the `docker compose` **subcommand** (a space, not a
  hyphen). Check with `docker compose version`. If that errors with
  `unknown shorthand flag: 'd' in -d`, you have the old standalone
  `docker-compose` (v1) or no Compose plugin. Install v2 on Ubuntu/Debian:

  ```bash
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
  docker compose version   # should now print v2.x
  ```

  (If that package isn't found, add Docker's official apt repo first — see
  <https://docs.docker.com/engine/install/>.)

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

## Already pulled the image? Full step-by-step

If you ran something like `docker pull ghcr.io/knonix/knonixai:sha-559aa42`
yourself, that only downloads the **app image**. KnonixAI still needs the rest
of its stack (Postgres, Redis, Ollama, SearXNG) and a config file. Do this to
go from a bare pull to a running system:

```bash
# 1. Get this installer (it provides the compose file + config template)
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install

# 2. Create your config
cp .env.example .env

# 3. Edit .env — at minimum:
#      POSTGRES_PASSWORD=<a strong password>
#      KNONIX_IMAGE_TAG=<the tag you pulled, e.g. sha-559aa42 — or v1.0.0 / latest>
#    (A version tag like v1.0.0 or latest is recommended over a raw sha- tag.)

# 4. Start the whole stack (app + Postgres + Redis + Ollama + SearXNG)
docker compose up -d

# 5. Pull the default local models into Ollama (first run only; a few minutes)
docker compose exec ollama ollama pull llama3.1:8b
docker compose exec ollama ollama pull nemotron-mini:4b
docker compose exec ollama ollama pull nomic-embed-text
```

Database migrations run **automatically** the first time the `knonixai`
container starts — there is no manual migrate step.

When it finishes:

- App: <http://localhost:3000>
- Admin dashboard: <http://localhost:3000/admin> (pull more models, view seats)

> If you pulled a `sha-...` tag directly, set `KNONIX_IMAGE_TAG` to that same
> tag in `.env` so Compose runs the image you already downloaded. Otherwise
> Compose defaults to `latest` and will pull that instead.

### Verify it's running

```bash
docker compose ps                        # all services should be "running"/healthy
docker compose logs -f knonixai          # watch app startup + migrations
curl -fsS http://localhost:3000 >/dev/null && echo "KnonixAI is up"
docker compose exec ollama ollama list   # confirm the local models are present
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

## Updating KnonixAI

Updates ship as new container images — you pull the newer image and recreate
the app container. Your data (Postgres, Redis, Ollama models, SearXNG) lives in
named Docker volumes and is **preserved** across updates. Database schema
migrations run **automatically** when the new container starts.

**Update to the latest image:**

```bash
cd knonixai-install
git pull                                    # get any installer/compose changes
docker compose pull                         # fetch the newest image
docker compose up -d                        # recreate changed containers
```

**Update to a specific version** (recommended for production — reproducible):

```bash
# 1. Set the target release in .env
#    KNONIX_IMAGE_TAG=v1.1.0
# 2. Apply it
docker compose pull
docker compose up -d
```

**Confirm the new version is running:**

```bash
docker compose images knonixai            # shows the image tag now in use
docker compose logs -f knonixai           # watch startup + migrations
```

**Roll back** if an update misbehaves — pin `KNONIX_IMAGE_TAG` back to the
previous version in `.env`, then `docker compose pull && docker compose up -d`.
Because data is in volumes, rolling the image back does not lose chat history.

> **Tip:** run pinned version tags (e.g. `v1.1.0`) rather than `latest` in
> production so upgrades are deliberate and every host runs the same build.
> Before a major upgrade, back up the Postgres volume
> (`docker compose exec postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup.sql`).

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
