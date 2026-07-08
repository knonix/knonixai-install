-- Full GoTrue reset for repairs when auth migrations are in a bad state.
-- Safe when no user accounts exist yet (0 rows in auth.users).
-- Clears public.schema_migrations (GoTrue pop tracker) and rebuilds auth schema.
TRUNCATE public.schema_migrations;
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA auth;