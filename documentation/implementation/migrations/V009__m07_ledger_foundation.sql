-- ============================================================================
-- KEKE — Migration M-07 (ledger foundation)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-07)
--                  KEKE_DATABASE_DESIGN.md §9 (ledger, hash chain, privileges)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 (roles + wallet schema), M-01 (drivers). Must have run.
--
-- SCOPE (and ONLY this scope):
--   * ledger_accounts, ledger_head (+ seed), journal_entries, journal_lines.
--   * The three IMMUTABLE hash helpers (canonical_line, canonical_entry,
--     journal_entry_hash).
--   * The SECURITY DEFINER validate_journal_entry() trigger function.
--   * The deferred constraint trigger trg_journal_entry_balanced.
--   * uq_journal_payout_correlation (and the other ledger indexes).
--   * Ownership transfer to keke_wallet + REVOKE EXECUTE FROM PUBLIC.
--
--   NOT in this migration:
--   * The seven wallet writers (append_journal_entry, request_payout,
--     process_payout, record_provider_ref, reject_payout, complete_payout,
--     fail_payout) — assigned to M-10.
--   * keke_app grants (SELECT/EXECUTE/USAGE) — M-11 privilege pass.
--   * Outbox (M-08), reconciliation/audit roles (PROPOSED).
--
-- SECURITY MODEL (canonical §9):
--   * Money is double-entry and append-only; balance is a projection of the
--     journal, never independent truth. Signed-balance convention: is_debit=true
--     DECREASES the account balance.
--   * ledger_head is the singleton hash-chain anchor; appends serialize on its
--     row lock (the writer in M-10 does `FOR UPDATE`). seq is assigned from the
--     head, not a gap-prone sequence.
--   * Only validate_journal_entry() is SECURITY DEFINER (it fires at COMMIT under
--     the caller's privileges and must read public.journal_lines + call the
--     wallet.* helpers). The three helpers are ordinary IMMUTABLE functions.
--   * Ledger tables are owned by keke_wallet; keke_app gets NO direct write here
--     (its SELECT-only / writer-EXECUTE grants are applied in M-11).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ledger_accounts — driver wallets + company clearing accounts.
--   account_type: DRIVER_WALLET / COMPANY_COMMISSION / MOMO_CLEARING / CASH_CLEARING.
--   ownership: DRIVER_WALLET requires a driver owner; clearing accounts have none.
--   balance is NUMERIC(16,2) (the authoritative ledger precision).
--   UNIQUE (id, currency) is the FK target for journal_lines' currency match.
-- ----------------------------------------------------------------------------
CREATE TABLE public.ledger_accounts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_type TEXT NOT NULL CHECK (account_type IN
                 ('DRIVER_WALLET','COMPANY_COMMISSION','MOMO_CLEARING','CASH_CLEARING')),
    owner_user_id UUID REFERENCES public.drivers(user_id),  -- set iff account_type = 'DRIVER_WALLET'
    currency     TEXT NOT NULL DEFAULT 'GHS',
    balance      NUMERIC(16,2) NOT NULL DEFAULT 0,
    version      INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ownership: DRIVER_WALLET requires a driver owner; clearing accounts have none
    CHECK ((account_type = 'DRIVER_WALLET') = (owner_user_id IS NOT NULL)),
    UNIQUE (id, currency)                    -- FK target for journal_lines currency
);
CREATE UNIQUE INDEX uq_ledger_account_owner
    ON public.ledger_accounts (owner_user_id) WHERE account_type = 'DRIVER_WALLET';

