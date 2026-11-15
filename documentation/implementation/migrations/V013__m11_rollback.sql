-- ============================================================================
-- KEKE — Rollback for Migration M-11 (V013__m11_final_privileges.sql)
-- ----------------------------------------------------------------------------
-- Reverses ONLY the changes introduced by M-11, WITHOUT CASCADE, preserving all
-- M-00 .. M-10 objects and privileges (including the M-08 keke_outbox_worker
-- grants and the M-10 writer EXECUTE grants).
--
-- PART 1 — Revoke the keke_app grants introduced by M-11 (deterministic, safe).
--
-- PART 2 — Ownership reversal (ENVIRONMENT-SPECIFIC).
--   M-11 transferred five tables to keke_wallet. The ORIGINAL owner is the
--   migration/bootstrap role that created them (environment-specific), and it is
--   NOT recoverable from the catalog after M-11 runs. A safe reversal therefore
--   requires the operator to supply that role name.
--
--   RECOMMENDED PROCEDURE:
--     1. Before running M-11, record the bootstrap/migration role (e.g. the role
--        that executed V001..V012).
--     2. To roll back, uncomment the five ALTER TABLE statements below and replace
--        `:bootstrap_role` with the recorded role name (or run them with the role
--        name supplied via a migration parameter/psql variable).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PART 1: revoke the exact M-11 keke_app grants (inverse of the forward GRANTs).
-- ----------------------------------------------------------------------------
REVOKE USAGE ON SCHEMA wallet FROM keke_app;

REVOKE SELECT ON public.ledger_accounts, public.ledger_head,
                 public.journal_entries, public.journal_lines FROM keke_app;

REVOKE SELECT ON public.payouts, public.payout_destinations FROM keke_app;

REVOKE SELECT, INSERT ON public.payout_events FROM keke_app;

REVOKE SELECT, INSERT, UPDATE ON public.idempotency_keys FROM keke_app;

REVOKE USAGE ON SEQUENCE public.payout_events_id_seq   FROM keke_app;
REVOKE USAGE ON SEQUENCE public.idempotency_keys_id_seq FROM keke_app;

-- ----------------------------------------------------------------------------
-- PART 2: ownership reversal (environment-specific original owner).
--   Replace `:bootstrap_role` with the recorded migration/bootstrap role name.
-- ----------------------------------------------------------------------------
-- ALTER TABLE public.payouts             OWNER TO :bootstrap_role;
-- ALTER TABLE public.payout_destinations OWNER TO :bootstrap_role;
-- ALTER TABLE public.payout_events       OWNER TO :bootstrap_role;
-- ALTER TABLE public.idempotency_keys    OWNER TO :bootstrap_role;
-- ALTER TABLE public.outbox_events       OWNER TO :bootstrap_role;
