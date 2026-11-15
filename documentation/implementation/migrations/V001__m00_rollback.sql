-- ============================================================================
-- KEKE — Rollback for Migration M-00 (V001__m00_extensions_roles_schema.sql)
-- ----------------------------------------------------------------------------
-- Reverses the schema and role objects created by M-00.
--
-- VALIDITY: run this rollback ONLY before any subsequent migration (M-01 .. M-11)
-- has created objects inside the `wallet` schema or granted privileges to these
-- roles. Once later migrations exist, the non-empty-schema and role-dependency
-- guards below make this rollback fail by design (that is the intended safety
-- behavior, not a bug).
--
-- DELIBERATELY NOT REVERSED (do not weaken the security default):
--   * CREATE privilege on the `public` schema for PUBLIC is NOT restored. On
--     PostgreSQL 15+ the public schema no longer grants CREATE to PUBLIC by
--     default, so restoring it here would WEAKEN the security posture. The
--     revocation is intentionally left in place.
--   * CREATE EXTENSION postgis is NOT dropped — the extension is shared and may
--     be depended upon by other schemas/roles.
--   * No passwords were set by M-00, so there is nothing credential-wise to
--     revoke.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Ownership guard: refuse to drop a `wallet` schema not owned by keke_wallet.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1
                 FROM pg_namespace n
                WHERE n.nspname = 'wallet'
                  AND n.nspowner::regrole::text IS DISTINCT FROM 'keke_wallet') THEN
        RAISE EXCEPTION 'refusing to drop schema wallet: owner is not keke_wallet';
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 2. Drop the wallet schema.
--    Fails safely if the schema is non-empty (no CASCADE), protecting objects
--    created by later migrations.
-- ----------------------------------------------------------------------------
DROP SCHEMA IF EXISTS wallet;

-- ----------------------------------------------------------------------------
-- 3. Drop roles. PostgreSQL refuses to drop a role that still owns objects or
--    holds granted privileges, so a role used by later migrations cannot be
--    dropped here — an additional dependency-safe guard.
-- ----------------------------------------------------------------------------
DROP ROLE IF EXISTS keke_outbox_worker;
DROP ROLE IF EXISTS keke_app;
DROP ROLE IF EXISTS keke_wallet;
