-- ============================================================================
-- KEKE — Migration M-10 (wallet writers)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-10), §8 (acceptance)
--                  KEKE_DATABASE_DESIGN.md §9 (the seven SECURITY DEFINER writers)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 (roles + wallet schema), M-06 (payouts/payout_destinations/
--             payout_events), M-07 (ledger + helpers + trigger), M-08 (outbox_events).
--
-- SCOPE (and ONLY this scope): the seven wallet writers below.
--   * NO new tables/indexes/types/triggers.
--   * NO enqueue_outbox_event() / outbox_requeue() / reconciliation / callback
--     integrity tables / new roles / SQLSTATE changes.
--
-- SECURITY:
--   * All seven functions are SECURITY DEFINER, SET search_path =
--     pg_catalog, wallet, owned by keke_wallet.
--   * PUBLIC execution revoked; EXECUTE granted ONLY to keke_app.
--   * keke_outbox_worker is NOT granted these functions.
--
-- FINANCIAL INVARIANTS (canonical §9):
--   * Hash chain: every money-mover locks the singleton ledger_head FOR UPDATE,
--     assigns seq = head.seq + 1, writes header+lines, then advances the head —
--     all in one transaction. prev_hash = head.last_hash.
--   * Double-entry: the deferred trg_journal_entry_balanced (M-07) revalidates
--     balance / single currency / entry_hash at COMMIT.
--   * Payout correlation: original = payout_id::text; reversal = payout_id::text
--     || ':reversal' (enforced by uq_journal_payout_correlation).
--   * Balance floor: request_payout rejects INSUFFICIENT_BALANCE under the wallet
--     lock (payout-specific guard; not a blanket negative-balance restriction).
--   * Terminal states: COMPLETED/REJECTED are never re-transitioned; each guarded
--     transition raises INVALID_PAYOUT_STATE otherwise.
--   * Provider-ref protection: PROVIDER_REF_CONFLICT on differing refs.
--
-- OPEN SECURITY ISSUE (production deployment blocker):
--   * append_journal_entry is granted broad EXECUTE to keke_app and accepts any
--     of the six entry types against arbitrary existing accounts (no
--     entry-type/account-pair allowlist). This is the canonical documented
--     behavior; it is PRESERVED here and NOT silently changed. An authorization
--     allowlist is an OPEN decision that must be resolved before production.
--
-- INTERIM OWNERSHIP NOTE: these writers reference public.payouts,
--   public.payout_destinations, public.payout_events and public.outbox_events,
--   whose keke_wallet ownership transfer lands in M-11. The writers are defined
--   here and become operational after M-11. (append_journal_entry is operational
--   immediately — its ledger tables were transferred in M-07.)
-- ============================================================================

