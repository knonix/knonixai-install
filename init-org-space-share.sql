-- Org-only Spaces collaboration
-- When a membership becomes active, grant space_members access on every Space
-- in that organization (editor, or owner if they created the Space).
-- Safe to re-run.

CREATE OR REPLACE FUNCTION knonix_sync_space_members_on_membership()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'active'
     AND NEW.user_id IS NOT NULL
     AND NEW.user_id <> '' THEN
    INSERT INTO space_members (id, space_id, user_id, role, created_at)
    SELECT
      substr(md5(random()::text || clock_timestamp()::text || NEW.user_id || s.id), 1, 24),
      s.id,
      NEW.user_id,
      CASE WHEN s.created_by_user_id = NEW.user_id THEN 'owner' ELSE 'editor' END,
      now()
    FROM spaces s
    WHERE s.org_id = NEW.org_id
      AND NOT EXISTS (
        SELECT 1 FROM space_members sm
        WHERE sm.space_id = s.id AND sm.user_id = NEW.user_id
      );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_knonix_membership_space_access ON memberships;
CREATE TRIGGER trg_knonix_membership_space_access
AFTER INSERT OR UPDATE OF status, user_id, org_id
ON memberships
FOR EACH ROW
EXECUTE FUNCTION knonix_sync_space_members_on_membership();
