# Security, reliability & performance audit (platform host)

Date of last pass: 2026-07-13 (post-reboot hardening).

## Public attack surface (desired)

| Port | Service | Exposure |
|------|---------|----------|
| 22 | SSH | Public (required for ops) |
| 80 / 443 | Caddy → app | Public HTTPS |
| 5432 Postgres | Local only `127.0.0.1` | Not public |
| 6379 Redis | Local only | Not public |
| 11434 Ollama | Local only | Not public |
| 8080 SearXNG | Local only | Not public |
| 8000/8443 Kong | Local only | Not public |
| 8787 License | Local only | Not public |

**Why localhost bind matters:** Docker published ports on `0.0.0.0` can **bypass UFW** via the `DOCKER` iptables chain. Binding to `127.0.0.1` closes that hole.

## Security controls

| Control | Status |
|---------|--------|
| Auth required for chat | On (`ENABLE_AUTH=true`) |
| Fleet board without admin token | HTTP 401 |
| License service not on WAN | `127.0.0.1:8787` |
| Frontier APIs | Off by default |
| Customer installer strips platform owner + admin token | Yes |
| `.env` mode | `600` |
| `secrets/` mode | `700` + key files `600` |
| `.env` / secrets in git | Ignored, not tracked |
| Containers privileged | No |

## Performance (CPU host)

| Setting | Target |
|---------|--------|
| Chat model | `qwen2.5:3b` (keep warm) |
| Coding model | `qwen2.5:3b` on low-RAM hosts |
| `OLLAMA_MAX_LOADED_MODELS` | 1 |
| `OLLAMA_NUM_PARALLEL` | 1 |
| Context / predict | Tuned via hardware-profile / `.env` |
| Restart policy | `unless-stopped` on all services |

Unload large models when not needed:

```bash
docker exec knonixai-ollama-1 ollama stop qwen2.5-coder:7b
docker exec knonixai-ollama-1 ollama stop qwen3:8b
```

## Residual risks / recommendations

1. **SSH** — Prefer keys; disable password auth if keys are provisioned.  
2. **Stripe / Azure secrets in `.env`** — Rotate if ever committed or shared.  
3. **Permanent UI/source fixes** — Entrypoint patches re-apply on each start; bake into GHCR when possible.  
4. **UFW + Docker** — Keep internal ports on loopback even if UFW is “active”.  
5. **Backups** — Snapshot Postgres volume and license-service data regularly.

## Verify after changes

```bash
ss -lntp | grep -E ':(5432|6379|11434|8080|8000)\b'   # should show 127.0.0.1 only
curl -sk --resolve ai.knonix.com:443:127.0.0.1 https://ai.knonix.com/api/knonix/health
docker compose -f docker-compose.yml -f docker-compose.proxy.yml -f docker-compose.platform.yml --profile auth ps
```
