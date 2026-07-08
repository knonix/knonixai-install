-- Idempotent bootstrap for existing Postgres volumes (not first-init only).
-- Creates the `postgres` role GoTrue migrations require when POSTGRES_USER
-- is not literally "postgres" (KnonixAI default: knonixai).
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres WITH SUPERUSER INHERIT CREATEDB CREATEROLE LOGIN
      REPLICATION BYPASSRLS;
  END IF;
END $$;