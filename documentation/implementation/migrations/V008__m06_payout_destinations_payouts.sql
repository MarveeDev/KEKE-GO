-- ============================================================================
-- KEKE — Migration M-06 (payout destinations & payouts)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-06)
--                  KEKE_DATABASE_DESIGN.md §8.1 (payout_destinations),
--                  §8.2 (payouts), §8.4 (payout_events)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-01 (drivers). Must have run.
--
-- SCOPE (and ONLY this scope):
--   * payout_destinations, payouts, payout_events.
--   * NO wallet functions (M-10), NO ledger (M-07), NO callback disposition /
--     integrity-conflict / orphan-callback tables, NO processing_started_at /
--     dedup_key / outbox_requeue (all PROPOSED/OPEN).
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Tables created in `public`; ownership transfer to keke_wallet and grants
--     are applied in the M-11 privilege pass, not here. No GRANT/REVOKE here.
--
-- TERMINAL-STATES NOTE: COMPLETED / REJECTED are terminal and never reopened.
--   This is enforced by the SECURITY DEFINER wallet functions (M-10), not by a
--   DB CHECK here — the status CHECK only limits the value set.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- payout_destinations — a driver's registered MoMo payout destination.
--   destination_type is MOBILE_MONEY only (MVP).
--   phone carries the canonical E.164 CHECK (this is where the design defines
--   the format constraint; users.phone has no such CHECK).
--   UNIQUE (id, driver_id) is the composite FK target for payouts ownership.
-- ----------------------------------------------------------------------------
CREATE TABLE public.payout_destinations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id        UUID NOT NULL REFERENCES public.drivers(user_id),
    destination_type TEXT NOT NULL DEFAULT 'MOBILE_MONEY'
                     CHECK (destination_type IN ('MOBILE_MONEY')),
    phone            TEXT NOT NULL,                 -- E.164, e.g. +233241234567
    status           TEXT NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','VERIFIED')),
    verified_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),          -- E.164
    UNIQUE (id, driver_id)                            -- FK target for payout ownership
);

CREATE INDEX idx_payout_destinations_driver
    ON public.payout_destinations (driver_id);

-- ----------------------------------------------------------------------------
-- payouts — a driver's payout request + workflow record.
--   Composite FK fk_payouts_destination_owner enforces that destination_id
--   belongs to driver_id (destination ownership). There is deliberately NO
--   separate single-column FK on destination_id.
--   status: PENDING / PROCESSING / COMPLETED / REJECTED (terminal).
--   Journal correlation (convention, enforced by M-07's uq_journal_payout_correlation):
--     original  = payouts.id::text
--     reversal  = payouts.id::text || ':reversal'
--   rejection_provider_event_id records the verified FAILURE event id for
--   traceability (NULL for a synchronous disburse rejection).
-- ----------------------------------------------------------------------------
CREATE TABLE public.payouts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id        UUID NOT NULL REFERENCES public.drivers(user_id),
    destination_id   UUID NOT NULL,
    amount           NUMERIC(12,2) NOT NULL CHECK (amount > 0),  -- GHS
    status           TEXT NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','PROCESSING','COMPLETED','REJECTED')),
    provider_ref     TEXT,                     -- provider disbursement reference
    rejection_reason TEXT,
    rejection_provider_event_id TEXT,          -- verified FAILURE event id (traceability)
    requested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at     TIMESTAMPTZ,
    version          INT NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- destination must belong to the same driver
    CONSTRAINT fk_payouts_destination_owner
        FOREIGN KEY (destination_id, driver_id)
        REFERENCES public.payout_destinations (id, driver_id)
);

CREATE INDEX idx_payouts_driver ON public.payouts (driver_id, created_at DESC);
CREATE INDEX idx_payouts_status ON public.payouts (status)
    WHERE status IN ('PENDING','PROCESSING');

-- ----------------------------------------------------------------------------
-- payout_events — immutable provider disbursement callback log.
--   provider + provider_event_id are NOT NULL (authenticated callbacks only).
--   event_type: SUCCESS / FAILURE / UNKNOWN. No `disposition` column (that is a
--   PROPOSED/OPEN addition, DB §16.1 — deliberately NOT implemented).
--   uq_payout_events_provider is a full (non-partial) unique index.
-- ----------------------------------------------------------------------------
CREATE TABLE public.payout_events (
    id                BIGSERIAL PRIMARY KEY,
    payout_id         UUID NOT NULL REFERENCES public.payouts(id),
    provider          TEXT NOT NULL,           -- 'HUBTEL' | 'PAYSTACK' (authenticated callbacks)
    provider_event_id TEXT NOT NULL,           -- provider's unique event id
    event_type        TEXT NOT NULL CHECK (event_type IN ('SUCCESS','FAILURE','UNKNOWN')),
    payload           JSONB NOT NULL,           -- raw provider event (sanitized)
    sha256            TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_payout_events_provider
    ON public.payout_events (provider, provider_event_id);
