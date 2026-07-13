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

## [1.6.0] — 2026-07-13

### Added
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
