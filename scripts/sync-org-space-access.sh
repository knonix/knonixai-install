#!/usr/bin/env bash
# sync-org-space-access.sh — Make Spaces visible/shareable to all active org members.
#
# Spaces are org-scoped. The app lists/opens Spaces via space_members ⋈ userId.
# Creators only get an owner row by default; this backfills every active
# membership as editor so the whole organization can collaborate.
# Users outside the org never get a row (and never see the Space).
#
# Safe to re-run (idempotent). Prefer this after invite accept / membership activate.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load POSTGRES_* from .env when present
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source <(grep -E '^(POSTGRES_USER|POSTGRES_DB|POSTGRES_PASSWORD)=' .env | sed 's/\r$//')
  set +a
fi

COMPOSE=(docker compose -f docker-compose.yml)
if [[ -f docker-compose.proxy.yml ]]; then COMPOSE+=(-f docker-compose.proxy.yml); fi
if [[ -f docker-compose.platform.yml ]]; then COMPOSE+=(-f docker-compose.platform.yml); fi
if [[ -f docker-compose.fix-health.yml ]]; then COMPOSE+=(-f docker-compose.fix-health.yml); fi

echo "==> Ensuring membership→space_members trigger (invite-accept path)"
if [[ -f init-org-space-share.sql ]]; then
  "${COMPOSE[@]}" exec -T postgres psql -U "${POSTGRES_USER:-knonixai}" -d "${POSTGRES_DB:-knonixai}" \
    < init-org-space-share.sql >/dev/null
fi

echo "==> Syncing org members → space_members (org-only sharing)"
"${COMPOSE[@]}" exec -T postgres psql -U "${POSTGRES_USER:-knonixai}" -d "${POSTGRES_DB:-knonixai}" <<'SQL'
INSERT INTO space_members (id, space_id, user_id, role, created_at)
SELECT
  substr(md5(random()::text || clock_timestamp()::text || m.user_id || s.id), 1, 24),
  s.id,
  m.user_id,
  CASE WHEN s.created_by_user_id = m.user_id THEN 'owner' ELSE 'editor' END,
  now()
FROM spaces s
JOIN memberships m ON m.org_id = s.org_id
WHERE m.status = 'active'
  AND m.user_id IS NOT NULL
  AND m.user_id <> ''
  AND NOT EXISTS (
    SELECT 1 FROM space_members sm
    WHERE sm.space_id = s.id AND sm.user_id = m.user_id
  );

-- Summary: org-scoped membership vs outsiders
SELECT
  s.id AS space_id,
  s.name,
  s.org_id,
  count(sm.user_id) AS member_count,
  string_agg(sm.role || ':' || left(sm.user_id, 8), ', ' ORDER BY sm.role, sm.user_id) AS members
FROM spaces s
LEFT JOIN space_members sm ON sm.space_id = s.id
GROUP BY s.id, s.name, s.org_id
ORDER BY s.name;

SELECT count(*) AS space_member_rows FROM space_members;
SQL
echo "==> Done. Active org members can open shared Spaces; non-members cannot."