-- ----------------------------------------------------------------------------
-- ledger_head — singleton hash-chain anchor (id = 1). seq is the last assigned
-- sequence; last_hash is the entry_hash of the latest entry.
-- ----------------------------------------------------------------------------
CREATE TABLE public.ledger_head (
    id         SMALLINT PRIMARY KEY CHECK (id = 1),  -- singleton row
    seq        BIGINT NOT NULL DEFAULT 0,            -- last assigned sequence
    last_hash  TEXT,                                  -- entry_hash of the latest entry
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Idempotent seed (no-op if the head already exists)
INSERT INTO public.ledger_head (id, seq, last_hash) VALUES (1, 0, NULL)
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- journal_entries — one header per financial event (hash-chained via ledger_head).
--   entry_type: RIDE_FARE / COMMISSION / PAYOUT / REFUND / ADJUSTMENT / BONUS.
--   correlation_id ties to ride_id / payment_id / payout_id.
-- ----------------------------------------------------------------------------
CREATE TABLE public.journal_entries (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seq           BIGINT NOT NULL,         -- assigned from ledger_head under lock
    entry_type    TEXT NOT NULL CHECK (entry_type IN
                  ('RIDE_FARE','COMMISSION','PAYOUT','REFUND','ADJUSTMENT','BONUS')),
    correlation_id TEXT NOT NULL,          -- ties to ride_id / payment_id / payout_id
    description   TEXT,
    prev_hash     TEXT,                    -- entry_hash of the immediately preceding entry
    entry_hash    TEXT NOT NULL,           -- sha256 of this entry's canonical bytes
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (seq)
);

-- ----------------------------------------------------------------------------
-- journal_lines — double-entry lines (one debit, one credit minimum).
--   amount is POSITIVE only; direction is the is_debit flag (signed-balance).
--   balance_after is the account's running balance after this line.
--   Composite FK (account_id, currency) → ledger_accounts (id, currency) enforces
--   that a line's currency matches its account.
-- ----------------------------------------------------------------------------
CREATE TABLE public.journal_lines (
    id               BIGSERIAL PRIMARY KEY,
    journal_entry_id UUID NOT NULL REFERENCES public.journal_entries(id),
    account_id       UUID NOT NULL,
    currency         TEXT NOT NULL DEFAULT 'GHS',
    amount           NUMERIC(16,2) NOT NULL CHECK (amount > 0),  -- positive only; direction by debit flag
    is_debit         BOOLEAN NOT NULL,
    balance_after    NUMERIC(16,2) NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- currency must match the referenced account's currency (DB-enforced)
    FOREIGN KEY (account_id, currency) REFERENCES public.ledger_accounts (id, currency)
);

CREATE INDEX idx_journal_lines_account
    ON public.journal_lines (account_id, created_at DESC);

-- Payout correlation invariant: exactly one original PAYOUT entry and at most one
-- reversal per payout (original correlation = payouts.id::text, reversal =
-- payouts.id::text || ':reversal').
CREATE UNIQUE INDEX uq_journal_payout_correlation
    ON public.journal_entries (correlation_id)
    WHERE entry_type = 'PAYOUT';

-- ----------------------------------------------------------------------------
-- Canonical hash serialization helpers (IMMUTABLE; internal to the write path).
-- The writer (M-10) and the trigger must use the SAME helpers so their SHA-256
-- input is byte-identical. These are ordinary functions, NOT SECURITY DEFINER.
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.canonical_line(
    p_account_id UUID, p_currency TEXT, p_amount NUMERIC, p_is_debit BOOLEAN
) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS
$$ SELECT p_account_id::text || ':' || upper(p_currency) || ':' ||
          p_amount::numeric(16,2)::text || ':' ||
          CASE WHEN p_is_debit THEN 'D' ELSE 'C' END $$;

CREATE FUNCTION wallet.canonical_entry(
    p_seq BIGINT, p_entry_type TEXT, p_correlation_id TEXT,
    p_prev_hash TEXT, p_lines TEXT
) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS
$$ SELECT p_seq::text || '|' || p_entry_type || '|' || p_correlation_id || '|' ||
          COALESCE(p_prev_hash, '') || '|' || p_lines $$;

CREATE FUNCTION wallet.journal_entry_hash(p_canonical TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS
$$ SELECT encode(sha256(convert_to(p_canonical, 'UTF8')), 'hex') $$;

-- ----------------------------------------------------------------------------
-- validate_journal_entry() — commit-time (deferred) double-entry validation.
--   SECURITY DEFINER is REQUIRED: the deferred trigger fires at COMMIT under the
--   original caller's (keke_app's) privileges, which has no EXECUTE on the helper
--   functions. Running as keke_wallet lets it read public.journal_lines and call
--   the wallet.* canonical helpers. Fixed search_path for safety.
-- ----------------------------------------------------------------------------
CREATE FUNCTION wallet.validate_journal_entry() RETURNS trigger
SECURITY DEFINER
SET search_path = pg_catalog, wallet
AS $$
DECLARE
    line_count      INT;
    currency_count  INT;
    debit_total     NUMERIC(16,2);
    credit_total    NUMERIC(16,2);
    canonical_lines TEXT;
    expected_hash   TEXT;
BEGIN
    SELECT COUNT(*),
           COUNT(DISTINCT currency),
           COALESCE(SUM(amount) FILTER (WHERE is_debit), 0),
           COALESCE(SUM(amount) FILTER (WHERE NOT is_debit), 0),
           COALESCE(string_agg(
               wallet.canonical_line(account_id, currency, amount, is_debit),
               '|' ORDER BY id), '')
      INTO line_count, currency_count, debit_total, credit_total, canonical_lines
      FROM public.journal_lines
     WHERE journal_entry_id = NEW.id;

    IF line_count < 2 THEN
        RAISE EXCEPTION 'journal entry % must have at least two lines', NEW.id;
    END IF;
    IF currency_count <> 1 THEN
        RAISE EXCEPTION 'journal entry % must have a single currency', NEW.id;
    END IF;
    IF debit_total <> credit_total THEN
        RAISE EXCEPTION 'journal entry % is unbalanced (debit % vs credit %)',
            NEW.id, debit_total, credit_total;
    END IF;

    -- recompute the entry hash from the canonical content and compare
    expected_hash := wallet.journal_entry_hash(
        wallet.canonical_entry(NEW.seq, NEW.entry_type, NEW.correlation_id,
                               NEW.prev_hash, canonical_lines));
    IF expected_hash IS DISTINCT FROM NEW.entry_hash THEN
        RAISE EXCEPTION 'journal entry % entry_hash mismatch', NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_journal_entry_balanced
    AFTER INSERT ON public.journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION wallet.validate_journal_entry();

-- ----------------------------------------------------------------------------
-- Ownership & privilege restrictions (ledger objects only; canonical §9).
--   keke_wallet owns the ledger tables and the wallet functions.
--   Helpers + trigger are internal to the write path: no PUBLIC execution.
--   keke_app grants (SELECT-only on ledger, EXECUTE on writers) are M-11.
-- ----------------------------------------------------------------------------
ALTER TABLE public.ledger_accounts OWNER TO keke_wallet;
ALTER TABLE public.ledger_head     OWNER TO keke_wallet;
ALTER TABLE public.journal_entries OWNER TO keke_wallet;
ALTER TABLE public.journal_lines   OWNER TO keke_wallet;

ALTER FUNCTION wallet.canonical_line(UUID, TEXT, NUMERIC, BOOLEAN) OWNER TO keke_wallet;
ALTER FUNCTION wallet.canonical_entry(BIGINT, TEXT, TEXT, TEXT, TEXT) OWNER TO keke_wallet;
ALTER FUNCTION wallet.journal_entry_hash(TEXT) OWNER TO keke_wallet;
ALTER FUNCTION wallet.validate_journal_entry() OWNER TO keke_wallet;

REVOKE EXECUTE ON FUNCTION wallet.canonical_line(UUID, TEXT, NUMERIC, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION wallet.canonical_entry(BIGINT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION wallet.journal_entry_hash(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION wallet.validate_journal_entry() FROM PUBLIC;
