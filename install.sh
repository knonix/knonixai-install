#!/usr/bin/env bash
#
# install.sh — Bootstrap a KnonixAI install from the prebuilt GHCR image.
#
# This does NOT require access to the KnonixAI source repository. It pulls the
# published PUBLIC container image, brings up the full sovereign stack (app +
# Ollama + Postgres + Redis + SearXNG), and pulls the default local models.
#
# Preflight checks (and, where possible, auto-fixes): docker + Compose v2
# present, and the Docker daemon running (auto-started via systemd/service/
# dockerd if it is down).
#
# Prerequisites:
#   - Docker + Docker Compose v2
#
# The image is public, so no login or token is needed. If Knonix has
# provisioned a PRIVATE image for your org, pass the token they gave you via
# the GHCR_USER + GHCR_TOKEN env vars (or run `docker login ghcr.io` first).
#
# Usage:
#   ./install.sh
#   # private image only:
#   GHCR_USER=<your-github-user> GHCR_TOKEN=<token> ./install.sh
#
set -euo pipefail

IMAGE="ghcr.io/knonix/knonixai"
COMPOSE_FILE="docker-compose.yml"
PROXY_FILE="docker-compose.proxy.yml"

# Read a KEY=value from .env (last match wins), stripped of surrounding quotes.
# Tolerates an optional `export ` prefix, leading whitespace, and spaces around
# the `=`, and ignores commented (#) lines, so hand-edited .env files just work.
read_env() {
  local key="$1" v
  v="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" .env 2>/dev/null \
        | grep -vE "^[[:space:]]*#" | tail -1 | cut -d= -f2- || true)"
  # Trim leading/trailing whitespace.
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  # Strip one layer of surrounding single or double quotes.
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

echo "==> KnonixAI install"
echo
echo "    Easy setup guide: EASY_SETUP.md  (for non-technical installers)"
echo "    You only need Docker. Answer the prompts or press Enter for defaults."
echo

# 1. Preflight: docker + compose present.
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Install Docker first." >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 is required (the 'docker compose' subcommand)." >&2
  echo "       Install it, e.g.: sudo apt-get install -y docker-compose-plugin" >&2
  exit 1
fi

