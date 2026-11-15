-- ============================================================================
-- KEKE — Migration M-02 (vehicles & verification documents)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-02)
--                  KEKE_DATABASE_DESIGN.md §4.2 (driver_vehicles, verification_documents)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-01 (drivers, admins) — M-00 and M-01 must have run.
--
-- SCOPE (and ONLY this scope):
--   * driver_vehicles, verification_documents.
--   * NO rides/payments/ledger/outbox/audit, NO wallet functions.
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Application tables in `public`, NOT transferred to keke_wallet.
--   * No GRANT/REVOKE issued here (privileges are a later concern).
--   * No passwords/credentials. No unrestricted privileges.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- driver_vehicles — a driver's registered vehicle (keke).
--   UNIQUE (id, driver_id) is the composite FK target that later lets a `rides`
--   row enforce "the vehicle belongs to the assigned driver" (M-04, the
--   fk_rides_vehicle_owner constraint).
--   status: PENDING / APPROVED / REJECTED / SUSPENDED (canonical).
-- ----------------------------------------------------------------------------
CREATE TABLE public.driver_vehicles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES public.drivers(user_id),
    type                TEXT NOT NULL DEFAULT 'KEKE',   -- vehicle class
    make                TEXT,
    model               TEXT,
    color               TEXT,
    plate_number        TEXT UNIQUE,
    registration_number TEXT,
    passenger_capacity  SMALLINT NOT NULL DEFAULT 3,
    status              TEXT NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
    approved_by         UUID REFERENCES public.admins(user_id),
    approved_at         TIMESTAMPTZ,
    version             INT NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, driver_id)              -- FK target enforcing ride→vehicle ownership
);

-- ----------------------------------------------------------------------------
-- verification_documents — driver/vehicle documents submitted for review.
--   vehicle_id is NULL for driver-level documents (license, national id, photo).
--   object_key + sha256 record the object-storage key and its content digest.
--   status: PENDING / IN_REVIEW / APPROVED / REJECTED (canonical).
-- ----------------------------------------------------------------------------
CREATE TABLE public.verification_documents (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id        UUID NOT NULL REFERENCES public.drivers(user_id),
    vehicle_id       UUID REFERENCES public.driver_vehicles(id),  -- null for driver docs
    document_type    TEXT NOT NULL CHECK (document_type IN
                     ('DRIVER_LICENSE','NATIONAL_ID','VEHICLE_REGISTRATION',
                      'INSURANCE','ROADWORTHINESS','PROFILE_PHOTO','OTHER')),
    object_key       TEXT NOT NULL,          -- object storage key
    sha256           TEXT NOT NULL,          -- content digest for integrity
    status           TEXT NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','IN_REVIEW','APPROVED','REJECTED')),
    rejection_reason TEXT,
    reviewed_by      UUID REFERENCES public.admins(user_id),
    reviewed_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
