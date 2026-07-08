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
    echo "Created .env from .env.example"
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
  echo "    Fleet seat reporting (connected mode):"
  echo "    Knonix tracks seat counts via a privacy-preserving heartbeat."
  echo "    Paste the fleet enrollment token from your Knonix license email."
  echo "    Leave blank only for offline/local-only free tier (no fleet board)."
  NEW_TOKEN="$(prompt_value "KNONIX_LICENSE_SERVICE_TOKEN (fleet enrollment)" "${FLEET_TOKEN_NOW}")"
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
  # Non-interactive: refuse known-bad default passwords in production-ish configs.
  if [[ "${PG_PASS_NOW}" == "change-me-in-production" ]]; then
    echo "ERROR: POSTGRES_PASSWORD is still 'change-me-in-production'." >&2
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
  if [[ -z "$(read_env KNONIX_MODEL)" ]]; then
    set_env KNONIX_MODEL "qwen2.5:7b"
  fi
  if [[ -z "$(read_env KNONIX_CODING_MODEL)" ]]; then
    set_env KNONIX_CODING_MODEL "qwen2.5-coder:7b"
  fi
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
  # ~10 years so keys don't silently expire on long-lived on-prem installs.
  exp=$((iat + 315360000))
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
AUTH_DOMAIN="$(read_env KNONIX_DOMAIN)"
if [[ -n "${AUTH_DOMAIN}" && "${AUTH_DOMAIN}" != "localhost" ]]; then
  PUBLIC_URL="https://${AUTH_DOMAIN}"
elif [[ "${AUTH_DOMAIN}" == "localhost" ]]; then
  PUBLIC_URL="https://localhost"
else
  PUBLIC_URL="http://localhost:3000"
fi
set_env_if_absent KNONIX_PUBLIC_URL "${PUBLIC_URL}"
set_env_if_absent NEXT_PUBLIC_BASE_URL "${PUBLIC_URL}"

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
else
  echo "==> Local mode: serving at http://localhost:3000 (no domain configured)"
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
TAG="$(read_env KNONIX_IMAGE_TAG)"
TAG="${TAG:-latest}"
echo "==> Pulling ${IMAGE}:${TAG}"
if ! docker pull "${IMAGE}:${TAG}"; then
  echo "ERROR: could not pull ${IMAGE}:${TAG}." >&2
  echo "       The image is public, so check your network/Docker setup and the" >&2
  echo "       KNONIX_IMAGE_TAG in .env. If Knonix provisioned a PRIVATE image" >&2
  echo "       for your org, set GHCR_USER + GHCR_TOKEN (read:packages) or run" >&2
  echo "       'docker login ghcr.io' first. Questions: sales@knonix.com." >&2
  exit 1
fi

echo "==> Starting the KnonixAI stack"
docker compose "${COMPOSE_ARGS[@]}" up -d

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

# 5. Pull default sovereign models into Ollama (CPU-friendly defaults).
CHAT_MODEL="$(read_env KNONIX_MODEL)"; CHAT_MODEL="${CHAT_MODEL:-qwen2.5:7b}"
CODING_MODEL="$(read_env KNONIX_CODING_MODEL)"; CODING_MODEL="${CODING_MODEL:-qwen2.5-coder:7b}"
echo "==> Pulling default local models (${CHAT_MODEL}, nomic-embed-text)"
echo "    (this can take several minutes on first run; needs free disk for models)"
for model in "${CHAT_MODEL}" nomic-embed-text; do
  docker compose "${COMPOSE_ARGS[@]}" exec -T ollama ollama pull "${model}" || \
    echo "WARNING: failed to pull ${model} — pull later from /admin or: docker compose exec ollama ollama pull ${model}"
done
# Coding model is optional on small disks — pull best-effort.
if [[ "${CODING_MODEL}" != "${CHAT_MODEL}" ]]; then
  echo "==> Pulling coding model ${CODING_MODEL} (optional)"
  docker compose "${COMPOSE_ARGS[@]}" exec -T ollama ollama pull "${CODING_MODEL}" || \
    echo "WARNING: coding model not pulled — you can add it from /admin later."
fi

# 6. Wait for app health, then print a clear first-run checklist.
if [[ -n "${KNONIX_DOMAIN}" && "${KNONIX_DOMAIN}" != "localhost" ]]; then
  APP_URL="https://${KNONIX_DOMAIN}"
elif [[ "${KNONIX_DOMAIN}" == "localhost" ]]; then
  APP_URL="https://localhost"
else
  APP_URL="http://localhost:3000"
fi

echo "==> Waiting for app health at ${APP_URL}/api/knonix/health"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 5 "${APP_URL}/api/knonix/health" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

echo
echo "==> KnonixAI is up."
echo "    App:   ${APP_URL}"
echo "    Admin: ${APP_URL}/admin"
echo "    Health:${APP_URL}/api/knonix/health"
if [[ -n "${KNONIX_DOMAIN}" && "${KNONIX_DOMAIN}" != "localhost" ]]; then
  echo
  echo "    First HTTPS request may take a few seconds while Caddy issues the"
  echo "    Let's Encrypt certificate. If it fails, confirm DNS points here and"
  echo "    ports 80+443 are open, then: docker compose ${COMPOSE_ARGS[*]} logs caddy"
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
