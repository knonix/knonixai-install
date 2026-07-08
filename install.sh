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
    echo "Created .env from .env.example — review it (set POSTGRES_PASSWORD, license, etc.)."
  else
    echo "ERROR: no .env or .env.example found in $(pwd)." >&2
    exit 1
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
    echo "==> Ensuring the auth schema exists in Postgres"
    docker compose "${COMPOSE_ARGS[@]}" exec -T postgres \
      psql -U "${PG_USER}" -d "${PG_DB}" -c 'CREATE SCHEMA IF NOT EXISTS auth;' \
      >/dev/null 2>&1 \
      && echo "    auth schema is ready." \
      || echo "WARNING: could not create the auth schema automatically; GoTrue may create it on start."
  fi
else
  echo "WARNING: Postgres did not become ready in time; skipping DB bootstrap."
fi

# 5. Pull the default sovereign models into Ollama.
echo "==> Pulling default local models (llama3.1:8b, nemotron-mini:4b, nomic-embed-text)"
echo "    (this can take several minutes on first run)"
for model in llama3.1:8b nemotron-mini:4b nomic-embed-text; do
  docker compose "${COMPOSE_ARGS[@]}" exec -T ollama ollama pull "${model}" || \
    echo "WARNING: failed to pull ${model} — you can pull it later from /admin."
done

echo
echo "==> KnonixAI is up."
if [[ -n "${KNONIX_DOMAIN}" ]]; then
  echo "    App:   https://${KNONIX_DOMAIN}"
  echo "    Admin: https://${KNONIX_DOMAIN}/admin"
  echo
  echo "    First HTTPS request may take a few seconds while Caddy issues the"
  echo "    Let's Encrypt certificate. If it fails, confirm DNS points here and"
  echo "    ports 80+443 are open, then: docker compose ${COMPOSE_ARGS[*]} logs caddy"
else
  echo "    App:   http://localhost:3000"
  echo "    Admin: http://localhost:3000/admin"
fi
if [[ "${AUTH_ENABLED}" == "true" ]]; then
  echo
  echo "    Accounts are ENABLED. Open the app and click Sign up to create the"
  echo "    first account (email/password works immediately — no email server"
  echo "    needed). To add Google/Microsoft sign-in, fill in the KNONIX_AUTH_*"
  echo "    OAuth values in .env and re-run this script."
fi
echo
echo "    Manage the stack with: docker compose ${COMPOSE_ARGS[*]} ps | logs | down"
