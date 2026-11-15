-- ============================================================================
-- KEKE — Migration M-01 (users & role profiles)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-01)
--                  KEKE_DATABASE_DESIGN.md §4.1 (users, passengers, drivers, admins)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 (roles + wallet schema + PostGIS) — M-00 must have run.
--
-- SCOPE (and ONLY this scope):
--   * users, passengers, drivers, admins (identity/profile aggregates).
--   * NO auth_sessions / otp_codes (PENDING — later migration).
--   * NO vehicles/documents (M-02), rides/payments/ledger/outbox/audit (M-04+),
--     and NO wallet functions (M-07 .. M-10).
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * These are application tables and live in the `public` schema (as in the
--     canonical design). They are NOT transferred to keke_wallet, which owns only
--     the ledger/payout/outbox tables (transferred in a later migration).
--   * No GRANT/REVOKE is issued here. Application DML privileges are a later
--     privilege-pass concern and are intentionally NOT invented in M-01.
--   * No passwords/credentials. No unrestricted privileges.
--
-- UUIDs: gen_random_uuid() is PostgreSQL core since v13 (no pgcrypto needed).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- users — single identity table for all roles (passenger / driver / admin).
--   phone: canonical E.164 login identity (UNIQUE). No format CHECK is imposed
--          here because the canonical design does not define one for users.
--   role : fixed CHECK — role is resolved server-side, never client-controlled.
--   status: account-level gate (ACTIVE / SUSPENDED / DEACTIVATED).
-- ----------------------------------------------------------------------------
CREATE TABLE public.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role            TEXT NOT NULL CHECK (role IN ('passenger','driver','admin')),
    phone           TEXT NOT NULL UNIQUE,          -- E.164, e.g. +233...
    email           TEXT UNIQUE,
    first_name      TEXT,
    last_name       TEXT,
    avatar_url      TEXT,
    status          TEXT NOT NULL DEFAULT 'ACTIVE'
                    CHECK (status IN ('ACTIVE','SUSPENDED','DEACTIVATED')),
    version         INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- passengers — 1:1 passenger profile. PK is the users FK (cascades on delete).
-- ----------------------------------------------------------------------------
CREATE TABLE public.passengers (
    user_id             UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    rating_avg          NUMERIC(3,2) NOT NULL DEFAULT 0,
    rating_count        INT NOT NULL DEFAULT 0,
    saved_places        JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- ----------------------------------------------------------------------------
-- drivers — 1:1 driver profile.
--   driver_status: driver-domain lifecycle, DISTINCT from users.status (the
--     account-level gate). Dispatch eligibility requires users.status=ACTIVE,
--     drivers.driver_status=ACTIVE, drivers.verification_status=APPROVED, and an
--     approved vehicle (see KEKE_DISPATCH_ENGINE.md). Online/offline is NOT
--     stored here — it lives in driver_availability (M-03).
-- ----------------------------------------------------------------------------
CREATE TABLE public.drivers (
    user_id             UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    driver_status       TEXT NOT NULL DEFAULT 'ONBOARDING'
                        CHECK (driver_status IN ('ONBOARDING','ACTIVE','SUSPENDED','DEACTIVATED')),
    verification_status TEXT NOT NULL DEFAULT 'PENDING'
                        CHECK (verification_status IN ('PENDING','IN_REVIEW','APPROVED','REJECTED')),
    rating_avg          NUMERIC(3,2) NOT NULL DEFAULT 0,
    rating_count        INT NOT NULL DEFAULT 0,
    license_number      TEXT,
    version             INT NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- admins — 1:1 admin profile with RBAC role (SUPER_ADMIN / OPS / SUPPORT / FINANCE).
-- ----------------------------------------------------------------------------
CREATE TABLE public.admins (
    user_id     UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    admin_role  TEXT NOT NULL CHECK (admin_role IN ('SUPER_ADMIN','OPS','SUPPORT','FINANCE')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
