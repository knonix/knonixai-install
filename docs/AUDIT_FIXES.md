# Audit implementation status (knonixai-install)

Implements the P0–P2 installer checklist. App-source items remain out of scope.

## Acceptance

| Check | Result |
| ----- | ------ |
| `docker compose config` (base, auth, connected, proxy, gpu, platform) | Pass |
| Preflight fails if `searxng/settings.yml` deleted | Pass |
| Secrets not committed | `.env` / `secrets/` gitignored |
| Live host | app healthy, home 200 (after recreate) |

## P0–P2 map

| # | Item | Status |
| - | ---- | ------ |
| 1 | GPU overlay + install auto-detect + `KNONIX_GPU` + CPU warning | Done |
| 2 | SearXNG settings, heartbeat, verify/migrate/disk scripts, preflight | Done |
| 3 | Default `offline`; heartbeat `profiles: [connected]`; opt-in token | Done |
| 4 | Default instruct `qwen2.5:7b` (compose); CPU/low profile `qwen2.5:3b` | Done |
| 5 | `OLLAMA_NUM_CTX=8192`, `NUM_PREDICT=4096` defaults | Done |
| 6 | Healthchecks + `service_healthy` for ollama | Done |
| 7 | `PARALLEL=2`, `MAX_LOADED=2`, `KEEP_ALIVE=30m` | Done |
| 8 | Loopback ports + Redis password | Done |
| 9 | `DISABLE_SIGNUP=true`, `AUTOCONFIRM=false`, bootstrap owner prompts | Done |
| 10 | Customer Caddy has no license-service routes | Done |
| 11 | Docs aligned | Done |
| 12 | `pull_policy=missing`; pin via `KNONIX_IMAGE_TAG` | Done |
| 13 | JWT TTL 1 year (`KNONIX_AUTH_JWT_TTL_DAYS`) | Done |

## App image residual (not this repo)

Chat templates, SSE cursor polish, history summarize, RAG top-k, system prompt,
Space ACL UI — require `ghcr.io/knonix/knonixai` source. Runtime patches in
`scripts/knonix-entrypoint.sh` cover waiting UX, num_ctx floor, think-strip.

## Publish

```bash
export GITHUB_TOKEN=… GHCR_USER=knonix
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
./scripts/push-release.sh
git push origin main
```
