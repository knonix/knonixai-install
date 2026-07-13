# Platform components (Knonix operators only)

This directory is **not** part of a customer install path.

| Path | Purpose |
|------|---------|
| `license-service/` | Central license + heartbeat registry + fleet/billing board |

## Who uses this

- **Knonix** on `ai.knonix.com` via `../scripts/platform-up.sh`  
- **Not** customers running `../install.sh`

Customers only **call** the public HTTPS endpoints on the platform host with an
enrollment token. They never run this service against Knonix production data.

See **[../docs/PUBLIC_VS_PLATFORM.md](../docs/PUBLIC_VS_PLATFORM.md)**.
