# Changelog

All notable changes to the **KnonixAI installer** and the published customer
image (`ghcr.io/knonix/knonixai`) are listed here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)-style.  
Versioning: installer `VERSION` file + image tags `vX.Y.Z` and `latest`.

Check for updates on an install:

```bash
./scripts/check-updates.sh
```

---

## [1.6.2] — 2026-07-17

### Added
- Runtime quality patches: tool retries, lower search step caps, RAG topK 5, think-strip, Working-only wait UI.
- `scripts/publish-all.sh` for git + GHCR publish when PAT is available.

### Changed
- P0–P2 installer hardening (offline default, GPU overlay, healthchecks, Redis auth, JWT 1y).

---

## [1.6.1] — 2026-07-13

### Added
- **macOS / MacBook Pro guide** (`docs/MACOS.md`): Docker Desktop + Ubuntu-on-Mac VMs.
- Hardware profile detects nested VMs / Apple-hosted guests, leaves host CPU free, and
  defaults Mac/VM installs to interactive **3B** models (no Metal GPU in containers).
- Org-only Spaces collaboration (create-time share + membership trigger + sync script).
- Per-user session / Spaces checks in `verify-install.sh`.
- GHCR publish workflow (`.github/workflows/publish-ghcr.yml`).

### Fixed
- Space create only granted access to the creator; other org members could not list Spaces.
- Entrypoint org-share patch covered all minified schema aliases.
- Chat waiting UX: single **Working** status (no rotating Thinking/Preparing copy).
- Compose healthchecks for Ollama + app; app waits until Ollama is healthy.
- Customer app port bound to loopback; heartbeat-cron only with `--profile connected`.
- Preflight for SearXNG/heartbeat bind-mount sources; GPU overlay when NVIDIA present.
- Removed test Space “Collab Verify Space” from live DB (Knonix Corp remains).

### Upgrade notes
```bash
cd knonixai-install
git pull origin main
./scripts/check-updates.sh
docker compose pull
docker compose up -d
# optional backfill:
./scripts/sync-org-space-access.sh
```

---

## [1.6.0] — 2026-07-13

### Added
- **Per-user sessions** verified: GoTrue JWT `sub` + `session_id` are unique per login;
  private chats are scoped to `user_id` (API list never crosses users).
- **Org-only Spaces collaboration:** all *active* organization members can list/open
  shared Spaces; non-members get 403. New Spaces auto-share with the org on create
  (entrypoint patch). Existing Spaces backfilled via `scripts/sync-org-space-access.sh`
  and `init-org-space-share.sql` (trigger on membership activate).
- **Resources rail** (right side, collapsible): links, files, and sources for each chat.
- **Related follow-ups fallback** when local models skip ` ```spec ` blocks.
- **Changelog + update checker** (`CHANGELOG.md`, `VERSION`, `scripts/check-updates.sh`).
- **Release publisher** (`scripts/release.sh`) to version, build, and push GHCR images.
- Platform fleet/billing board with admin auth and seat rollups (operator host only).
- Hardware profile + low-CPU defaults for smooth installs on 8–16 GB hosts.

### Changed
- **Security:** Postgres, Redis, Ollama, SearXNG, and Kong bind to `127.0.0.1` only
  (Docker ports no longer bypass UFW on the WAN).
- **Thinking UI:** single bounce-dot indicator on the activity header (no per-step dots).
- **Customer posture:** `install.sh` forces `PLATFORM_OWNER=false`, strips admin token.
- **`.env` permissions:** created/maintained as mode `600`.
- Runtime entrypoint patches (auth health, URL prefetch, POAM office clamp, related,
  resources rail, thinking cleanup) applied on every container start and bakeable
  into published images.

### Fixed
- Health `authConfigured` false on public images (NEXT_PUBLIC inlined empty at build).
- URL chips not triggering page prefetch.
- Bare “POAM/SSP” incorrectly opening Word/office tools.
- Services not restarting after host reboot (`restart: unless-stopped`).
- Auth race on reboot (GoTrue before Postgres DNS ready).

### Upgrade notes
```bash
cd knonixai-install
git pull origin main
./scripts/check-updates.sh
docker compose pull
# customer:
docker compose -f docker-compose.yml -f docker-compose.proxy.yml --profile auth up -d
# then hard-refresh the browser
```

---

## [1.5.0] — 2026-07-08

### Added
- Public GHCR image install path; no source repo required for customers.
- Connected licensing heartbeats (privacy-preserving seat counts).
- Self-hosted auth (GoTrue + Kong), Caddy HTTPS overlay.

### Notes
- Baseline fleet-capable installer used by early platform hosts.
