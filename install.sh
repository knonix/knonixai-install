#!/usr/bin/env bash
#
# install.sh — Bootstrap a KnonixAI install from the prebuilt GHCR image.
#
# This does NOT require access to the KnonixAI source repository. It pulls the
# published container image, brings up the full sovereign stack (app + Ollama +
# Postgres + Redis + SearXNG), and pulls the default local models.
#
# Prerequisites:
#   - Docker + Docker Compose v2
#   - A GHCR access token with read:packages (provided by Knonix), UNLESS the
#     image has been made public. Set it via the GHCR_TOKEN + GHCR_USER env
#     vars, or log in beforehand with `docker login ghcr.io`.
#
# Usage:
#   GHCR_USER=<your-github-user> GHCR_TOKEN=<token> ./install.sh
#   # or, if already logged in / image is public:
#   ./install.sh
#
set -euo pipefail

IMAGE="ghcr.io/knonix/knonixai"
COMPOSE_FILE="docker-compose.yml"

echo "==> KnonixAI install"

# 1. Preflight: docker + compose present.
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. Install Docker first." >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 is required (docker compose ...)." >&2
  exit 1
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

# 3. Authenticate to GHCR if a token was provided (needed for a private image).
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  : "${GHCR_USER:?Set GHCR_USER alongside GHCR_TOKEN}"
  echo "==> Logging in to ghcr.io as ${GHCR_USER}"
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
fi

# 4. Pull the image and bring the stack up.
TAG="$(grep -E '^KNONIX_IMAGE_TAG=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
TAG="${TAG:-latest}"
echo "==> Pulling ${IMAGE}:${TAG}"
if ! docker pull "${IMAGE}:${TAG}"; then
  echo "ERROR: could not pull ${IMAGE}:${TAG}." >&2
  echo "       If the image is private, set GHCR_USER + GHCR_TOKEN (read:packages)" >&2
  echo "       or run 'docker login ghcr.io' first. Contact sales@knonix.com for access." >&2
  exit 1
fi

echo "==> Starting the KnonixAI stack"
docker compose -f "${COMPOSE_FILE}" up -d

# 5. Pull the default sovereign models into Ollama.
echo "==> Pulling default local models (llama3.1:8b, nemotron-mini:4b, nomic-embed-text)"
echo "    (this can take several minutes on first run)"
for model in llama3.1:8b nemotron-mini:4b nomic-embed-text; do
  docker compose -f "${COMPOSE_FILE}" exec -T ollama ollama pull "${model}" || \
    echo "WARNING: failed to pull ${model} — you can pull it later from /admin."
done

echo
echo "==> KnonixAI is up."
echo "    App:   http://localhost:3000"
echo "    Admin: http://localhost:3000/admin"
echo
echo "    Manage the stack with: docker compose -f ${COMPOSE_FILE} ps | logs | down"
