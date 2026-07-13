/**
 * REFERENCE FIX for knonix/KnonixAI — app/api/knonix/health/route.ts
 *
 * Copy the runtimeEnv + hasSupabase logic into the main app repo and rebuild
 * the GHCR image so customers do not depend on the install entrypoint patch.
 *
 * Why: Next.js replaces process.env.NEXT_PUBLIC_* with string literals at
 * build time. Empty build-time values permanently break authConfigured.
 */
import { DEFAULT_MODEL } from '@/lib/config/default-model'
import {
  isFleetLicensingConfigured,
  resolveLicenseKey
} from '@/lib/knonix/fleet-license'
import { getOrCreateInstallIdentity } from '@/lib/knonix/instance-id'
import { resolveBillableSeats } from '@/lib/knonix/seats'
import { isFrontierAllowed, isSovereignProvider } from '@/lib/utils/registry'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** Bracket access — not inlined by Next at build time. */
function runtimeEnv(name: string): string {
  return (process.env[name] ?? '').trim()
}

export async function GET() {
  const ollamaBase = runtimeEnv('OLLAMA_BASE_URL')
  let ollamaReachable = false
  let installedModels: string[] = []
  if (ollamaBase) {
    try {
      const res = await fetch(`${ollamaBase.replace(/\/+$/, '')}/api/tags`, {
        cache: 'no-store',
        signal: AbortSignal.timeout(2500)
      })
      if (res.ok) {
        ollamaReachable = true
        const data = (await res.json()) as {
          models?: Array<{ name?: string }>
        }
        installedModels = (data.models ?? [])
          .map(m => m.name || '')
          .filter(Boolean)
      }
    } catch {
      ollamaReachable = false
    }
  }

  const authEnabled = runtimeEnv('ENABLE_AUTH') !== 'false'
  // Server readiness must use runtimeEnv (not process.env.NEXT_PUBLIC_X).
  const hasSupabase =
    Boolean(runtimeEnv('NEXT_PUBLIC_SUPABASE_URL')) &&
    Boolean(runtimeEnv('NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY'))
  const fleetConfigured = isFleetLicensingConfigured()
  const heartbeatEnabled = Boolean(runtimeEnv('KNONIX_HEARTBEAT_SECRET'))
  const licenseMode = (runtimeEnv('KNONIX_LICENSE_MODE') || 'free').toLowerCase()

  let licenseKeyPresent = false
  let fleetRegistered = false
  let activeSeats = 0
  try {
    licenseKeyPresent = Boolean(await resolveLicenseKey())
    const identity = await getOrCreateInstallIdentity()
    fleetRegistered = Boolean(
      identity.fleetRegisteredAt || identity.licenseKey?.trim()
    )
    activeSeats = await resolveBillableSeats()
  } catch {
    // DB may still be migrating on first boot — health stays "degraded"
  }

  const checks = {
    ollamaConfigured: Boolean(ollamaBase),
    ollamaReachable,
    authEnabled,
    authConfigured: !authEnabled || hasSupabase,
    fleetConfigured,
    licenseKeyPresent,
    fleetRegistered,
    heartbeatEnabled,
    connectorEncryptionConfigured: Boolean(
      runtimeEnv('KNONIX_CONNECTOR_ENCRYPTION_KEY')
    )
  }

  const ready =
    checks.ollamaReachable &&
    checks.authConfigured &&
    (licenseMode === 'offline' ||
      licenseMode === 'free' ||
      (checks.fleetConfigured && checks.licenseKeyPresent) ||
      (checks.fleetConfigured && !checks.licenseKeyPresent))

  const setupSteps: Array<{ id: string; done: boolean; message: string }> = [
    {
      id: 'ollama',
      done: checks.ollamaReachable,
      message: checks.ollamaReachable
        ? 'Local model runtime is reachable'
        : 'Ollama is not reachable — check the ollama service'
    },
    {
      id: 'model',
      done: installedModels.length > 0,
      message:
        installedModels.length > 0
          ? `Models installed: ${installedModels.slice(0, 4).join(', ')}`
          : 'No models installed yet — install.sh pulls defaults, or use Admin → Models'
    },
    {
      id: 'auth',
      done: checks.authConfigured,
      message: checks.authConfigured
        ? authEnabled
          ? 'Authentication is configured'
          : 'Auth disabled (single-user mode)'
        : 'Auth enabled but Supabase/GoTrue keys are missing'
    },
    {
      id: 'fleet',
      done:
        licenseMode === 'offline' ||
        licenseMode === 'free' ||
        (checks.fleetConfigured &&
          (checks.licenseKeyPresent || checks.fleetRegistered)),
      message:
        licenseMode === 'offline'
          ? 'Offline license mode'
          : licenseMode === 'free' && !checks.fleetConfigured
            ? 'Free tier (local only) — set KNONIX_LICENSE_SERVICE_URL + TOKEN for fleet reporting'
            : checks.licenseKeyPresent || checks.fleetRegistered
              ? 'Fleet license present — seats report via heartbeat'
              : checks.fleetConfigured
                ? 'Fleet credentials set — license assigns on first admin sign-up'
                : 'Fleet not configured — seats will not report to Knonix'
    },
    {
      id: 'heartbeat',
      done:
        heartbeatEnabled || licenseMode === 'free' || licenseMode === 'offline',
      message: heartbeatEnabled
        ? 'Heartbeat secret set (cron can report seats daily)'
        : 'Set KNONIX_HEARTBEAT_SECRET so the install can schedule seat reports'
    }
  ]

  return Response.json({
    status: ready ? 'ok' : 'degraded',
    version: runtimeEnv('KNONIX_VERSION') || '1.0.0',
    defaultModel: DEFAULT_MODEL.id,
    defaultProvider: DEFAULT_MODEL.providerId,
    sovereign: isSovereignProvider(DEFAULT_MODEL.providerId),
    frontierEnabled: isFrontierAllowed(),
    licenseMode,
    activeSeats,
    installedModels,
    checks,
    setupSteps,
    ready
  })
}