-- ============================================================================
-- 1. append_journal_entry — complete, single-transaction journal writer.
-- ============================================================================
CREATE FUNCTION wallet.append_journal_entry(
    p_entry_type     TEXT,
    p_correlation_id TEXT,
    p_description    TEXT,
    p_lines          JSONB        -- [{account_id, amount, is_debit}, ...]
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_seq             BIGINT;
    v_last_hash       TEXT;
    v_entry_id        UUID := gen_random_uuid();
    v_canonical_lines TEXT;
    v_entry_hash      TEXT;
    v_line            RECORD;
    v_running         NUMERIC(16,2);
    v_balance_after   NUMERIC(16,2);
BEGIN
    -- 1. Lock + read the ledger head; fail loudly if absent (never silent).
    SELECT seq, last_hash INTO v_seq, v_last_hash
      FROM public.ledger_head WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ledger_head is not initialized';
    END IF;
    v_seq := v_seq + 1;

    -- 2. Validate input shape.
    IF jsonb_typeof(p_lines) <> 'array' THEN
        RAISE EXCEPTION 'p_lines must be a JSON array';
    END IF;
    IF jsonb_array_length(p_lines) < 2 THEN
        RAISE EXCEPTION 'journal entry requires at least two lines';
    END IF;

    -- 3a. Each line must have the correct JSON types. IS DISTINCT FROM rejects a
    --     missing property explicitly (jsonb_typeof(NULL) is NULL, not 'string').
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_lines) AS l
        WHERE jsonb_typeof(l->'account_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(l->'amount') IS DISTINCT FROM 'number'
           OR jsonb_typeof(l->'is_debit') IS DISTINCT FROM 'boolean'
    ) THEN
        RAISE EXCEPTION 'invalid journal line: account_id must be a UUID string, amount a JSON number, is_debit a JSON boolean';
    END IF;

    -- 3b. account_id must be a syntactically valid UUID.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_lines) AS l
        WHERE (l->>'account_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ) THEN
        RAISE EXCEPTION 'invalid account_id: not a UUID';
    END IF;

    -- 3c. amount must be positive with at most two decimal places (reject >2dp
    --     rather than silently rounding) and within NUMERIC(16,2) range.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_lines) AS l
        WHERE (l->>'amount') !~ '^\d+(\.\d{1,2})?$'
           OR (l->>'amount')::numeric(16,2) <= 0
    ) THEN
        RAISE EXCEPTION 'invalid amount: must be positive with at most two decimal places';
    END IF;

    -- 4. Reject unknown accounts and mixed currencies.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_lines) AS l
        LEFT JOIN public.ledger_accounts a ON a.id = (l->>'account_id')::uuid
        WHERE a.id IS NULL
    ) THEN
        RAISE EXCEPTION 'unknown account id in journal lines';
    END IF;
    IF (SELECT count(DISTINCT a.currency)
          FROM jsonb_array_elements(p_lines) AS l
          JOIN public.ledger_accounts a ON a.id = (l->>'account_id')::uuid) <> 1 THEN
        RAISE EXCEPTION 'journal entry must have a single currency';
    END IF;

    -- 5. Lock affected accounts in deterministic account-ID order (deadlock-free).
    PERFORM a.id
      FROM public.ledger_accounts a
     WHERE a.id IN (SELECT (l->>'account_id')::uuid FROM jsonb_array_elements(p_lines) AS l)
     ORDER BY a.id
     FOR UPDATE;

    -- 6. Canonical lines + entry hash (byte-identical to the trigger).
    SELECT string_agg(
               wallet.canonical_line((l.elem->>'account_id')::uuid, a.currency,
                                      (l.elem->>'amount')::numeric(16,2),
                                      (l.elem->>'is_debit')::boolean),
               '|' ORDER BY l.ord)
      INTO v_canonical_lines
      FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS l(elem, ord)
      JOIN public.ledger_accounts a ON a.id = (l.elem->>'account_id')::uuid;
    v_entry_hash := wallet.journal_entry_hash(
        wallet.canonical_entry(v_seq, p_entry_type, p_correlation_id,
                               v_last_hash, v_canonical_lines));

    -- 7. Insert the header.
    INSERT INTO public.journal_entries
        (id, seq, entry_type, correlation_id, description, prev_hash, entry_hash)
    VALUES
        (v_entry_id, v_seq, p_entry_type, p_correlation_id, p_description,
         v_last_hash, v_entry_hash);

    -- 8. Insert each line, computing balance_after per account (rows are already
    --    locked in step 5; each line's balance is read and projected in order).
    FOR v_line IN
        SELECT (l.elem->>'account_id')::uuid      AS account_id,
               (l.elem->>'amount')::numeric(16,2) AS amount,
               (l.elem->>'is_debit')::boolean     AS is_debit
          FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS l(elem, ord)
         ORDER BY l.ord
    LOOP
        SELECT balance INTO v_running
          FROM public.ledger_accounts WHERE id = v_line.account_id FOR UPDATE;
        IF v_line.is_debit THEN
            v_balance_after := v_running - v_line.amount;
        ELSE
            v_balance_after := v_running + v_line.amount;
        END IF;
        INSERT INTO public.journal_lines
            (journal_entry_id, account_id, currency, amount, is_debit, balance_after)
        SELECT v_entry_id, v_line.account_id, a.currency, v_line.amount,
               v_line.is_debit, v_balance_after
          FROM public.ledger_accounts a WHERE a.id = v_line.account_id;
        UPDATE public.ledger_accounts
           SET balance = v_balance_after, version = version + 1
         WHERE id = v_line.account_id;
    END LOOP;

    -- 9. Advance the head in the same transaction.
    UPDATE public.ledger_head
       SET seq = v_seq, last_hash = v_entry_hash, updated_at = now()
     WHERE id = 1;

    RETURN v_entry_id;
END;
$$;

ALTER FUNCTION wallet.append_journal_entry(TEXT, TEXT, TEXT, JSONB) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.append_journal_entry(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.append_journal_entry(TEXT, TEXT, TEXT, JSONB) TO keke_app;

-- ============================================================================
-- 2. request_payout — driver payout request (idempotency-wrapped by the API).
--    Debits DRIVER_WALLET, credits MOMO_CLEARING; creates the payouts row.
-- ============================================================================
CREATE FUNCTION wallet.request_payout(
    p_driver_id      UUID,
    p_destination_id UUID,
    p_amount         NUMERIC(16,2)   -- GHS (API converts integer pesewas -> GHS)
) RETURNS UUID                       -- payout_id (journal correlation_id)
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_seq              BIGINT;
    v_last_hash        TEXT;
    v_entry_id         UUID := gen_random_uuid();
    v_payout_id        UUID := gen_random_uuid();
    v_wallet_id        UUID;
    v_clearing_id      UUID;
    v_currency         TEXT;
    v_wallet_balance   NUMERIC(16,2);
    v_clearing_balance NUMERIC(16,2);
    v_canonical        TEXT;
    v_entry_hash       TEXT;
BEGIN
    -- 1. Validate the amount (reject NULL/zero/negative).
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_AMOUNT';
    END IF;

    -- 2. Serialize journal appends.
    SELECT seq, last_hash INTO v_seq, v_last_hash
      FROM public.ledger_head WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ledger_head is not initialized';
    END IF;
    v_seq := v_seq + 1;

    -- 3. Validate and lock the payout destination: owned by this driver, verified.
    PERFORM 1
      FROM public.payout_destinations d
     WHERE d.id = p_destination_id
       AND d.driver_id = p_driver_id
       AND d.status = 'VERIFIED'
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_DESTINATION';
    END IF;

    -- 4. Lock and resolve the driver wallet and the MoMo clearing account.
    SELECT a.id, a.currency INTO v_wallet_id, v_currency
      FROM public.ledger_accounts a
     WHERE a.account_type = 'DRIVER_WALLET' AND a.owner_user_id = p_driver_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'driver wallet not found';
    END IF;

    SELECT id INTO v_clearing_id
      FROM public.ledger_accounts
     WHERE account_type = 'MOMO_CLEARING' AND currency = v_currency
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MOMO_CLEARING account not found';
    END IF;

    -- 5. Payout-specific available-balance check, under the wallet lock.
    SELECT balance INTO v_wallet_balance
      FROM public.ledger_accounts WHERE id = v_wallet_id;
    IF v_wallet_balance < p_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE';
    END IF;
    SELECT balance INTO v_clearing_balance
      FROM public.ledger_accounts WHERE id = v_clearing_id;

    -- 6. Canonical lines + entry hash (debit wallet, credit clearing).
    v_canonical := wallet.canonical_line(v_wallet_id,   v_currency, p_amount, true)  || '|' ||
                   wallet.canonical_line(v_clearing_id, v_currency, p_amount, false);
    v_entry_hash := wallet.journal_entry_hash(
        wallet.canonical_entry(v_seq, 'PAYOUT', v_payout_id::text, v_last_hash, v_canonical));

    -- 7. Journal header + balanced lines.
    INSERT INTO public.journal_entries
        (id, seq, entry_type, correlation_id, description, prev_hash, entry_hash)
    VALUES
        (v_entry_id, v_seq, 'PAYOUT', v_payout_id::text, 'driver payout', v_last_hash, v_entry_hash);

    INSERT INTO public.journal_lines
        (journal_entry_id, account_id, currency, amount, is_debit, balance_after)
    VALUES
        (v_entry_id, v_wallet_id,   v_currency, p_amount, true,  v_wallet_balance   - p_amount),
        (v_entry_id, v_clearing_id, v_currency, p_amount, false, v_clearing_balance + p_amount);

    -- 8. Project account balances and bump versions.
    UPDATE public.ledger_accounts SET balance = balance - p_amount, version = version + 1
     WHERE id = v_wallet_id;
    UPDATE public.ledger_accounts SET balance = balance + p_amount, version = version + 1
     WHERE id = v_clearing_id;

    -- 9. Insert the payout workflow record (correlation_id == this id).
    INSERT INTO public.payouts
        (id, driver_id, destination_id, amount, status, requested_at)
    VALUES
        (v_payout_id, p_driver_id, p_destination_id, p_amount::numeric(12,2), 'PENDING', now());

    -- 10. Advance the head in the same transaction.
    UPDATE public.ledger_head
       SET seq = v_seq, last_hash = v_entry_hash, updated_at = now()
     WHERE id = 1;

    RETURN v_payout_id;
END;
$$;

ALTER FUNCTION wallet.request_payout(UUID, UUID, NUMERIC) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.request_payout(UUID, UUID, NUMERIC) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.request_payout(UUID, UUID, NUMERIC) TO keke_app;

-- ============================================================================
-- 3. process_payout — admin initiate disbursement (PENDING -> PROCESSING).
--    No money movement; enqueues the durable payout.submit outbox event.
-- ============================================================================
CREATE FUNCTION wallet.process_payout(
    p_payout_id UUID
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout RECORD;
BEGIN
    SELECT p.* INTO v_payout
      FROM public.payouts p WHERE p.id = p_payout_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payout not found';
    END IF;
    IF v_payout.status <> 'PENDING' THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_STATE';
    END IF;

    -- Transition PENDING -> PROCESSING and enqueue the durable submit event in the
    -- same transaction. The provider disburse call happens later in a worker.
    UPDATE public.payouts
       SET status = 'PROCESSING', processed_at = now(), version = version + 1
     WHERE id = p_payout_id;

    INSERT INTO public.outbox_events
        (event_id, aggregate_type, aggregate_id, event_type, payload, status, available_at)
    VALUES
        (p_payout_id, 'payout', p_payout_id, 'payout.submit',
         jsonb_build_object('payout_id', p_payout_id,
                            'driver_id', v_payout.driver_id,
                            'destination_id', v_payout.destination_id,
                            'amount', v_payout.amount,
                            'provider_idempotency_key', p_payout_id::text),
         'PENDING', now());

    RETURN p_payout_id;
END;
$$;

ALTER FUNCTION wallet.process_payout(UUID) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.process_payout(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.process_payout(UUID) TO keke_app;

-- ============================================================================
-- 4. record_provider_ref — persist the provider reference after disburse.
--    Initial assignment only; identical retry is a no-op; differing ref is
--    rejected (PROVIDER_REF_CONFLICT).
-- ============================================================================
CREATE FUNCTION wallet.record_provider_ref(
    p_payout_id    UUID,
    p_provider_ref TEXT
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout RECORD;
BEGIN
    IF p_provider_ref IS NULL OR btrim(p_provider_ref) = '' THEN
        RAISE EXCEPTION 'INVALID_PROVIDER_REF';
    END IF;

    SELECT p.* INTO v_payout
      FROM public.payouts p WHERE p.id = p_payout_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payout not found';
    END IF;
    IF v_payout.status <> 'PROCESSING' THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_STATE';
    END IF;

    -- Initial assignment; an identical retry is a no-op; a different existing
    -- reference is rejected (never overwritten).
    IF v_payout.provider_ref IS DISTINCT FROM p_provider_ref THEN
        IF v_payout.provider_ref IS NOT NULL THEN
            RAISE EXCEPTION 'PROVIDER_REF_CONFLICT';
        END IF;
        UPDATE public.payouts
           SET provider_ref = p_provider_ref, version = version + 1
         WHERE id = p_payout_id;
    END IF;

    RETURN p_payout_id;
END;
$$;

ALTER FUNCTION wallet.record_provider_ref(UUID, TEXT) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.record_provider_ref(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.record_provider_ref(UUID, TEXT) TO keke_app;

-- ============================================================================
-- 5. reject_payout — admin rejection BEFORE submission (PENDING -> REJECTED).
--    Reversal: credits DRIVER_WALLET, debits MOMO_CLEARING.
-- ============================================================================
CREATE FUNCTION wallet.reject_payout(
    p_payout_id UUID,
    p_reason    TEXT
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout           RECORD;
    v_seq              BIGINT;
    v_last_hash        TEXT;
    v_entry_id         UUID := gen_random_uuid();
    v_wallet_id        UUID;
    v_clearing_id      UUID;
    v_currency         TEXT;
    v_wallet_balance   NUMERIC(16,2);
    v_clearing_balance NUMERIC(16,2);
    v_canonical        TEXT;
    v_entry_hash       TEXT;
BEGIN
    SELECT p.* INTO v_payout
      FROM public.payouts p WHERE p.id = p_payout_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payout not found';
    END IF;
    IF v_payout.status <> 'PENDING' THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_STATE';
    END IF;

    SELECT seq, last_hash INTO v_seq, v_last_hash
      FROM public.ledger_head WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ledger_head is not initialized';
    END IF;
    v_seq := v_seq + 1;

    SELECT a.id, a.currency INTO v_wallet_id, v_currency
      FROM public.ledger_accounts a
     WHERE a.account_type = 'DRIVER_WALLET' AND a.owner_user_id = v_payout.driver_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'driver wallet not found';
    END IF;
    SELECT id INTO v_clearing_id
      FROM public.ledger_accounts
     WHERE account_type = 'MOMO_CLEARING' AND currency = v_currency
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MOMO_CLEARING account not found';
    END IF;

    SELECT balance INTO v_wallet_balance
      FROM public.ledger_accounts WHERE id = v_wallet_id;
    SELECT balance INTO v_clearing_balance
      FROM public.ledger_accounts WHERE id = v_clearing_id;

    v_canonical := wallet.canonical_line(v_wallet_id,   v_currency, v_payout.amount, false) || '|' ||
                   wallet.canonical_line(v_clearing_id, v_currency, v_payout.amount, true);
    v_entry_hash := wallet.journal_entry_hash(
        wallet.canonical_entry(v_seq, 'PAYOUT', v_payout.id::text || ':reversal',
                               v_last_hash, v_canonical));

    INSERT INTO public.journal_entries
        (id, seq, entry_type, correlation_id, description, prev_hash, entry_hash)
    VALUES
        (v_entry_id, v_seq, 'PAYOUT', v_payout.id::text || ':reversal',
         'payout reversal', v_last_hash, v_entry_hash);

    INSERT INTO public.journal_lines
        (journal_entry_id, account_id, currency, amount, is_debit, balance_after)
    VALUES
        (v_entry_id, v_wallet_id,   v_currency, v_payout.amount, false, v_wallet_balance   + v_payout.amount),
        (v_entry_id, v_clearing_id, v_currency, v_payout.amount, true,  v_clearing_balance - v_payout.amount);

    UPDATE public.ledger_accounts SET balance = balance + v_payout.amount, version = version + 1
     WHERE id = v_wallet_id;
    UPDATE public.ledger_accounts SET balance = balance - v_payout.amount, version = version + 1
     WHERE id = v_clearing_id;

    UPDATE public.payouts
       SET status = 'REJECTED', rejection_reason = p_reason,
           processed_at = now(), version = version + 1
     WHERE id = p_payout_id;

    UPDATE public.ledger_head
       SET seq = v_seq, last_hash = v_entry_hash, updated_at = now()
     WHERE id = 1;

    RETURN v_entry_id;
END;
$$;

ALTER FUNCTION wallet.reject_payout(UUID, TEXT) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.reject_payout(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.reject_payout(UUID, TEXT) TO keke_app;

-- ============================================================================
-- 6. complete_payout — provider success (PROCESSING -> COMPLETED). No money
--    movement: the reservation becomes the final disbursement.
-- ============================================================================
CREATE FUNCTION wallet.complete_payout(
    p_payout_id    UUID,
    p_provider_ref TEXT
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout RECORD;
BEGIN
    IF p_provider_ref IS NULL OR btrim(p_provider_ref) = '' THEN
        RAISE EXCEPTION 'INVALID_PROVIDER_REF';
    END IF;

    SELECT p.* INTO v_payout
      FROM public.payouts p WHERE p.id = p_payout_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payout not found';
    END IF;
    IF v_payout.status <> 'PROCESSING' THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_STATE';
    END IF;

    -- First assignment or identical reference is allowed; a different existing
    -- reference is rejected (never overwritten).
    IF v_payout.provider_ref IS NOT NULL
       AND v_payout.provider_ref <> p_provider_ref THEN
        RAISE EXCEPTION 'PROVIDER_REF_CONFLICT';
    END IF;

    UPDATE public.payouts
       SET status = 'COMPLETED',
           provider_ref = p_provider_ref,
           processed_at = now(), version = version + 1
     WHERE id = p_payout_id;

    RETURN p_payout_id;
END;
$$;

ALTER FUNCTION wallet.complete_payout(UUID, TEXT) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.complete_payout(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.complete_payout(UUID, TEXT) TO keke_app;

-- ============================================================================
-- 7. fail_payout — provider failure (PROCESSING -> REJECTED, with reversal).
--    p_provider_event_id: verified FAILURE webhook event id (NULL for a
--    synchronous disburse rejection). Reversal correlation = payout_id::text
--    || ':reversal'.
-- ============================================================================
CREATE FUNCTION wallet.fail_payout(
    p_payout_id         UUID,
    p_provider_event_id TEXT,
    p_reason            TEXT
) RETURNS UUID
SECURITY DEFINER
SET search_path = pg_catalog, wallet
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout           RECORD;
    v_seq              BIGINT;
    v_last_hash        TEXT;
    v_entry_id         UUID := gen_random_uuid();
    v_wallet_id        UUID;
    v_clearing_id      UUID;
    v_currency         TEXT;
    v_wallet_balance   NUMERIC(16,2);
    v_clearing_balance NUMERIC(16,2);
    v_canonical        TEXT;
    v_entry_hash       TEXT;
BEGIN
    SELECT p.* INTO v_payout
      FROM public.payouts p WHERE p.id = p_payout_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payout not found';
    END IF;
    IF v_payout.status <> 'PROCESSING' THEN
        RAISE EXCEPTION 'INVALID_PAYOUT_STATE';
    END IF;

    SELECT seq, last_hash INTO v_seq, v_last_hash
      FROM public.ledger_head WHERE id = 1 FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ledger_head is not initialized';
    END IF;
    v_seq := v_seq + 1;

    SELECT a.id, a.currency INTO v_wallet_id, v_currency
      FROM public.ledger_accounts a
     WHERE a.account_type = 'DRIVER_WALLET' AND a.owner_user_id = v_payout.driver_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'driver wallet not found';
    END IF;
    SELECT id INTO v_clearing_id
      FROM public.ledger_accounts
     WHERE account_type = 'MOMO_CLEARING' AND currency = v_currency
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MOMO_CLEARING account not found';
    END IF;

    SELECT balance INTO v_wallet_balance
      FROM public.ledger_accounts WHERE id = v_wallet_id;
    SELECT balance INTO v_clearing_balance
      FROM public.ledger_accounts WHERE id = v_clearing_id;

    v_canonical := wallet.canonical_line(v_wallet_id,   v_currency, v_payout.amount, false) || '|' ||
                   wallet.canonical_line(v_clearing_id, v_currency, v_payout.amount, true);
    v_entry_hash := wallet.journal_entry_hash(
        wallet.canonical_entry(v_seq, 'PAYOUT', v_payout.id::text || ':reversal',
                               v_last_hash, v_canonical));

    INSERT INTO public.journal_entries
        (id, seq, entry_type, correlation_id, description, prev_hash, entry_hash)
    VALUES
        (v_entry_id, v_seq, 'PAYOUT', v_payout.id::text || ':reversal',
         'payout reversal', v_last_hash, v_entry_hash);

    INSERT INTO public.journal_lines
        (journal_entry_id, account_id, currency, amount, is_debit, balance_after)
    VALUES
        (v_entry_id, v_wallet_id,   v_currency, v_payout.amount, false, v_wallet_balance   + v_payout.amount),
        (v_entry_id, v_clearing_id, v_currency, v_payout.amount, true,  v_clearing_balance - v_payout.amount);

    UPDATE public.ledger_accounts SET balance = balance + v_payout.amount, version = version + 1
     WHERE id = v_wallet_id;
    UPDATE public.ledger_accounts SET balance = balance - v_payout.amount, version = version + 1
     WHERE id = v_clearing_id;

    UPDATE public.payouts
       SET status = 'REJECTED', rejection_reason = p_reason,
           rejection_provider_event_id = p_provider_event_id,
           processed_at = now(), version = version + 1
     WHERE id = p_payout_id;

    UPDATE public.ledger_head
       SET seq = v_seq, last_hash = v_entry_hash, updated_at = now()
     WHERE id = 1;

    RETURN v_entry_id;
END;
$$;

ALTER FUNCTION wallet.fail_payout(UUID, TEXT, TEXT) OWNER TO keke_wallet;
REVOKE ALL ON FUNCTION wallet.fail_payout(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION wallet.fail_payout(UUID, TEXT, TEXT) TO keke_app;
