-- ============================================================================
-- KEKE — Migration M-00 (foundations: extensions, roles, schema, security)
-- ----------------------------------------------------------------------------
-- Source of truth:
--   * KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-00) and §5.1 (roles)
--   * KEKE_DATABASE_DESIGN.md §9 (bootstrap block)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
--
-- SCOPE (and ONLY this scope):
--   1. Enable the PostGIS extension.
--   2. Create the three database roles (keke_wallet, keke_app, keke_outbox_worker).
--   3. Verify role attributes (reject incompatible pre-existing roles).
--   4. Create the `wallet` schema owned by `keke_wallet`.
--   5. Apply the initial privilege restrictions (REVOKE CREATE).
--   6. Verify `wallet` schema ownership.
--
-- NOT in this migration: application tables, wallet functions, ledger tables,
-- outbox tables, audit_logs, or the privilege-pass (SELECT/EXECUTE/USAGE grants).
-- Those belong to migrations M-01 .. M-11.
--
-- SECURITY DECISIONS:
--   * NO passwords are set or invented here. LOGIN roles are created without a
--     password; credentials MUST be provisioned out-of-band by the deployment
--     pipeline (secrets manager / `ALTER ROLE ... PASSWORD`) and MUST NEVER be
--     committed to the repository.
--   * All roles are created with the restrictive attributes (NOSUPERUSER,
--     NOCREATEDB, NOCREATEROLE, NOREPLICATION, NOBYPASSRLS). These are the
--     PostgreSQL defaults, stated explicitly as a documented security boundary.
--   * keke_wallet is NOLOGIN: it is an owner/group role, not a login identity.
--   * keke_app and keke_outbox_worker are LOGIN roles used by the application
--     and the outbox worker respectively.
--   * Per the canonical design, keke_app is NEVER granted membership in
--     keke_wallet (so it cannot SET ROLE to the owner).
--
-- IDEMPOTENCY NOTE: role creation is guarded by pg_roles existence checks so the
-- migration is a no-op on re-run. Attribute drift on a PRE-EXISTING role is
-- DETECTED (see step 3 verification, which raises) — the migration does NOT
-- ALTER existing roles.
--
-- EXECUTION REQUIREMENTS (no credentials embedded):
--   * M-00 must be executed by a PostgreSQL SUPERUSER (or an equivalent
--     bootstrap role). Two statements require it:
--       - CREATE EXTENSION postgis — PostGIS is an UNTRUSTED extension whose
--         installation requires elevated privileges.
--       - CREATE SCHEMA ... AUTHORIZATION keke_wallet — creating a schema owned
--         by a role the caller is not a member of requires superuser.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Extensions
-- ----------------------------------------------------------------------------
-- PostGIS is required for the GEOGRAPHY columns introduced in later migrations
-- (driver_availability, pricing_zones, ride_locations). Enabling it here keeps
-- all geo-dependent DDL in later migrations unconditional.
CREATE EXTENSION IF NOT EXISTS postgis;

-- NOTE: gen_random_uuid() is provided by PostgreSQL core since v13 (no pgcrypto
-- needed on PG16). It is referenced by later migrations as a PK default.

-- ----------------------------------------------------------------------------
-- 2. Roles (idempotent creation; restrictive attributes)
-- ----------------------------------------------------------------------------

-- keke_wallet: NOLOGIN owner role for the `wallet` schema and all financial
-- SECURITY DEFINER functions (created in M-07 .. M-10). No login capability.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keke_wallet') THEN
        CREATE ROLE keke_wallet
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
END
$$;

-- keke_app: LOGIN role for the NestJS application services. Least privilege: it
-- will receive only SELECT on ledger tables and EXECUTE on the controlled wallet
-- writers in M-11. It is NOT a member of keke_wallet.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keke_app') THEN
        CREATE ROLE keke_app
            LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
END
$$;

-- keke_outbox_worker: LOGIN role for the outbox delivery worker. No direct table
-- access; it will receive only EXECUTE on the claim/renew/ack/retry/dead-letter
-- functions in M-11.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keke_outbox_worker') THEN
        CREATE ROLE keke_outbox_worker
            LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 3. Verify role attributes (reject incompatible pre-existing roles)
-- ----------------------------------------------------------------------------
-- The guards above skip creation when a role already exists. This step rejects
-- any pre-existing role whose attributes break the security boundary. It never
-- ALTERs a role — incompatible state raises and must be reconciled out-of-band.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole,
               rolreplication, rolbypassrls
          FROM pg_roles
         WHERE rolname IN ('keke_wallet', 'keke_app', 'keke_outbox_worker')
    LOOP
        IF r.rolsuper
           OR r.rolcreatedb
           OR r.rolcreaterole
           OR r.rolreplication
           OR r.rolbypassrls THEN
            RAISE EXCEPTION
                'role % has incompatible attributes (rolsuper/rolcreatedb/rolcreaterole/rolreplication/rolbypassrls must all be false)',
                r.rolname;
        END IF;

        CASE r.rolname
            WHEN 'keke_wallet' THEN
                IF r.rolcanlogin THEN
                    RAISE EXCEPTION 'role keke_wallet must be NOLOGIN (rolcanlogin must be false)';
                END IF;
            WHEN 'keke_app', 'keke_outbox_worker' THEN
                IF NOT r.rolcanlogin THEN
                    RAISE EXCEPTION 'role % must be LOGIN (rolcanlogin must be true)', r.rolname;
                END IF;
            ELSE
                RAISE EXCEPTION 'unexpected role name %', r.rolname;
        END CASE;
    END LOOP;
END
$$;

-- ----------------------------------------------------------------------------
-- 4. wallet schema (owned by keke_wallet)
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS wallet AUTHORIZATION keke_wallet;

-- ----------------------------------------------------------------------------
-- 5. Initial privilege restrictions (approved for M-00)
-- ----------------------------------------------------------------------------
-- Remove the default PUBLIC CREATE on the public schema (defense-in-depth; on
-- PostgreSQL 15+ this is already the default, on PG14 and earlier it is not).
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- No untrusted or application role may create objects in the wallet schema.
REVOKE CREATE ON SCHEMA wallet FROM PUBLIC;

-- Belt-and-suspenders: explicitly revoke CREATE from the application role even
-- though the PUBLIC revoke above already covers it (mirrors the canonical
-- bootstrap block verbatim).
REVOKE CREATE ON SCHEMA public FROM keke_app;
REVOKE CREATE ON SCHEMA wallet FROM keke_app;

-- ----------------------------------------------------------------------------
-- 6. Ownership verification (fail loudly if not keke_wallet-owned)
-- ----------------------------------------------------------------------------
-- The design requires ownership to be explicitly verified, not assumed from
-- CREATE SCHEMA ... AUTHORIZATION: a pre-existing schema with a different owner
-- must not slip through (CREATE SCHEMA IF NOT EXISTS would otherwise leave it).
DO $$
BEGIN
    IF (SELECT n.nspowner::regrole::text
          FROM pg_namespace n
         WHERE n.nspname = 'wallet') IS DISTINCT FROM 'keke_wallet' THEN
        RAISE EXCEPTION 'wallet schema is not owned by keke_wallet';
    END IF;
END
$$;
