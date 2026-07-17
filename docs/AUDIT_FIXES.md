# Audit fixes (installer repo)

This repo is the **image-only installer**. Chat prompt templates, SSE render, and
sampling live inside `ghcr.io/knonix/knonixai` and are only partially improvable
via env vars + `scripts/knonix-entrypoint.sh` runtime patches.

## Status vs. external audit recommendations

| ID | Recommendation | Status | Where |
| -- | -------------- | ------ | ----- |
| P0-1 | GPU for Ollama | **Done** | `docker-compose.gpu.yml`; `install.sh` auto-adds when `nvidia-smi` works |
| P0-2 | Ship SearXNG settings + heartbeat | **Done** (already present) | `searxng/settings.yml`, `scripts/heartbeat-cron.sh`, `scripts/preflight-mounts.sh` |
| P0-3 | Offline/gov heartbeat off by default option | **Done** | `heartbeat-cron` uses `profiles: [connected]`; set `KNONIX_LICENSE_MODE=offline` |
| P0-4 | Non-thinking default model | **Done** | Default `qwen2.5:3b` / hardware profile; not `qwen3:8b` |
| P1-1 | Context sizing | **Done** (profile-based) | low 1536 / medium 2048 / high 4096 via `hardware-profile.sh` |
| P1-2 | Healthchecks ollama + app | **Done** | `docker-compose.yml` healthcheck + `depends_on: service_healthy` |
| P1-3 | NUM_PARALLEL / MAX_LOADED | **Done** | Defaults `1` / `1` |
| P1-4 | Loopback ports | **Done** | Postgres/Redis/Ollama/Kong/app on `127.0.0.1` |
| P1-5 | Signup control for domain | **Documented + tip** | `KNONIX_AUTH_DISABLE_SIGNUP` |
| P1-6 | Caddy license routes on customers | **Done** | Customer `Caddyfile` has no `/v1` fleet routes; only `Caddyfile.platform` |
| P2-1 | Doc drift | **Done** | `INSTALL_SETTINGS.md` aligned |
| P2-2 | Pin digest / pull policy | **Partial** | Documented; set `KNONIX_IMAGE_TAG` + `KNONIX_IMAGE_PULL_POLICY=never` for air-gap |
| UX | Waiting status noise | **Done** | entrypoint `waiting-status-simple` |
| UX | Test space “Collab Verify” | **Done** (deleted from DB) | — |
| Mac | MacBook / nested VM profile | **Done** | `docs/MACOS.md`, virt-aware profile |

## Image-source items (need GHCR app source / next image build)

- Chat template correctness and `<think>` stripping for Qwen3
- History trim when context overflows
- Sampling temperature/top_p per model
- RAG top-k / chunk budget
- Space permissions UI (right-click members) — schema supports roles; UI/API in image
- Token-level SSE already proxied correctly in `Caddyfile` (`flush_interval -1`)

## os-june (https://github.com/open-software-network/os-june) takeaways

Useful product ideas (not a drop-in code merge — June is a Tauri desktop app):

1. **Privacy-tier labels on models** (local / private / frontier) — we should surface
   sovereign vs frontier clearly in Admin (image work).
2. **Local-first defaults** — already our posture; keep frontier off by default.
3. **Opt-in telemetry only** — our heartbeat is already optional via `offline` mode;
   never enable for CUI without ATO.
4. **Activity HUD / clear agent status** — simplified waiting label toward that UX.
5. **Pinned image digests + verify page** — matches our `check-updates` / release tags.

## Apply on this host

```bash
cd /home/knonix/knonixai-install
bash scripts/preflight-mounts.sh
# platform host:
docker compose -f docker-compose.yml -f docker-compose.proxy.yml \
  -f docker-compose.platform.yml -f docker-compose.fix-health.yml \
  --profile auth --profile connected up -d
./scripts/optimize-cpu-speed.sh low   # Mac VM
./scripts/verify-install.sh
```

## Publish reminder

GHCR `:latest` is **not** updated until you authenticate and run:

```bash
export GITHUB_TOKEN=ghp_…   # repo + write:packages
export GHCR_USER=knonix
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
./scripts/push-release.sh
# or: PUSH=true ./scripts/release.sh
```
