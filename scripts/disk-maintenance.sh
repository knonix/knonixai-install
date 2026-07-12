#!/usr/bin/env bash
# Reclaim Docker disk space on a KnonixAI install.
#
# Safe to run while the stack is up. Does NOT delete named volumes (Postgres,
# Ollama models in use, chat history).
#
# Usage:
#   ./scripts/disk-maintenance.sh           # report only
#   ./scripts/disk-maintenance.sh --prune   # prune dangling images + build cache

set -euo pipefail

PRUNE=false
if [[ "${1:-}" == "--prune" ]]; then
  PRUNE=true
fi

echo "==> Disk usage (Docker data root)"
docker info --format 'Docker Root Dir: {{.DockerRootDir}}' 2>/dev/null || true
df -h "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null | xargs dirname 2>/dev/null || echo .)" 2>/dev/null || df -h /

echo ""
echo "==> Docker space summary"
docker system df 2>/dev/null || true

echo ""
echo "==> Ollama models (each ~5 GB for 7B/8B)"
if docker compose ps ollama --status running -q 2>/dev/null | grep -q .; then
  docker compose exec -T ollama ollama list 2>/dev/null || true
  echo "    Remove an unused model: docker compose exec ollama ollama rm <name>"
else
  echo "    (ollama service not running)"
fi

echo ""
echo "==> Named volumes (data is preserved — not deleted by this script)"
docker volume ls --filter name=knonixai 2>/dev/null || docker volume ls

if [[ "${PRUNE}" == "true" ]]; then
  echo ""
  echo "==> Pruning dangling images and build cache..."
  docker image prune -f
  docker builder prune -af 2>/dev/null || true
  echo "==> Done. Run 'docker system df' to verify."
else
  echo ""
  echo "==> Report only. To prune dangling images and build cache, run:"
  echo "    $0 --prune"
  echo ""
  echo "    To free ~5 GB per model, remove models you no longer use:"
  echo "    docker compose exec ollama ollama rm <model-name>"
fi