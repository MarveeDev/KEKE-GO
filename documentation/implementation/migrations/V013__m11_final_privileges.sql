-- ============================================================================
-- KEKE — Migration M-11 (final privileges)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-11), §5.1 (roles)
--                  KEKE_DATABASE_DESIGN.md §9 (ownership + keke_app grants)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-00 .. M-10 (all objects must exist).
--
-- SCOPE (and ONLY this scope):
--   1. Transfer ownership of the five remaining financial/outbox/idempotency
--      tables to keke_wallet (ledger tables + functions were already transferred
--      in M-07/M-08/M-10).
--   2. Grant keke_app the canonical privileges (schema USAGE, table SELECT /
--      SELECT+INSERT / SELECT+INSERT+UPDATE, sequence USAGE).
--   3. Verify final ownership of all wallet-owned objects.
--
--   NOT in this migration:
--   * No audit roles/functions (keke_audit / keke_audit_writer / audit.append_log)
--     — PROPOSED/OPEN, DB §11.1. audit_logs is NOT touched.
--   * No reconciliation roles. No payments/payment_events changes.
--   * No application-table privilege changes. No new objects.
--   * keke_outbox_worker permissions are UNCHANGED (already granted in M-08).
--
-- SECURITY:
--   * keke_app gets SELECT-only on ledger tables (NO INSERT/UPDATE/DELETE) — all
--     financial writes go through the M-10 SECURITY DEFINER writers.
--   * keke_app gets NO direct access to outbox_events.
--   * No PUBLIC grants are introduced.
--   * The HIGH-severity append_journal_entry authorization gap is PRESERVED
--     (unchanged); its allowlist remains an OPEN production blocker.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Ownership transfers (the five remaining keke_wallet-owned tables).
--    These make the M-08/M-10 SECURITY DEFINER functions operational against the
--    payout/outbox/idempotency tables (they run as keke_wallet).
-- ----------------------------------------------------------------------------
ALTER TABLE public.payouts             OWNER TO keke_wallet;
ALTER TABLE public.payout_destinations OWNER TO keke_wallet;
ALTER TABLE public.payout_events       OWNER TO keke_wallet;
ALTER TABLE public.idempotency_keys    OWNER TO keke_wallet;
ALTER TABLE public.outbox_events       OWNER TO keke_wallet;

-- ----------------------------------------------------------------------------
-- 2. Ownership verification (final pass). Fails loudly if any financial/outbox/
--    idempotency table is not owned by keke_wallet — including the four ledger
--    tables transferred in M-07.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'ledger_accounts','ledger_head','journal_entries','journal_lines',
        'payouts','payout_destinations','payout_events','idempotency_keys','outbox_events'
    ] LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_class c
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relname = t
               AND c.relowner::regrole::text IS DISTINCT FROM 'keke_wallet'
        ) THEN
            RAISE EXCEPTION 'public.% is not owned by keke_wallet', t;
        END IF;
    END LOOP;
END
$$;

-- ----------------------------------------------------------------------------
-- 3. Ownership verification (wallet schema, functions, type). Confirms the
--    M-07/M-08/M-10 objects remain keke_wallet-owned.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT n.nspowner::regrole::text
          FROM pg_namespace n
         WHERE n.nspname = 'wallet') IS DISTINCT FROM 'keke_wallet' THEN
        RAISE EXCEPTION 'wallet schema is not owned by keke_wallet';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'wallet'
           AND p.proowner::regrole::text IS DISTINCT FROM 'keke_wallet'
    ) THEN
        RAISE EXCEPTION 'some wallet function is not owned by keke_wallet';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
         WHERE n.nspname = 'wallet' AND t.typname = 'outbox_claim_result'
           AND t.typowner::regrole::text IS DISTINCT FROM 'keke_wallet'
    ) THEN
        RAISE EXCEPTION 'wallet.outbox_claim_result is not owned by keke_wallet';
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 4. keke_app privileges (canonical §9). SELECT-only on ledger/payout tables;
--    no direct financial writes; no outbox_events access; no helper/trigger
--    EXECUTE. (The seven M-10 writer EXECUTE grants are preserved, not re-issued.)
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA wallet TO keke_app;

GRANT SELECT ON public.ledger_accounts, public.ledger_head,
                 public.journal_entries, public.journal_lines TO keke_app;

GRANT SELECT ON public.payouts, public.payout_destinations TO keke_app;

GRANT SELECT, INSERT ON public.payout_events TO keke_app;

GRANT SELECT, INSERT, UPDATE ON public.idempotency_keys TO keke_app;

GRANT USAGE ON SEQUENCE public.payout_events_id_seq   TO keke_app;
GRANT USAGE ON SEQUENCE public.idempotency_keys_id_seq TO keke_app;