# 1b. Ensure the Docker daemon is running and reachable. Auto-start it if not.
wait_for_docker() {
  # Poll `docker info` for up to ~30s; return 0 once the daemon responds.
  for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if ! docker info >/dev/null 2>&1; then
  # Distinguish "daemon down" from "running but I lack permission".
  err="$(docker info 2>&1 || true)"
  if echo "$err" | grep -qi "permission denied"; then
    echo "ERROR: cannot access the Docker socket (permission denied)." >&2
    echo "       Re-run with sudo:            sudo ./install.sh" >&2
    echo "       ...or add yourself to docker: sudo usermod -aG docker \$USER && newgrp docker" >&2
    exit 1
  fi

  echo "==> Docker daemon not reachable — attempting to start it"
  # Prefer root for daemon management; use sudo if available and not already root.
  SUDO=""
  if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      echo "ERROR: Docker daemon is not running and I can't elevate to start it." >&2
      echo "       Start it manually (e.g. 'sudo systemctl start docker') and re-run." >&2
      exit 1
    fi
  fi

  started=""
  if command -v systemctl >/dev/null 2>&1; then
    echo "    Trying: ${SUDO:+sudo }systemctl start docker"
    $SUDO systemctl start docker >/dev/null 2>&1 && started=1 || true
    # Best-effort: enable on boot so this doesn't recur.
    $SUDO systemctl enable docker >/dev/null 2>&1 || true
  fi
  if [[ -z "$started" ]] && command -v service >/dev/null 2>&1; then
    echo "    Trying: ${SUDO:+sudo }service docker start"
    $SUDO service docker start >/dev/null 2>&1 && started=1 || true
  fi
  if [[ -z "$started" ]] && command -v dockerd >/dev/null 2>&1; then
    # No init system (minimal hosts / some WSL setups): launch dockerd directly.
    echo "    Trying: ${SUDO:+sudo }dockerd (background)"
    $SUDO sh -c 'dockerd >/var/log/dockerd.log 2>&1 &' && started=1 || true
  fi

  if ! wait_for_docker; then
    echo "ERROR: Docker daemon did not become reachable." >&2
    echo "       Start it manually and re-run:" >&2
    echo "         sudo systemctl enable --now docker   # systemd hosts" >&2
    echo "         sudo dockerd &                        # no-systemd hosts" >&2
    echo "       Diagnose with: sudo journalctl -u docker --no-pager -n 40" >&2
    exit 1
  fi
  echo "    Docker daemon is up."
fi

# 2. Ensure a .env exists.
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    chmod 600 .env 2>/dev/null || true
    echo "Created .env from .env.example (mode 600)"
  else
    echo "ERROR: no .env or .env.example found in $(pwd)." >&2
    exit 1
  fi
fi

# Interactive prompt (TTY only). Non-interactive installs keep existing .env.
prompt_value() {
  local prompt="$1" default="$2" var=""
  if [[ ! -t 0 ]]; then
    printf '%s' "${default}"
    return 0
  fi
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " var || true
    printf '%s' "${var:-$default}"
  else
    read -r -p "${prompt}: " var || true
    printf '%s' "${var}"
  fi
}

# Write KEY=value into .env (replace existing uncommented line or append).
set_env() {
  local key="$1" val="$2"
  if grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" .env 2>/dev/null; then
    sed -i.bak -E "s|^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=.*|${key}=${val}|" .env \
      && rm -f .env.bak
  elif grep -qE "^[[:space:]]*#[[:space:]]*${key}[[:space:]]*=" .env 2>/dev/null; then
    sed -i.bak -E "s|^[[:space:]]*#[[:space:]]*${key}[[:space:]]*=.*|${key}=${val}|" .env \
      && rm -f .env.bak
  else
    printf '\n%s=%s\n' "$key" "$val" >> .env
  fi
}

# 2a. Guided configuration — only the fields companies always need.
echo "==> Checking required configuration"
NEED_WIZARD=0
PG_PASS_NOW="$(read_env POSTGRES_PASSWORD)"
if [[ -z "${PG_PASS_NOW}" || "${PG_PASS_NOW}" == "change-me-in-production" || "${PG_PASS_NOW}" == "knonixai" ]]; then
  NEED_WIZARD=1
fi
FLEET_TOKEN_NOW="$(read_env KNONIX_LICENSE_SERVICE_TOKEN)"
LICENSE_MODE_NOW="$(read_env KNONIX_LICENSE_MODE)"
LICENSE_MODE_NOW="${LICENSE_MODE_NOW:-connected}"

if [[ -t 0 ]]; then
  echo
  echo "    KnonixAI customer setup (press Enter to accept defaults)."
  echo "    Docs: https://github.com/knonix/knonixai-install"
  echo

  if [[ "${NEED_WIZARD}" -eq 1 ]]; then
    GEN_PG="$(openssl rand -base64 24 2>/dev/null | tr -d '/+=' | head -c 24 || echo "Kn0n1x$(date +%s)")"
    NEW_PG="$(prompt_value "Postgres password (required — store this securely)" "${GEN_PG}")"
    set_env POSTGRES_PASSWORD "${NEW_PG}"
    echo "    Saved POSTGRES_PASSWORD"
  fi

  CURRENT_DOMAIN="$(read_env KNONIX_DOMAIN)"
  NEW_DOMAIN="$(prompt_value "Public domain for HTTPS (blank = localhost only)" "${CURRENT_DOMAIN}")"
  if [[ -n "${NEW_DOMAIN}" ]]; then
    set_env KNONIX_DOMAIN "${NEW_DOMAIN}"
    CURRENT_EMAIL="$(read_env KNONIX_ACME_EMAIL)"
    NEW_EMAIL="$(prompt_value "Email for HTTPS certificate notices" "${CURRENT_EMAIL}")"
    if [[ -n "${NEW_EMAIL}" ]]; then
      set_env KNONIX_ACME_EMAIL "${NEW_EMAIL}"
    fi
  fi

  echo
  echo "    Seat reporting for billing (optional, connected mode):"
  echo "    Your install stays fully local. If you paste the enrollment token from"
  echo "    Knonix, a daily privacy-preserving heartbeat reports ONLY seat count"
  echo "    (no chat content, no user PII) so Knonix can bill accurately."
  echo "    You do NOT get access to any Knonix fleet or licensing console."
  echo "    Leave blank for free/local-only (no reporting to Knonix)."
  NEW_TOKEN="$(prompt_value "KNONIX_LICENSE_SERVICE_TOKEN (enrollment from Knonix)" "${FLEET_TOKEN_NOW}")"
  if [[ -n "${NEW_TOKEN}" ]]; then
    set_env KNONIX_LICENSE_SERVICE_TOKEN "${NEW_TOKEN}"
    set_env KNONIX_LICENSE_MODE "connected"
    if [[ -z "$(read_env KNONIX_LICENSE_SERVICE_URL)" ]]; then
      set_env KNONIX_LICENSE_SERVICE_URL "https://ai.knonix.com"
    fi
    echo "    Fleet enrollment token saved (connected mode)."
  else
    if [[ "${LICENSE_MODE_NOW}" == "connected" && -z "${FLEET_TOKEN_NOW}" ]]; then
      echo "    No fleet token — switching to free (local) mode. You can add a token later."
      set_env KNONIX_LICENSE_MODE "free"
    fi
  fi
else
  # Non-interactive: refuse known-bad default passwords (audit §5.5).
  if [[ -z "${PG_PASS_NOW}" || "${PG_PASS_NOW}" == "change-me-in-production" || "${PG_PASS_NOW}" == "knonixai" ]]; then
    echo "ERROR: POSTGRES_PASSWORD is weak or unset (refused: empty, change-me-in-production, knonixai)." >&2
    echo "       Edit .env and set a strong password, then re-run." >&2
    exit 1
  fi
  if [[ "${LICENSE_MODE_NOW}" == "connected" && -z "${FLEET_TOKEN_NOW}" ]]; then
    echo "WARNING: KNONIX_LICENSE_MODE=connected but KNONIX_LICENSE_SERVICE_TOKEN is empty."
    echo "         Seats will not report to the Knonix fleet board until you set the token."
  fi
fi

# Always ensure fleet URL default when connected.
if [[ "$(read_env KNONIX_LICENSE_MODE)" == "connected" ]]; then
  if [[ -z "$(read_env KNONIX_LICENSE_SERVICE_URL)" ]]; then
    set_env KNONIX_LICENSE_SERVICE_URL "https://ai.knonix.com"
  fi
fi

# Auto-generate install secrets (idempotent).
if command -v openssl >/dev/null 2>&1; then
  if [[ -z "$(read_env KNONIX_HEARTBEAT_SECRET)" ]]; then
    set_env KNONIX_HEARTBEAT_SECRET "$(openssl rand -hex 32)"
    echo "==> Generated KNONIX_HEARTBEAT_SECRET (daily seat reporting)"
  fi
  if [[ -z "$(read_env KNONIX_CONNECTOR_ENCRYPTION_KEY)" ]]; then
    # 32-byte key, base64 — used to encrypt OAuth connector tokens at rest.
    set_env KNONIX_CONNECTOR_ENCRYPTION_KEY "$(openssl rand -base64 32)"
    echo "==> Generated KNONIX_CONNECTOR_ENCRYPTION_KEY (connector token encryption)"
  fi
  if [[ -z "$(read_env REDIS_PASSWORD)" ]]; then
    set_env REDIS_PASSWORD "$(openssl rand -hex 24)"
    echo "==> Generated REDIS_PASSWORD (Redis requirepass)"
  fi
  # Keep LOCAL_REDIS_URL in sync with password for the app container.
  RP="$(read_env REDIS_PASSWORD)"
  if [[ -n "${RP}" ]]; then
    set_env LOCAL_REDIS_URL "redis://:${RP}@redis:6379"
  fi
  # Model defaults come from hardware profile (after set_env_if_absent is defined).
fi

# 2b. Provision self-hosted auth (GoTrue + Kong) fully automatically.
#
#     When ENABLE_AUTH=true (the default), the app needs a JWT secret plus an
#     anon and a service_role API key (both are HS256-signed JWTs), and a
#     Supabase URL pointing at the bundled Kong gateway. Rather than make the
#     operator generate these by hand, we mint any that are missing and write
#     them back into .env so the stack is self-configuring. Re-runs are
#     idempotent: existing values are preserved.

# Base64url (no padding) from stdin.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Sign a Supabase-style JWT for a given role using the shared secret.
#   mint_supabase_jwt <role> <secret>
mint_supabase_jwt() {
  local role="$1" secret="$2" header payload iat exp signing_input sig
  header='{"alg":"HS256","typ":"JWT"}'
  iat="$(date +%s)"
  # Default 1 year (audit P2-3). Override days via KNONIX_AUTH_JWT_TTL_DAYS (min 30, max 3650).
  local ttl_days
  ttl_days="$(read_env KNONIX_AUTH_JWT_TTL_DAYS 2>/dev/null || true)"
  ttl_days="${ttl_days:-365}"
  if ! [[ "${ttl_days}" =~ ^[0-9]+$ ]] || [[ "${ttl_days}" -lt 30 ]]; then ttl_days=365; fi
  if [[ "${ttl_days}" -gt 3650 ]]; then ttl_days=3650; fi
  exp=$((iat + ttl_days * 86400))
  payload="{\"role\":\"${role}\",\"iss\":\"supabase\",\"iat\":${iat},\"exp\":${exp}}"
  signing_input="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
  sig="$(printf '%s' "$signing_input" \
    | openssl dgst -binary -sha256 -hmac "$secret" | b64url)"
  printf '%s.%s' "$signing_input" "$sig"
}

# Append KEY=value to .env only if the key is not already set (uncommented).
set_env_if_absent() {
  local key="$1" val="$2"
  if [[ -n "$(read_env "$key")" ]]; then
    return 0  # already set by the operator or a previous run
  fi
  # Replace a commented placeholder line if present; otherwise append.
  if grep -qE "^[[:space:]]*#[[:space:]]*${key}[[:space:]]*=" .env 2>/dev/null; then
    # Portable in-place edit (GNU + BSD sed).
    sed -i.bak -E "s|^[[:space:]]*#[[:space:]]*${key}[[:space:]]*=.*|${key}=${val}|" .env \
      && rm -f .env.bak
  else
    printf '\n%s=%s\n' "$key" "$val" >> .env
  fi
}

# set_env is defined above (guided config); keep set_env_if_absent for auth minting.

# 2a. Hardware profile: low-CPU / low-GPU customers get 3B + tight context so
# chat stays interactive. Operators who already set KNONIX_MODEL keep it.
# shellcheck source=scripts/hardware-profile.sh
if [[ -f "$(dirname "$0")/scripts/hardware-profile.sh" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/scripts/hardware-profile.sh"
elif [[ -f "./scripts/hardware-profile.sh" ]]; then
  # shellcheck disable=SC1091
  source "./scripts/hardware-profile.sh"
fi
if declare -F detect_hardware_profile >/dev/null 2>&1; then
  read -r HW_PROFILE HW_MEM_GB HW_GPU HW_CORES HW_VRAM_MB < <(detect_hardware_profile)
  echo "==> Hardware profile: $(profile_description "${HW_PROFILE}")"
  echo "    Detected: ${HW_MEM_GB} GB RAM, ${HW_CORES} inference threads, GPU=${HW_GPU} (VRAM≈${HW_VRAM_MB} MB)"
  if declare -F host_environment_hint >/dev/null 2>&1; then
    echo "    Host: $(host_environment_hint)"
  fi
  apply_hardware_profile_env "${HW_PROFILE}" "${HW_CORES}"
  if [[ "${HW_PROFILE}" == "low" ]]; then
    echo "    Low-resource mode: default model qwen2.5:3b (override in .env or Admin → Models)."
    echo "    Tip: On MacBook / nested VMs there is no Apple Metal for Ollama — keep 3B + Quick mode."
    echo "    Tip: Cloud-class speed needs a GPU Linux host or optional frontier APIs for non-CUI work."
    echo "    Mac guide: docs/MACOS.md"
  fi
else
  set_env_if_absent KNONIX_MODEL "qwen2.5:3b"
  set_env_if_absent KNONIX_CODING_MODEL "qwen2.5:3b"
  set_env_if_absent OLLAMA_NUM_CTX "1536"
  set_env_if_absent OLLAMA_NUM_PREDICT "256"
  set_env_if_absent INFERENCE_MAX_OUTPUT_TOKENS "512"
  set_env_if_absent OLLAMA_KEEP_ALIVE "-1"
fi

AUTH_ENABLED="$(read_env ENABLE_AUTH)"
AUTH_ENABLED="${AUTH_ENABLED:-true}"
# Persist the resolved value so the app container always starts with an
# explicit ENABLE_AUTH. Without this, a pre-existing .env that lacks the line
# leaves the var unset at runtime and the app falls back to anonymous mode
# even though auth was fully provisioned below.
set_env_if_absent ENABLE_AUTH "${AUTH_ENABLED}"
if [[ "${AUTH_ENABLED}" == "true" ]]; then
  echo "==> Provisioning self-hosted auth (GoTrue + Kong)"
  if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl is required to generate auth keys but was not found." >&2
    echo "       Install it (e.g. 'sudo apt-get install -y openssl') and re-run," >&2
    echo "       or set ENABLE_AUTH=false in .env for single-user mode." >&2
    exit 1
  fi

  # 1) Shared JWT secret (generate once, reuse forever).
  AUTH_SECRET="$(read_env KNONIX_AUTH_JWT_SECRET)"
  if [[ -z "${AUTH_SECRET}" ]]; then
    AUTH_SECRET="$(openssl rand -hex 32)"
    set_env_if_absent KNONIX_AUTH_JWT_SECRET "${AUTH_SECRET}"
    echo "    Generated KNONIX_AUTH_JWT_SECRET"
  fi

  # 2) anon + service_role API keys (JWTs signed with the secret above). Only
  #    (re)mint if BOTH are missing, so we never rotate keys out from under an
  #    existing deployment.
  ANON_KEY="$(read_env NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)"
  SERVICE_KEY="$(read_env SUPABASE_SECRET_KEY)"
  if [[ -z "${ANON_KEY}" && -z "${SERVICE_KEY}" ]]; then
    ANON_KEY="$(mint_supabase_jwt anon "${AUTH_SECRET}")"
    SERVICE_KEY="$(mint_supabase_jwt service_role "${AUTH_SECRET}")"
    set_env_if_absent NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY "${ANON_KEY}"
    set_env_if_absent SUPABASE_SECRET_KEY "${SERVICE_KEY}"
    echo "    Generated anon + service_role API keys"
  fi

  # 3) Public URLs. In domain mode the app + auth are fronted by Caddy at
  #    https://<domain>/ and the gateway is reachable at .../supabase; in local
  #    mode Kong is published on :8000 and the app on :3000.
  AUTH_DOMAIN="$(read_env KNONIX_DOMAIN)"
  if [[ -n "${AUTH_DOMAIN}" && "${AUTH_DOMAIN}" != "localhost" ]]; then
    SUPABASE_URL="https://${AUTH_DOMAIN}/supabase"
    SITE_URL="https://${AUTH_DOMAIN}"
  else
    SUPABASE_URL="http://localhost:8000"
    SITE_URL="http://localhost:3000"
  fi
  set_env_if_absent NEXT_PUBLIC_SUPABASE_URL "${SUPABASE_URL}"
  set_env_if_absent KNONIX_AUTH_API_EXTERNAL_URL "${SUPABASE_URL}/auth/v1"
  set_env_if_absent KNONIX_AUTH_SITE_URL "${SITE_URL}"
  set_env_if_absent KNONIX_AUTH_ADDITIONAL_REDIRECT_URLS "${SITE_URL}/**"
  echo "    Auth URL: ${SUPABASE_URL}  (accounts + Google/Microsoft sign-in)"
else
  echo "==> Auth disabled (ENABLE_AUTH=false) — single-user / anonymous mode"
fi

# Public origin for OAuth / M365 connector callbacks. The Next.js process listens
# on 0.0.0.0:3000 inside Docker; these vars tell it the URL browsers use.
# Always re-sync from KNONIX_DOMAIN so flipping local → HTTPS domain updates
# callbacks without hand-editing stale localhost URLs.
AUTH_DOMAIN="$(read_env KNONIX_DOMAIN)"
if [[ -n "${AUTH_DOMAIN}" && "${AUTH_DOMAIN}" != "localhost" ]]; then
  PUBLIC_URL="https://${AUTH_DOMAIN}"
elif [[ "${AUTH_DOMAIN}" == "localhost" ]]; then
  PUBLIC_URL="https://localhost"
else
  PUBLIC_URL="http://localhost:3000"
fi
set_env KNONIX_PUBLIC_URL "${PUBLIC_URL}"
set_env NEXT_PUBLIC_BASE_URL "${PUBLIC_URL}"
echo "==> Public origin: ${PUBLIC_URL}"
if [[ -n "${AUTH_DOMAIN}" ]]; then
  echo "    Web server: Caddy will auto-start (HTTPS reverse proxy + Let's Encrypt)"
else
  echo "    Web server: local only (http://localhost:3000). Set KNONIX_DOMAIN for HTTPS."
fi

# Enterprise SSO (GoTrue): reuse connector MS OAuth creds when dedicated auth
# vars are unset, and auto-enable providers that have id + secret configured.
MS_OAUTH_ID="$(read_env KNONIX_MS_OAUTH_CLIENT_ID)"
MS_OAUTH_SECRET="$(read_env KNONIX_MS_OAUTH_CLIENT_SECRET)"
if [[ -z "$(read_env KNONIX_AUTH_AZURE_CLIENT_ID)" && -n "${MS_OAUTH_ID}" ]]; then
  set_env_if_absent KNONIX_AUTH_AZURE_CLIENT_ID "${MS_OAUTH_ID}"
fi
if [[ -z "$(read_env KNONIX_AUTH_AZURE_SECRET)" && -n "${MS_OAUTH_SECRET}" ]]; then
  set_env_if_absent KNONIX_AUTH_AZURE_SECRET "${MS_OAUTH_SECRET}"
fi
if [[ -n "$(read_env KNONIX_AUTH_AZURE_CLIENT_ID)" && -n "$(read_env KNONIX_AUTH_AZURE_SECRET)" ]]; then
  set_env_if_absent KNONIX_AUTH_AZURE_ENABLED "true"
fi
if [[ -n "$(read_env KNONIX_AUTH_GOOGLE_CLIENT_ID)" && -n "$(read_env KNONIX_AUTH_GOOGLE_SECRET)" ]]; then
  set_env_if_absent KNONIX_AUTH_GOOGLE_ENABLED "true"
fi

# 2c. SearXNG needs a non-empty secret_key. Generate one once and persist it so
#     the self-hosted search backend starts cleanly and serves JSON to the app.
SEARXNG_SECRET_VAL="$(read_env SEARXNG_SECRET)"
if [[ -z "${SEARXNG_SECRET_VAL}" ]] && command -v openssl >/dev/null 2>&1; then
  set_env_if_absent SEARXNG_SECRET "$(openssl rand -hex 32)"
  echo "==> Generated SEARXNG_SECRET"
fi

# 3. Authenticate to GHCR only if a token was provided (private-image case).
#    The public image needs no login; this block is skipped by default.
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  : "${GHCR_USER:?Set GHCR_USER alongside GHCR_TOKEN}"
  echo "==> Logging in to ghcr.io as ${GHCR_USER}"
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
fi

# 3b. Decide whether to front the app with the HTTPS reverse proxy. If a
#     domain is configured in .env, we add the Caddy overlay so the app is
#     served at https://<domain>/ with automatic Let's Encrypt certs. If not,
#     the app is published on http://localhost:3000.
KNONIX_DOMAIN="$(read_env KNONIX_DOMAIN)"
COMPOSE_ARGS=(-f "${COMPOSE_FILE}")
# Start the auth services (GoTrue + Kong) only when auth is enabled.
if [[ "${AUTH_ENABLED}" == "true" ]]; then
  COMPOSE_ARGS+=(--profile auth)
fi
# Seat heartbeats only when connected to Knonix billing (no outbound cron in offline/gov).
LICENSE_MODE_COMPOSE="$(read_env KNONIX_LICENSE_MODE)"
LICENSE_MODE_COMPOSE="${LICENSE_MODE_COMPOSE:-connected}"
if [[ "${LICENSE_MODE_COMPOSE}" == "connected" ]]; then
  COMPOSE_ARGS+=(--profile connected)
  echo "==> License mode: connected (daily seat heartbeat enabled)"
else
  echo "==> License mode: ${LICENSE_MODE_COMPOSE} (no outbound heartbeat-cron)"
fi
# NVIDIA GPU for Ollama when toolkit is present (skip on Mac VMs / CPU hosts).
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 \
  && [[ -f docker-compose.gpu.yml ]]; then
  COMPOSE_ARGS+=(-f docker-compose.gpu.yml)
  echo "==> NVIDIA GPU detected — enabling docker-compose.gpu.yml for Ollama"
fi
if [[ -n "${KNONIX_DOMAIN}" ]]; then
  if [[ ! -f "${PROXY_FILE}" ]]; then
    echo "ERROR: KNONIX_DOMAIN is set but ${PROXY_FILE} is missing." >&2
    echo "       Re-clone the installer (git pull) so the proxy overlay is present." >&2
    exit 1
  fi
  COMPOSE_ARGS+=(-f "${PROXY_FILE}")
  echo "==> Domain mode: serving at https://${KNONIX_DOMAIN} (Caddy + Let's Encrypt)"
  if [[ "${KNONIX_DOMAIN}" != "localhost" && -z "$(read_env KNONIX_ACME_EMAIL)" ]]; then
    echo "    NOTE: KNONIX_ACME_EMAIL is empty. Set it in .env for cert-expiry notices."
  fi
  echo "    Requirements: DNS A/AAAA for ${KNONIX_DOMAIN} -> this host, and ports 80+443 open."
  # Internet-facing: default invite-only (audit P1-5). First owner:
  #   temporarily set KNONIX_AUTH_DISABLE_SIGNUP=false, sign up, then re-enable true
  #   or use KNONIX_BOOTSTRAP_ADMIN_EMAIL + password + GoTrue admin (future).
  if [[ "${KNONIX_DOMAIN}" != "localhost" ]]; then
    if [[ -z "$(read_env KNONIX_AUTH_DISABLE_SIGNUP)" ]]; then
      set_env KNONIX_AUTH_DISABLE_SIGNUP "true"
      echo "    KNONIX_AUTH_DISABLE_SIGNUP=true (public domain — open signup off)"
      echo "    First owner: set to false once, create account, then set true again."
    fi
  fi
  # GCC High / gov: prefer offline licensing (no outbound heartbeat)
  MS_CLOUD="$(read_env KNONIX_MS_CLOUD_ENVIRONMENT)"
  if [[ "${MS_CLOUD}" == "gcc_high" || "${MS_CLOUD}" == "dod" || "$(read_env KNONIX_GOV_MODE)" == "true" ]]; then
    if [[ -z "$(read_env KNONIX_LICENSE_MODE)" || "$(read_env KNONIX_LICENSE_MODE)" == "connected" ]]; then
      if [[ "$(read_env KNONIX_FORCE_CONNECTED)" != "true" ]]; then
        set_env_if_absent KNONIX_LICENSE_MODE "offline"
        echo "    Gov cloud detected — KNONIX_LICENSE_MODE defaults toward offline (no seat egress)."
      fi
    fi
  fi
else
  echo "==> Local mode: serving at http://127.0.0.1:3000 (no domain configured)"
  echo "    KNONIX_DOMAIN was empty (checked $(pwd)/.env)."
  if [[ ! -f .env ]]; then
    echo "    NOTE: no .env file found here. Copy it first: cp .env.example .env"
  fi
  echo "    To serve over HTTPS on your own domain, add these lines to .env"
  echo "    (use your fully-qualified domain, e.g. sub.domain.com):"
  echo "        KNONIX_DOMAIN=sub.domain.com"
  echo "        KNONIX_ACME_EMAIL=you@domain.com"
  echo "    then re-run: sudo ./install.sh"
fi

# 4. Pull the image and bring the stack up.
#
# Public customer installs always use the prebuilt GHCR image
# (ghcr.io/knonix/knonixai:latest by default). Platform-only files
# (docker-compose.platform.yml, Caddyfile.platform) are NEVER applied here —
# those are for the Knonix-operated fleet host only (scripts/platform-up.sh).
TAG="$(read_env KNONIX_IMAGE_TAG)"
TAG="${TAG:-latest}"

# Guardrails: public installer = customer local software ONLY.
# - No license-service / fleet board
# - No platform-owner / unlimited seats
# - No Knonix admin token (that would be a security leak if copied from platform)
# Customers may optionally SEND seat heartbeats to Knonix (connected mode) so
# Knonix can bill accurately — they never RECEIVE fleet visibility.
if [[ "$(read_env KNONIX_PLATFORM_OWNER)" == "true" ]] || [[ "$(read_env KNONIX_PLATFORM_MODE)" == "cloud" ]]; then
  echo "WARNING: .env had platform-owner flags (PLATFORM_OWNER / PLATFORM_MODE=cloud)."
  echo "         Public ./install.sh is for customer installs only — clearing those flags."
  echo "         For the Knonix fleet host (ai.knonix.com), use: sudo ./scripts/platform-up.sh"
fi
# Always force customer posture (idempotent).
set_env KNONIX_PLATFORM_OWNER false
if [[ "$(read_env KNONIX_PLATFORM_MODE)" == "cloud" ]] || [[ -z "$(read_env KNONIX_PLATFORM_MODE)" ]]; then
  set_env KNONIX_PLATFORM_MODE sovereign
fi
# Strip operator-only secrets if a platform .env was copied by mistake.
if [[ -n "$(read_env KNONIX_LICENSE_ADMIN_TOKEN)" ]]; then
  echo "WARNING: KNONIX_LICENSE_ADMIN_TOKEN is set — that is Knonix-operator only."
  echo "         Clearing it so this customer install cannot act as fleet admin."
  set_env KNONIX_LICENSE_ADMIN_TOKEN ""
fi
# Secrets file must not be world-readable
chmod 600 .env 2>/dev/null || true
# Never pull license-service or platform Caddy via customer install path.
if [[ -f docker-compose.platform.yml ]]; then
  : # may exist in repo for Knonix ops; we intentionally never -f it here
fi

# ":local" is only for images built on this host (docker build -t …:local).
# It is not published to GHCR — do not try to pull it.
if [[ "${TAG}" == "local" ]]; then
  if docker image inspect "${IMAGE}:local" >/dev/null 2>&1; then
    echo "==> Using existing local image ${IMAGE}:local (not pulling from GHCR)"
    if [[ "$(read_env KNONIX_IMAGE_PULL_POLICY)" != "never" ]]; then
      set_env KNONIX_IMAGE_PULL_POLICY never
    fi
  else
    echo "WARNING: KNONIX_IMAGE_TAG=local but ${IMAGE}:local is not on this host."
    echo "         :local is never published to GHCR (dev builds only)."
    echo "         Switching to KNONIX_IMAGE_TAG=latest (public customer image)."
    TAG=latest
    set_env KNONIX_IMAGE_TAG latest
    set_env KNONIX_IMAGE_PULL_POLICY always
  fi
fi

if [[ "${TAG}" != "local" ]]; then
  echo "==> Pulling public image ${IMAGE}:${TAG}"
  if ! docker pull "${IMAGE}:${TAG}"; then
    echo "ERROR: could not pull ${IMAGE}:${TAG}." >&2
    echo "       Customers need anonymous pull of the public package on GHCR." >&2
    echo "       Check network/Docker, and that KNONIX_IMAGE_TAG is 'latest' or a" >&2
    echo "       published release tag. Private org images need GHCR_USER + GHCR_TOKEN" >&2
    echo "       (read:packages) or 'docker login ghcr.io'. Questions: sales@knonix.com." >&2
    exit 1
  fi
fi

echo "==> Preflight bind-mount sources (SearXNG / heartbeat / entrypoint)"
if [[ -x scripts/preflight-mounts.sh ]]; then
  bash scripts/preflight-mounts.sh
elif [[ -f scripts/preflight-mounts.sh ]]; then
  bash scripts/preflight-mounts.sh
else
  echo "WARNING: scripts/preflight-mounts.sh missing — compose may mount empty dirs"
fi

echo "==> Starting the KnonixAI stack (customer compose — no platform fleet service)"
docker compose "${COMPOSE_ARGS[@]}" up -d

# 4a. Confirm reverse proxy is up when domain mode is enabled.
if [[ -n "${KNONIX_DOMAIN}" ]]; then
  echo "==> Checking web server (Caddy reverse proxy)"
  caddy_ok=""
  for _ in $(seq 1 20); do
    if docker compose "${COMPOSE_ARGS[@]}" ps caddy 2>/dev/null | grep -qiE 'Up|running'; then
      caddy_ok=1
      break
    fi
    sleep 2
  done
  if [[ -n "${caddy_ok}" ]]; then
    echo "    Caddy is running — HTTPS at https://${KNONIX_DOMAIN}"
    if [[ "${KNONIX_DOMAIN}" != "localhost" ]]; then
      echo "    First request may issue a Let's Encrypt cert (needs DNS + ports 80/443)."
    fi
  else
    echo "WARNING: Caddy did not come up. HTTPS may not work yet."
    echo "         Check: docker compose ${COMPOSE_ARGS[*]} logs caddy"
    echo "         Confirm ${PROXY_FILE} exists and ports 80/443 are free."
  fi
fi

# 4b. Postgres bootstrap for existing volumes. Init scripts only run on a new
#     data volume, so on upgrades we ensure pgvector + auth schema here.
PG_USER="$(read_env POSTGRES_USER)"; PG_USER="${PG_USER:-knonixai}"
PG_DB="$(read_env POSTGRES_DB)"; PG_DB="${PG_DB:-knonixai}"
pg_ready=""
for _ in $(seq 1 30); do
  if docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
       pg_isready -U "${PG_USER}" >/dev/null 2>&1; then
    pg_ready=1
    break
  fi
  sleep 2
done

if [[ -n "${pg_ready}" ]]; then
  RAG_ENABLED="$(read_env KNONIX_RAG_ENABLED)"
  RAG_ENABLED="${RAG_ENABLED:-true}"
  if [[ "${RAG_ENABLED}" == "true" ]]; then
    echo "==> Ensuring pgvector extension is enabled (RAG / knowledge base)"
    docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -U "${PG_USER}" -d "${PG_DB}" -c 'CREATE EXTENSION IF NOT EXISTS vector;' \
      >/dev/null 2>&1 \
      && echo "    pgvector extension is ready." \
      || echo "WARNING: could not enable pgvector — confirm postgres image is pgvector/pgvector:pg17."
  fi

  if [[ "${AUTH_ENABLED}" == "true" ]]; then
    echo "==> Ensuring auth schema + postgres role exist (GoTrue requirement)"
    if docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -U "${PG_USER}" -d "${PG_DB}" < init-auth-role.sql >/dev/null 2>&1; then
      docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
        psql -U "${PG_USER}" -d "${PG_DB}" -c 'CREATE SCHEMA IF NOT EXISTS auth;' \
        >/dev/null 2>&1 || true
      docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
        psql -U "${PG_USER}" -d "${PG_DB}" < init-auth-types.sql >/dev/null 2>&1 || true
      # Stale auth.schema_migrations breaks GoTrue when search_path includes auth.
      docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
        psql -U "${PG_USER}" -d "${PG_DB}" -c 'DROP TABLE IF EXISTS auth.schema_migrations;' \
        >/dev/null 2>&1 || true
      echo "    auth schema + postgres role are ready."
      # If GoTrue is crash-looping on MFA enum migrations, repair automatically
      # when no accounts exist yet (fresh install / broken migration state).
      auth_users="$(
        docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
          psql -U "${PG_USER}" -d "${PG_DB}" -tAc 'SELECT count(*) FROM auth.users' 2>/dev/null \
          | tr -d '[:space:]' || echo 0
      )"
      if [[ "${auth_users}" == "0" ]] && docker compose "${COMPOSE_ARGS[@]}" ps supabase-auth 2>/dev/null \
        | grep -q 'Restarting'; then
        echo "    GoTrue unhealthy with no accounts — resetting auth migrations"
        docker compose "${COMPOSE_ARGS[@]}" stop supabase-auth >/dev/null 2>&1 || true
        docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
          psql -U "${PG_USER}" -d "${PG_DB}" < init-auth-reset.sql >/dev/null 2>&1 || true
        docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
          psql -U "${PG_USER}" -d "${PG_DB}" < init-auth-role.sql >/dev/null 2>&1 || true
        docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
          psql -U "${PG_USER}" -d "${PG_DB}" < init-auth-types.sql >/dev/null 2>&1 || true
      fi
      docker compose "${COMPOSE_ARGS[@]}" restart supabase-auth >/dev/null 2>&1 \
        && echo "    Restarted supabase-auth to apply migrations." \
        || true
    else
      echo "WARNING: could not bootstrap auth roles; check Postgres logs."
    fi
  fi
else
  echo "WARNING: Postgres did not become ready in time; skipping DB bootstrap."
fi

# 4c. Org-only Spaces: ensure active org members can list/open shared Spaces.
if [[ -n "${pg_ready:-}" ]]; then
  if [[ -f init-org-space-share.sql ]]; then
    echo "==> Installing org Spaces share trigger"
    docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -U "${PG_USER:-knonixai}" -d "${PG_DB:-knonixai}" < init-org-space-share.sql \
      >/dev/null 2>&1 || echo "WARNING: org space share trigger not applied (non-fatal)"
  fi
  if [[ -f scripts/sync-org-space-access.sh ]]; then
    echo "==> Syncing Spaces access for active organization members"
    bash scripts/sync-org-space-access.sh || echo "WARNING: space access sync failed (non-fatal)"
  fi
fi

# 5. Pull default sovereign models into Ollama (profile-aware; low-end = 3B only).
CHAT_MODEL="$(read_env KNONIX_MODEL)"; CHAT_MODEL="${CHAT_MODEL:-qwen2.5:3b}"
CODING_MODEL="$(read_env KNONIX_CODING_MODEL)"; CODING_MODEL="${CODING_MODEL:-${CHAT_MODEL}}"
echo "==> Pulling default local models (${CHAT_MODEL}, nomic-embed-text)"
echo "    (this can take several minutes on first run; needs free disk for models)"
for model in "${CHAT_MODEL}" nomic-embed-text; do
  docker compose "${COMPOSE_ARGS[@]}" exec -T ollama ollama pull "${model}" || \
    echo "WARNING: failed to pull ${model} — pull later from /admin or: docker compose exec ollama ollama pull ${model}"
done
# Second large model only when profile chose a distinct coding tag (medium/high).
if [[ "${CODING_MODEL}" != "${CHAT_MODEL}" ]]; then
  echo "==> Pulling coding model ${CODING_MODEL} (optional on small disks)"
  docker compose "${COMPOSE_ARGS[@]}" exec -T ollama ollama pull "${CODING_MODEL}" || \
    echo "WARNING: coding model not pulled — you can add it from /admin later."
else
  echo "    Coding uses the same model as chat (${CHAT_MODEL}) — saves RAM on low-end hosts."
fi
# Keep the chat model resident so the first user message is not a multi-minute cold load.
echo "==> Warming ${CHAT_MODEL} (keep_alive forever)"
curl -fsS --max-time 300 http://127.0.0.1:11434/api/generate \
  -d "{\"model\":\"${CHAT_MODEL}\",\"prompt\":\"ready\",\"stream\":false,\"keep_alive\":-1,\"options\":{\"num_predict\":2,\"num_ctx\":512}}" \
  >/dev/null 2>&1 \
  && echo "    Model warm." \
  || echo "WARNING: warm failed — first chat may be slow while the model loads."

# 6. Wait for app health, then print a clear first-run checklist.
if [[ -n "${KNONIX_DOMAIN}" && "${KNONIX_DOMAIN}" != "localhost" ]]; then
  APP_URL="https://${KNONIX_DOMAIN}"
elif [[ "${KNONIX_DOMAIN}" == "localhost" ]]; then
  APP_URL="https://localhost"
else
  APP_URL="http://localhost:3000"
fi

# Fetch health JSON even when the public domain cannot hairpin on the install host.
# Tries public URL first, then 127.0.0.1 with Host/SNI, then container network via docker.
fetch_health_json() {
  local url_path="/api/knonix/health" json=""
  json="$(curl -fsS --max-time 5 "${APP_URL}${url_path}" 2>/dev/null || true)"
  if [[ -n "${json}" ]]; then
    printf '%s' "${json}"
    return 0
  fi
  if [[ -n "${KNONIX_DOMAIN}" && "${KNONIX_DOMAIN}" != "localhost" ]]; then
    json="$(curl -fsSk --max-time 5 \
      --resolve "${KNONIX_DOMAIN}:443:127.0.0.1" \
      "https://${KNONIX_DOMAIN}${url_path}" 2>/dev/null || true)"
    if [[ -n "${json}" ]]; then
      printf '%s' "${json}"
      return 0
    fi
    json="$(curl -fsSk --max-time 5 \
      --resolve "${KNONIX_DOMAIN}:80:127.0.0.1" \
      "http://${KNONIX_DOMAIN}${url_path}" 2>/dev/null || true)"
    if [[ -n "${json}" ]]; then
      printf '%s' "${json}"
      return 0
    fi
  fi
  json="$(curl -fsS --max-time 5 "http://127.0.0.1:3000${url_path}" 2>/dev/null || true)"
  if [[ -n "${json}" ]]; then
    printf '%s' "${json}"
    return 0
  fi
  json="$(
    docker compose "${COMPOSE_ARGS[@]}" exec -T knonixai \
      wget -qO- --timeout=5 "http://127.0.0.1:3000${url_path}" 2>/dev/null || true
  )"
  if [[ -n "${json}" ]]; then
    printf '%s' "${json}"
    return 0
  fi
  return 1
}

echo "==> Waiting for app health (ready=true)…"
health_json=""
health_ready=""
health_status=""
health_auth=""
for _ in $(seq 1 50); do
  health_json="$(fetch_health_json || true)"
  if [[ -n "${health_json}" ]]; then
    health_status="$(printf '%s' "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    health_ready="$(printf '%s' "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ready',''))" 2>/dev/null || true)"
    health_auth="$(printf '%s' "${health_json}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('checks',{}).get('authConfigured',''))" 2>/dev/null || true)"
    # Accept true/True/1
    if [[ "${health_ready}" == "True" || "${health_ready}" == "true" || "${health_ready}" == "1" ]]; then
      break
    fi
  fi
  sleep 3
