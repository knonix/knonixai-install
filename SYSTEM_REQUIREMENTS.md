# KnonixAI — System Requirements

Sizing guide for sovereign self-hosted installs. Plan capacity for **Docker data**
(the partition where images, models, and database volumes live), not just the OS
root disk.

## Minimum (evaluation / single user)

| Resource | Minimum |
|----------|---------|
| **CPU** | 4 vCPU (x86_64 or ARM64) |
| **RAM** | 16 GB (32 GB recommended for 7B–8B models on CPU) |
| **Docker data disk** | **50 GB free** |
| **OS root disk** | 20 GB |
| **Network** | Outbound HTTPS for image pulls; ports 80/443 if using a public domain |

## Recommended (production / small team)

| Resource | Recommended |
|----------|-------------|
| **CPU** | 8+ vCPU |
| **RAM** | 32–64 GB |
| **Docker data disk** | **80–100 GB free** |
| **GPU** | Optional NVIDIA GPU + `nvidia-container-toolkit` for faster inference |

## Disk breakdown (typical install)

| Component | Approx. size | Notes |
|-----------|--------------|-------|
| Container images | 12–15 GB | Ollama image (~8 GB), KnonixAI app (~3 GB), Postgres, Redis, Caddy, Kong, GoTrue |
| Ollama models | 5–15 GB each | Default chat model + coding model + embed model; **each extra model adds ~5 GB** |
| Postgres + Redis + app data | 1–5 GB | Grows with chat history and knowledge index |
| Docker build cache | 0–10 GB | Accumulates when building images locally (`KNONIX_IMAGE_TAG=local`) |
| Headroom | 10+ GB | Required for pulls, upgrades, and temporary build layers |

**Example (this host's default stack):**

- `qwen2.5:7b` (~4.7 GB) — chat
- `qwen2.5-coder:7b` (~4.7 GB) — coding
- `nomic-embed-text` (~0.3 GB) — RAG embeddings
- **Total models ≈ 10 GB** (remove unused models to reclaim space)

A **30 GB Docker data partition fills up quickly** when you keep multiple 7B/8B
models, local image builds, and upgrade layers. **Use 50 GB minimum; 80 GB+ for
production.**

## Public URL / OAuth (per install)

The app process binds to `0.0.0.0:3000` inside Docker. Browsers and Microsoft/Google
OAuth never use that address. Each install must advertise its **public origin**:

| Variable | Purpose |
|----------|---------|
| `KNONIX_DOMAIN` | Your FQDN (e.g. `ai.customer.gov`) |
| `KNONIX_PUBLIC_URL` | Full public origin (`https://ai.customer.gov`) |
| `NEXT_PUBLIC_BASE_URL` | Same as above (absolute links in the app) |
| `KNONIX_AUTH_SITE_URL` | Post-login landing URL (set by `install.sh`) |

`install.sh` sets these automatically when `KNONIX_DOMAIN` is configured. **M365
connector redirect URI** (register in Entra):

```text
https://<KNONIX_DOMAIN>/api/knonix/connectors/microsoft/callback
```

Re-run `./install.sh` after changing domain, or recreate the `knonixai` container
so env vars apply.

## Docker data directory

If Docker stores data on a small volume (e.g. `/mnt/knonix-data`), either:

1. **Expand the data disk** (recommended for production), or
2. Run periodic maintenance: `./scripts/disk-maintenance.sh`

See [README.md — Disk maintenance](./README.md#disk-maintenance).

## Compliance / boundary notes

- **GCC High**: set `KNONIX_MS_CLOUD_ENVIRONMENT=gcc_high` and use Entra apps in
  the `.us` cloud. Register redirect URIs on the government endpoint.
- **Frontier APIs** (`KNONIX_ALLOW_FRONTIER=true`) send prompts outside your boundary.
  Off by default on sovereign installs.