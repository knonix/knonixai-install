-- GoTrue MFA migrations create factor_type in public, but v2.177+ migrations
-- reference auth.factor_type when GOTRUE_DB_NAMESPACE=auth. Pre-create the auth-
-- schema enums so later migrations (e.g. add_mfa_phone_config) succeed.
DO $$
BEGIN
  CREATE TYPE auth.factor_type AS ENUM ('totp', 'webauthn');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE auth.factor_status AS ENUM ('unverified', 'verified');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE auth.aal_level AS ENUM ('aal1', 'aal2', 'aal3');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;