done

if [[ "${health_ready}" == "True" || "${health_ready}" == "true" || "${health_ready}" == "1" ]]; then
  echo "    Health OK (status=${health_status}, ready=true, authConfigured=${health_auth})"
else
  echo "WARNING: App did not report ready=true yet."
  echo "         status=${health_status:-unknown} authConfigured=${health_auth:-unknown}"
  if [[ -n "${health_json}" ]]; then
    printf '%s\n' "${health_json}" | python3 -m json.tool 2>/dev/null || printf '%s\n' "${health_json}"
  fi
  echo "         Check: docker compose ${COMPOSE_ARGS[*]} logs knonixai --tail 80"
  echo "         Then:  ./scripts/verify-install.sh"
fi

echo
echo "==> KnonixAI is up."
echo "    Legal: by using this software you accept TERMS_OF_USE.md (use at your own risk)."
echo "    Privacy: see PRIVACY_POLICY.md — self-hosted data stays in your boundary."
echo "    App:   ${APP_URL}"
echo "    Admin: ${APP_URL}/admin"
echo "    Health:${APP_URL}/api/knonix/health"
if [[ -n "${KNONIX_DOMAIN}" && "${KNONIX_DOMAIN}" != "localhost" ]]; then
  echo
  echo "    First HTTPS request may take a few seconds while Caddy issues the"
  echo "    Let's Encrypt certificate. If it fails, confirm DNS points here and"
  echo "    ports 80+443 are open, then: docker compose ${COMPOSE_ARGS[*]} logs caddy"
  echo "    Note: from the same LAN, https://${KNONIX_DOMAIN} may hang (router hairpin)."
  echo "    Test health with: curl -fsSk --resolve ${KNONIX_DOMAIN}:443:127.0.0.1 https://${KNONIX_DOMAIN}/api/knonix/health"
  echo "    Or test from a phone on cellular, not home Wi‑Fi."
