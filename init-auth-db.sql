--
-- KnonixAI — Postgres bootstrap for self-hosted Supabase Auth (GoTrue).
--
-- The install reuses the same Postgres instance that stores chat history for
-- the GoTrue auth tables, keeping everything inside one sovereign boundary
-- (no external database, no cloud Supabase).
--
-- GoTrue runs its OWN migrations to create the tables it needs inside the
-- `auth` schema on first start. This script pre-creates that schema and the
-- `postgres` role GoTrue migrations expect (GRANT ... TO postgres).
--
-- Docker runs every *.sql in /docker-entrypoint-initdb.d exactly once, on the
-- FIRST initialization of an empty data volume. On existing volumes this file
-- is ignored — install.sh re-applies the role bootstrap on upgrades.
--
CREATE SCHEMA IF NOT EXISTS auth;

-- GoTrue v2.177+ migrations grant on the "postgres" role. Official images
-- create it by default; KnonixAI uses POSTGRES_USER=knonixai instead.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres WITH SUPERUSER INHERIT CREATEDB CREATEROLE LOGIN
      REPLICATION BYPASSRLS;
  END IF;
END $$;