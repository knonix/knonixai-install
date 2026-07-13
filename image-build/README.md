# Publishing a customer-safe KnonixAI app image

Regular users pull `ghcr.io/knonix/knonixai:latest`. That image **must** report
`ready: true` with auth keys set only at **runtime** (via install `.env`).

## Bug this directory prevents

Next.js inlines `process.env.NEXT_PUBLIC_*` at **image build** time. If the
GHCR image is built without those vars, `/api/knonix/health` compiles to:

```js
authConfigured: !authEnabled || !!"".trim() && !!"".trim()  // always false
```

and every customer install shows **degraded** / “Supabase/GoTrue keys are missing”
even though `install.sh` correctly minted keys into `.env`.

## Fix in two layers

| Layer | What | Who |
|-------|------|-----|
| **Installer (already shipped)** | `scripts/knonix-entrypoint.sh` patches the health chunk at container start | All installs via `docker-compose.yml` |
| **Image (required for clean GHCR)** | Rebuild app from `knonix/KnonixAI` with the source fix below, **or** run `publish-fixed-image.sh` | Platform maintainers |

### Source fix (`knonix/KnonixAI`)

In `app/api/knonix/health/route.ts`, **never** use static
`process.env.NEXT_PUBLIC_…` for readiness. Use bracket access so Next does not
inline empty strings at build:

```ts
function runtimeEnv(name: string): string {
  return (process.env[name] ?? '').trim()
}

const hasSupabase =
  Boolean(runtimeEnv('NEXT_PUBLIC_SUPABASE_URL')) &&
  Boolean(runtimeEnv('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY'))
```

See `patches/health-route-runtime-env.ts` for a full reference copy.

### CI / Docker build rules

1. Do **not** require real Supabase URLs at `docker build` time for health.
2. Prefer the `runtimeEnv()` pattern for any **server-only** readiness checks
   that read `NEXT_PUBLIC_*`.
3. After publishing, smoke test on a **clean** host:

```bash
git clone https://github.com/knonix/knonixai-install.git
cd knonixai-install && ./install.sh
curl -fsS http://localhost:3000/api/knonix/health | jq .
# expect: "status":"ok", "ready":true, "checks.authConfigured":true
```

## Publish customer image (preferred)

From the **install repo root**:

```bash
# Requires: docker login ghcr.io  (write:packages)
PUSH=true ./scripts/release.sh          # uses VERSION file
# or bump first:
PUSH=true ./scripts/release.sh 1.6.1
```

This:

1. Builds `FROM ghcr.io/knonix/knonixai:latest` (or local base)
2. Bakes health auth fix + full `knonix-entrypoint.sh` into the image
3. Tags `vX.Y.Z`, `latest`, and `installer-X.Y.Z`
4. Pushes when `PUSH=true`

Back-compat: `./image-build/publish-fixed-image.sh` calls `scripts/release.sh`.

Also update **CHANGELOG.md** and push the installer repo so
`./scripts/check-updates.sh` can notify customers.

## Customer path (must stay clean)

`./install.sh` must **never** apply:

- `docker-compose.platform.yml`
- `Caddyfile.platform`
- `KNONIX_PLATFORM_OWNER=true` / `KNONIX_PLATFORM_MODE=cloud`

Those are only for the Knonix fleet host via `scripts/platform-up.sh`.
