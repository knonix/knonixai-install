# Audit fixes — complete status

Scope: **knonixai-install** (image-only installer). App prompt/SSE/RAG internals
live in `ghcr.io/knonix/knonixai` and are only partially adjustable via env +
`scripts/knonix-entrypoint.sh`.

Last updated: 2026-07-17 (this host).

## Fix table (audit §6.1)

| ID | Status | Implementation |
| -- | ------ | -------------- |
| **P0-1** GPU | **Done** | `docker-compose.gpu.yml`; `install.sh` / `platform-up.sh` auto-attach when `nvidia-smi` works. CPU/Mac: no GPU (expected). |
| **P0-2** SearXNG + heartbeat + preflight | **Done** | `searxng/settings.yml`, `scripts/heartbeat-cron.sh`, `scripts/preflight-mounts.sh` |
| **P0-3** Offline heartbeat | **Done** | `heartbeat-cron` → `profiles: [connected]`; `scripts/airgap-mode.sh`; gov cloud → prefer offline |
| **P0-4** Non-thinking default | **Done** | Default `qwen2.5:3b` / profile; entrypoint **strip-think-tags** for `<think>` |
| **P1-1** Context size | **Done** | low 2048 / medium 4096 / **high 8192**; entrypoint removes image min-2048 floor → min 512 |
| **P1-2** Healthchecks | **Done** | Ollama + knonixai; `depends_on: service_healthy` |
| **P1-3** Parallel / loaded models | **Done** | Defaults 1/1; high profile 2/2; finite `KEEP_ALIVE` on low/medium |
| **P1-4** Ports / Redis / DB TLS | **Done** | Loopback ports; **REDIS_PASSWORD** + requirepass; **scripts/gen-db-tls.sh** + **enable-db-tls.sh** |
| **P1-5** Signup | **Done** | Public domain → `KNONIX_AUTH_DISABLE_SIGNUP=true` by default |
| **P1-6** Customer Caddy fleet | **Done** | Fleet only in `Caddyfile.platform` |
| **P2-1** Doc drift | **Done** | `.env.example`, `INSTALL_SETTINGS.md`, compose aligned |
| **P2-2** Air-gap pull | **Done** | `scripts/airgap-mode.sh` → `pull_policy=never` + offline |
| **P2-3** JWT expiry | **Done** | Default **365 days** (`KNONIX_AUTH_JWT_TTL_DAYS`) |
| **§5.5** Weak postgres default | **Done** | Refuses `knonixai` / `change-me-in-production` |
| **Sampling env** | **Done** | `OLLAMA_TEMPERATURE` / `TOP_P` / `REPEAT_PENALTY` wired (image already reads them) |
| **Waiting UX** | **Done** | Single **Working** status |
| **Test space** | **Done** | Collab Verify removed |

## Image-source residual (cannot fully close without app repo)

| Item | What we did | Remaining |
| ---- | ----------- | --------- |
| Chat templates | Prefer instruct models | Native template QA needs app tests |
| History trim | Larger ctx on GPU/high | Summarize-vs-drop policy is image code |
| SSE token render | Caddy `flush_interval -1` | Frontend cursor polish is image UI |
| RAG top-k / budget | Context larger on high | Chunker/rerank in image |
| System prompt | — | Image product work |
| Space ACL UI | Org-wide share + DB trigger | Right-click members UI in image |
| GHCR publish | Local image + scripts ready | Needs your `GITHUB_TOKEN` |

## Verify on this host

```text
app=healthy  home=200  model=qwen2.5:3b
redis: NOAUTH without password; PONG with REDIS_PASSWORD
entrypoint: waiting-status-simple, ollama-num-ctx-floor, strip-think-tags
spaces: Knonix Corp only
```

## Operator commands

```bash
# Security / air-gap
./scripts/airgap-mode.sh
./scripts/enable-db-tls.sh   # optional Postgres SSL

# Speed profile
./scripts/optimize-cpu-speed.sh low|medium|high

# Publish (still needs token)
export GITHUB_TOKEN=ghp_… GHCR_USER=knonix
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
./scripts/push-release.sh
```