fi
echo
echo "    ========== First-run checklist (required) =========="
if [[ "${AUTH_ENABLED}" == "true" ]]; then
  echo "    1. Open ${APP_URL}/auth/sign-up"
  echo "       Create the FIRST account with your work email — that user becomes"
  echo "       the organization owner (Admin)."
  echo "    2. Open ${APP_URL}/admin"
  echo "       Confirm License shows valid / free or paid, and your chat model is active."
  echo "    3. Open ${APP_URL}/admin/members"
  echo "       Add colleagues (each active member = 1 billable seat)."
else
  echo "    1. Open ${APP_URL} (auth disabled — single shared workspace)."
fi
FLEET_MODE="$(read_env KNONIX_LICENSE_MODE)"; FLEET_MODE="${FLEET_MODE:-connected}"
FLEET_TOKEN="$(read_env KNONIX_LICENSE_SERVICE_TOKEN)"
if [[ "${FLEET_MODE}" == "connected" && -n "${FLEET_TOKEN}" ]]; then
  echo "    4. Fleet: connected — first sign-up auto-registers this install;"
  echo "       daily heartbeats report seat counts (no PII) to Knonix."
elif [[ "${FLEET_MODE}" == "connected" ]]; then
  echo "    4. Fleet: set KNONIX_LICENSE_SERVICE_TOKEN in .env (from Knonix),"
  echo "       then: docker compose ${COMPOSE_ARGS[*]} up -d knonixai heartbeat-cron"
else
  echo "    4. Fleet: mode=${FLEET_MODE} (local free/offline — not reporting to Knonix)."
fi
echo "    5. Optional: Microsoft 365 connectors → Admin → Connectors"
echo "    6. Verify anytime: ./scripts/verify-install.sh"
echo "    ===================================================="
echo
echo "    Manage the stack with: docker compose ${COMPOSE_ARGS[*]} ps | logs | down"
