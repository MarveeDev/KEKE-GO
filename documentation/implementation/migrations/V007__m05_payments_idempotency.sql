-- ============================================================================
-- KEKE — Migration M-05 (payments & idempotency)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-05)
--                  KEKE_DATABASE_DESIGN.md §8 (payments, payment_events),
--                  §8.3 (idempotency_keys)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-04 (rides), M-01 (users). Both must have run.
--
-- SCOPE (and ONLY this scope): payments, payment_events, idempotency_keys.
--   * NO payouts/payout_destinations/payout_events (M-06), NO ledger/wallet
--     functions (M-07/M-10), NO callback reconciliation (PROPOSED).
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Tables created in `public`. Ownership transfer (idempotency_keys →
--     keke_wallet) and grants are applied in a LATER privilege pass (M-11), not
--     here. No GRANT/REVOKE issued here. No unrestricted privileges.
--
-- MONEY: DB stores GHS as NUMERIC(12,2); the API exposes integer pesewas (÷100).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- payments — one charge per ride.
--   provider_ref = provider TRANSACTION id (shared by all its events).
--   idempotency_key = client-supplied dedup key (UNIQUE). NOTE: its precedence
--   vs the generic idempotency_keys table is an OPEN decision (API §11.3); both
--   are preserved here as documented.
--   method: CASH | MOBILE_MONEY. status: PENDING/AUTHORIZED/CAPTURED/FAILED/REFUNDED/EXPIRED.
-- ----------------------------------------------------------------------------
CREATE TABLE public.payments (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id          UUID NOT NULL REFERENCES public.rides(id),
    payer_user_id    UUID NOT NULL REFERENCES public.users(id),
    amount           NUMERIC(12,2) NOT NULL,
    currency         TEXT NOT NULL DEFAULT 'GHS',
    method           TEXT NOT NULL CHECK (method IN ('CASH','MOBILE_MONEY')),
    status           TEXT NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','AUTHORIZED','CAPTURED','FAILED','REFUNDED','EXPIRED')),
    provider         TEXT,                     -- 'HUBTEL' | 'PAYSTACK' | null for cash
    provider_ref     TEXT,                     -- provider transaction id (shared by all its events)
    idempotency_key  TEXT NOT NULL UNIQUE,     -- client-supplied, dedupes retries
    version          INT NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- payment_events — immutable webhook/event log.
--   provider_event_id = provider's UNIQUE webhook event id (distinct from
--   payments.provider_ref, the transaction id).
--   Partial unique index uq_payment_events_provider dedupes replayed webhooks.
-- ----------------------------------------------------------------------------
CREATE TABLE public.payment_events (
    id                BIGSERIAL PRIMARY KEY,
    payment_id        UUID NOT NULL REFERENCES public.payments(id),
    provider          TEXT,              -- 'HUBTEL' | 'PAYSTACK' | null (manual)
    provider_event_id TEXT,              -- provider's unique webhook event id (distinct from provider_ref)
    event_type        TEXT NOT NULL,     -- 'WEBHOOK','CALLBACK','REFUND','MANUAL'
    payload           JSONB NOT NULL,    -- raw provider event (sanitized)
    sha256            TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- a provider event is processed at most once
CREATE UNIQUE INDEX uq_payment_events_provider
    ON public.payment_events (provider, provider_event_id)
    WHERE provider_event_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- idempotency_keys — generic request idempotency contract (API §11.1).
--   principal_id is a bare UUID (authenticated user id; NOT FK'd — canonical).
--   key_hash / payload_hash are sha256 hex. UNIQUE (principal_id, operation,
--   key_hash) is the final dedup safeguard.
--   expires_at = created_at + 24h (retention); purged by a background job.
-- ----------------------------------------------------------------------------
CREATE TABLE public.idempotency_keys (
    id               BIGSERIAL PRIMARY KEY,
    principal_id     UUID NOT NULL,               -- authenticated user id
    operation        TEXT NOT NULL,               -- e.g. 'POST /payouts'
    key_hash         TEXT NOT NULL,               -- sha256 hex of the client key
    payload_hash     TEXT NOT NULL,               -- sha256 hex of canonical payload
    status           TEXT NOT NULL DEFAULT 'IN_PROGRESS'
                     CHECK (status IN ('IN_PROGRESS','COMPLETED')),
    lease_owner      TEXT,                        -- worker/request holding the lease
    lease_expires_at TIMESTAMPTZ,                 -- lease expiry (fencing)
    lease_generation BIGINT NOT NULL DEFAULT 0,   -- fencing generation
    response_json    JSONB,                       -- stored original response
    resource_ref     TEXT,                        -- resulting resource id/version
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ NOT NULL,        -- 24h retention
    UNIQUE (principal_id, operation, key_hash)
);

CREATE INDEX idx_idempotency_expiry ON public.idempotency_keys (expires_at)
    WHERE status = 'COMPLETED';
CREATE INDEX idx_idempotency_lease ON public.idempotency_keys (lease_expires_at)
    WHERE status = 'IN_PROGRESS';
