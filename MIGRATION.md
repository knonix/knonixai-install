# Migrate KnonixAI to another machine

Move a full install (users, chats, models, TLS certs, config) from one host to a
faster machine with more CPU/RAM/GPU.

**Script:** [`./scripts/migrate.sh`](./scripts/migrate.sh)  
**Also see:** [SYSTEM_REQUIREMENTS.md](./SYSTEM_REQUIREMENTS.md) · [INSTALL_SETTINGS.md](./INSTALL_SETTINGS.md)

---

## What gets moved

| Piece | Contents |
| ----- | -------- |
| **Install config** | `.env`, `secrets/`, compose files, `Caddyfile`, scripts |
| **`knonixai_postgres_data`** | Auth users, chats, orgs, knowledge/RAG |
| **`knonixai_ollama_data`** | Local LLM weights (often the largest volume) |
| **`knonixai_caddy_data`** | Let’s Encrypt certificates |
| **`knonixai_knonix_workspaces`** | Code workspace files |
| **`redis` / `searxng` / `caddy_config`** | Cache, search state, Caddy config |

Compose project name is **`knonixai`** → Docker volumes are named `knonixai_*`.

---

## Recommended target hardware

| Goal | CPU | RAM | Disk |
| ---- | --- | --- | ---- |
| Smoother team / CMMC use | **16+ vCPU** | **64 GB** | **200+ GB** NVMe |
| Fast local models | 16–32 cores | 64–128 GB | 300+ GB + **NVIDIA 16–24 GB** GPU |

On the new host you can raise inference budgets, for example:

```bash
OLLAMA_NUM_CTX=8192
OLLAMA_NUM_PREDICT=3072
```

---

## Quick path (script)

### 1. Old (source) host

```bash
cd /path/to/knonixai-install

# See volume sizes (Ollama is often tens of GB)
./scripts/migrate.sh list-volumes

# Full backup — stops the stack for a consistent Postgres snapshot
./scripts/migrate.sh export ~/knonix-backup

# Smaller backup (re-pull models on the new host):
# ./scripts/migrate.sh export ~/knonix-backup --skip-ollama
```

Copy the backup (contains secrets — use a private channel):

```bash
rsync -avP ~/knonix-backup/ user@NEW_HOST:/tmp/knonix-backup/
```

### 2. New (target) host — prerequisites

```bash
# Ubuntu/Debian example
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin curl git openssl
sudo usermod -aG docker "$USER"   # log out and back in
```

Ensure enough free disk for Docker data (models + Postgres + images).

### 3. New host — restore and start

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install

./scripts/migrate.sh import /tmp/knonix-backup
```

**Review `.env` before starting:**

| Setting | Guidance |
| ------- | -------- |
| `KNONIX_DOMAIN` / `KNONIX_PUBLIC_URL` | Keep if DNS will point here; update if domain changes |
| `KNONIX_IMAGE_TAG` | Prefer `latest` or a version tag (rebuild if you used `:local`) |
| `OLLAMA_NUM_CTX` / `OLLAMA_NUM_PREDICT` | Raise on larger RAM/CPU |
| **Customer install** | `KNONIX_PLATFORM_MODE=sovereign`, `KNONIX_PLATFORM_OWNER=false` — **do not** set `KNONIX_LICENSE_ADMIN_TOKEN` |
| **Knonix platform host only** (`ai.knonix.com`) | Keep `KNONIX_PLATFORM_MODE=cloud`, `KNONIX_PLATFORM_OWNER=true`, and platform admin token |

```bash
# Pull image if needed
docker pull "ghcr.io/knonix/knonixai:${KNONIX_IMAGE_TAG:-latest}"

# HTTPS domain mode
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d

# Or local only (no domain):
# docker compose -f docker-compose.yml up -d

./scripts/verify-install.sh
curl -fsS "https://YOUR_DOMAIN/api/knonix/health"   # or http://localhost:3000/...
```

### 4. DNS cutover

1. Point the domain **A/AAAA** record at the **new** public IP.  
2. Open inbound **80** and **443**.  
3. Confirm HTTPS health and login.  
4. Only after the new host is stable, decommission the old volumes.

Delete the backup directory when migration is confirmed (it includes `.env` and secrets).

---

## Script reference

```bash
./scripts/migrate.sh help
./scripts/migrate.sh list-volumes
./scripts/migrate.sh export <dir> [--skip-ollama] [--keep-running]
./scripts/migrate.sh import <dir> [--skip-ollama]
```

| Flag | Meaning |
| ---- | ------- |
| `--skip-ollama` | Do not export/import model weights; re-pull with Ollama on the new host |
| `--keep-running` | Export without stopping containers (faster, riskier for Postgres) |

Export writes:

- `MANIFEST.txt` — hostname, domain, image tag snapshot  
- `config/install-config.tgz` — install tree  
- `volumes/knonixai_*.tgz` — each volume  
- `knonix-migrate-bundle.tgz` — single archive of the above  

---

## Config-only alternative (smaller transfer)

If the full backup is too large:

1. Export with `--skip-ollama`, **or** copy only install dir + `postgres_data` (+ `caddy_data` for certs).  
2. On the new host, start the stack and pull models:

```bash
docker compose exec ollama ollama pull qwen3:8b
docker compose exec ollama ollama pull nomic-embed-text
```

Users and chats are preserved; first model pull takes time.

---

## Platform vs customer (security)

| Capability | Customer local install | Knonix platform host |
| ---------- | ---------------------- | -------------------- |
| Chat / Spaces / your data | Yes | Yes |
| Fleet board (all customer installs) | **No** | **Yes** (`@knonix.com` + cloud mode) |
| Unlimited seats | **No** | **Yes** (`KNONIX_PLATFORM_OWNER=true`) |

**Never** copy the platform `.env` (with `KNONIX_PLATFORM_MODE=cloud`, `KNONIX_PLATFORM_OWNER=true`, or `KNONIX_LICENSE_ADMIN_TOKEN`) onto a pure customer machine. Fleet stays off when mode is `sovereign` (the installer default).

---

## After migration checklist

- [ ] `./scripts/verify-install.sh` passes  
- [ ] Health: `/api/knonix/health` → `status: ok`  
- [ ] Existing users can sign in  
- [ ] Chat works; `docker compose exec ollama ollama list` shows models  
- [ ] HTTPS valid (if using a domain)  
- [ ] M365 / SSO redirect URIs still match `KNONIX_DOMAIN`  
- [ ] Fleet/heartbeat OK **only if** this remains the platform host  
- [ ] Backup deleted or stored encrypted offline  

---

## Troubleshooting

| Problem | Fix |
| ------- | --- |
| Import: volume name missing | Keep compose project name `knonixai` (see `name: knonixai` in `docker-compose.yml`) |
| Image `:local` not found on new host | Set `KNONIX_IMAGE_TAG=latest` (or a release tag) and `docker pull` |
| Empty database after import | Re-run import; ensure stack was stopped and `knonixai_postgres_data.tgz` restored |
| HTTPS fails | DNS A/AAAA → new IP; ports 80/443 open; `docker compose … logs caddy` |
| Out of disk during export | Use `--skip-ollama` or free space; Ollama is usually the bulk of the backup |

---

## Support

Licensing / fleet enrollment tokens: **sales@knonix.com**
