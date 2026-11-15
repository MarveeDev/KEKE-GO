-- ============================================================================
-- KEKE — Migration M-08 (outbox infrastructure)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-08)
--                  KEKE_DATABASE_DESIGN.md §10 / §10.1 (outbox_events + workers)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 (roles + wallet schema). Must have run.
--
-- SCOPE (and ONLY this scope):
--   * outbox_events table + its three indexes.
--   * wallet.outbox_claim_result composite type.
--   * Five worker functions: outbox_claim, outbox_renew_lease, outbox_ack,
--     outbox_retry, outbox_dead_letter.
--
--   NOT in this migration:
--   * enqueue_outbox_event() (PROPOSED/OPEN, DB §10.3).
--   * dedup_key / payout.reevaluate / outbox_requeue() (PROPOSED, DB §16.4).
--   * ride.accepted consumer, reconciliation features.
--   * outbox_events TABLE ownership transfer to keke_wallet + keke_app grants —
--     those are part of the M-11 privilege pass, NOT here. (Until M-11 the table
--     is superuser-owned; the SECURITY DEFINER functions below become operational
--     against it once M-11 transfers ownership.)
--
-- SECURITY MODEL (canonical §10.1):
--   * All five functions are SECURITY DEFINER with SET search_path =
--     pg_catalog, wallet, owned by keke_wallet.
--   * PUBLIC EXECUTE is revoked; EXECUTE is granted ONLY to keke_outbox_worker
--     (plus USAGE on the wallet schema and the claim-result type). The worker has
--     NO direct table access.
--   * Claiming uses UPDATE ... FOR UPDATE SKIP LOCKED; every non-claim operation
--     validates status = 'PROCESSING', the matching claim token, and a non-expired
--     lease (OUTBOX_LEASE_NOT_HELD otherwise). At-least-once via lease expiry.
--   * No retry-count limit and no dedup key are invented here (retry-limit
--     enforcement is worker-owned per the design).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- outbox_events — transactional outbox (the durable event source).
--   event_id: stable consumer idempotency key (UNIQUE).
--   status: PENDING / PROCESSING / PROCESSED / DEAD_LETTER.
--   attempts / available_at: retry scheduling; locked_by/locked_until: lease.
-- ----------------------------------------------------------------------------
CREATE TABLE public.outbox_events (
    id             BIGSERIAL PRIMARY KEY,
    event_id       UUID NOT NULL UNIQUE,      -- stable consumer idempotency key
    aggregate_type TEXT NOT NULL,             -- 'ride' | 'payment' | 'notification' | ...
    aggregate_id   UUID NOT NULL,             -- owning aggregate id
    event_type     TEXT NOT NULL,             -- 'payout.submit','ride.accepted'
    payload        JSONB NOT NULL,
    status         TEXT NOT NULL DEFAULT 'PENDING'
                   CHECK (status IN ('PENDING','PROCESSING','PROCESSED','DEAD_LETTER')),
    attempts       INT NOT NULL DEFAULT 0,
    available_at   TIMESTAMPTZ NOT NULL DEFAULT now(),  -- next eligible attempt (retry scheduling)
    locked_by      TEXT,                      -- worker claim marker
    locked_until   TIMESTAMPTZ,               -- lease expiry
    last_error     TEXT,                      -- most recent delivery error
    published_at   TIMESTAMPTZ,               -- first delivery attempt
    processed_at   TIMESTAMPTZ,               -- acked by consumer
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- worker claiming: pending/proc events ordered by next-attempt time
CREATE INDEX idx_outbox_pending
    ON public.outbox_events (status, available_at)
    WHERE status IN ('PENDING','PROCESSING');
CREATE INDEX idx_outbox_locked
    ON public.outbox_events (locked_until)
    WHERE status = 'PROCESSING';
CREATE INDEX idx_outbox_aggregate
    ON public.outbox_events (aggregate_type, aggregate_id);

-- ----------------------------------------------------------------------------
-- wallet.outbox_claim_result — minimal claim result returned to the worker.
-- ----------------------------------------------------------------------------
CREATE TYPE wallet.outbox_claim_result AS (
    event_id     UUID,
    event_type   TEXT,
    payload      JSONB,
    claim_token  UUID,
    locked_until TIMESTAMPTZ,
    attempts     INT
);

-- ----------------------------------------------------------------------------
-- wallet.outbox_claim — atomically claim a batch of eligible events.
--   Validates batch size (1..100) and lease duration (1..300). Uses
--   FOR UPDATE SKIP LOCKED for safe multi-worker concurrency; each claimed row
--   gets its own unguessable UUID claim token.
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.outbox_claim(p_batch INT, p_lease_seconds INT)
RETURNS SETOF wallet.outbox_claim_result
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_batch IS NULL OR p_batch < 1 OR p_batch > 100 THEN
        RAISE EXCEPTION 'INVALID_BATCH_SIZE';
    END IF;
    IF p_lease_seconds IS NULL OR p_lease_seconds < 1 OR p_lease_seconds > 300 THEN
        RAISE EXCEPTION 'INVALID_LEASE_DURATION';
    END IF;

    RETURN QUERY
    UPDATE public.outbox_events e
       SET status = 'PROCESSING',
           locked_by = gen_random_uuid()::text,
           locked_until = clock_timestamp() + make_interval(secs => p_lease_seconds),
           published_at = COALESCE(published_at, clock_timestamp())
     WHERE e.id IN (
         SELECT id FROM public.outbox_events
          WHERE (status = 'PENDING' AND available_at <= clock_timestamp())
             OR (status = 'PROCESSING' AND locked_until < clock_timestamp())
          ORDER BY available_at
          FOR UPDATE SKIP LOCKED
          LIMIT p_batch
     )
     RETURNING e.event_id, e.event_type, e.payload,
               e.locked_by::uuid AS claim_token, e.locked_until, e.attempts;
END;
$$;

-- ----------------------------------------------------------------------------
-- wallet.outbox_renew_lease — extend a held lease. Validates duration and that
-- the caller holds the matching claim token with a non-expired lease.
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.outbox_renew_lease(p_event_id UUID, p_claim_token UUID, p_lease_seconds INT)
RETURNS VOID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_lease_seconds IS NULL OR p_lease_seconds < 1 OR p_lease_seconds > 300 THEN
        RAISE EXCEPTION 'INVALID_LEASE_DURATION';
    END IF;
    UPDATE public.outbox_events
       SET locked_until = clock_timestamp() + make_interval(secs => p_lease_seconds)
     WHERE event_id = p_event_id AND status = 'PROCESSING'
       AND locked_by = p_claim_token::text
       AND locked_until > clock_timestamp();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'OUTBOX_LEASE_NOT_HELD';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- wallet.outbox_ack — mark an event PROCESSED (terminal). Requires a held lease.
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.outbox_ack(p_event_id UUID, p_claim_token UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.outbox_events
       SET status = 'PROCESSED', processed_at = clock_timestamp(),
           locked_by = NULL, locked_until = NULL
     WHERE event_id = p_event_id AND status = 'PROCESSING'
       AND locked_by = p_claim_token::text
       AND locked_until > clock_timestamp();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'OUTBOX_LEASE_NOT_HELD';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- wallet.outbox_retry — return an event to PENDING with backoff. Increments
-- attempts, records last_error, clears the lease. Validates backoff (1..86400).
-- NOTE: no maximum-attempt threshold is enforced here (worker-owned).
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.outbox_retry(p_event_id UUID, p_claim_token UUID, p_error TEXT, p_backoff_seconds INT)
RETURNS VOID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_backoff_seconds IS NULL OR p_backoff_seconds < 1 OR p_backoff_seconds > 86400 THEN
        RAISE EXCEPTION 'INVALID_BACKOFF';
    END IF;
    UPDATE public.outbox_events
       SET status = 'PENDING',
           attempts = attempts + 1, last_error = p_error,
           locked_by = NULL, locked_until = NULL,
           available_at = clock_timestamp() + make_interval(secs => p_backoff_seconds)
     WHERE event_id = p_event_id AND status = 'PROCESSING'
       AND locked_by = p_claim_token::text
       AND locked_until > clock_timestamp();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'OUTBOX_LEASE_NOT_HELD';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- wallet.outbox_dead_letter — mark an event DEAD_LETTER (permanent failure).
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.outbox_dead_letter(p_event_id UUID, p_claim_token UUID, p_error TEXT)
RETURNS VOID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.outbox_events
       SET status = 'DEAD_LETTER', last_error = p_error, locked_by = NULL, locked_until = NULL
     WHERE event_id = p_event_id AND status = 'PROCESSING'
       AND locked_by = p_claim_token::text
       AND locked_until > clock_timestamp();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'OUTBOX_LEASE_NOT_HELD';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- Ownership & privileges (functions/type only; canonical §10.1).
--   keke_wallet owns the type + functions (SECURITY DEFINER runs as keke_wallet).
--   REVOKE ALL FROM PUBLIC; EXECUTE granted ONLY to keke_outbox_worker, plus the
--   schema/type USAGE it needs to resolve and consume the functions. The worker
--   has NO direct table access.
--   outbox_events TABLE ownership + keke_app grants remain in M-11.
-- ----------------------------------------------------------------------------
ALTER TYPE     wallet.outbox_claim_result                         OWNER TO keke_wallet;
ALTER FUNCTION wallet.outbox_claim(INT, INT)                      OWNER TO keke_wallet;
ALTER FUNCTION wallet.outbox_renew_lease(UUID, UUID, INT)         OWNER TO keke_wallet;
ALTER FUNCTION wallet.outbox_ack(UUID, UUID)                      OWNER TO keke_wallet;
ALTER FUNCTION wallet.outbox_retry(UUID, UUID, TEXT, INT)         OWNER TO keke_wallet;
ALTER FUNCTION wallet.outbox_dead_letter(UUID, UUID, TEXT)        OWNER TO keke_wallet;

REVOKE ALL ON FUNCTION wallet.outbox_claim(INT, INT)              FROM PUBLIC;
REVOKE ALL ON FUNCTION wallet.outbox_renew_lease(UUID, UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION wallet.outbox_ack(UUID, UUID)              FROM PUBLIC;
REVOKE ALL ON FUNCTION wallet.outbox_retry(UUID, UUID, TEXT, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION wallet.outbox_dead_letter(UUID, UUID, TEXT) FROM PUBLIC;

GRANT USAGE ON SCHEMA wallet TO keke_outbox_worker;
GRANT USAGE ON TYPE   wallet.outbox_claim_result                    TO keke_outbox_worker;
GRANT EXECUTE ON FUNCTION wallet.outbox_claim(INT, INT)             TO keke_outbox_worker;
GRANT EXECUTE ON FUNCTION wallet.outbox_renew_lease(UUID, UUID, INT) TO keke_outbox_worker;
GRANT EXECUTE ON FUNCTION wallet.outbox_ack(UUID, UUID)             TO keke_outbox_worker;
GRANT EXECUTE ON FUNCTION wallet.outbox_retry(UUID, UUID, TEXT, INT) TO keke_outbox_worker;
GRANT EXECUTE ON FUNCTION wallet.outbox_dead_letter(UUID, UUID, TEXT) TO keke_outbox_worker;
