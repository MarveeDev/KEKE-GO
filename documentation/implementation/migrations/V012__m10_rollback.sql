-- ============================================================================
-- KEKE — Rollback for Migration M-10 (V012__m10_wallet_writers.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the seven wallet writer functions created by M-10, in reverse
-- dependency order, WITHOUT CASCADE. No tables/indexes/types/triggers are dropped
-- (they belong to M-06/M-07/M-08). Preserves M-00 .. M-09 objects and privileges.
-- ============================================================================

DROP FUNCTION IF EXISTS wallet.fail_payout(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS wallet.complete_payout(UUID, TEXT);
DROP FUNCTION IF EXISTS wallet.reject_payout(UUID, TEXT);
DROP FUNCTION IF EXISTS wallet.record_provider_ref(UUID, TEXT);
DROP FUNCTION IF EXISTS wallet.process_payout(UUID);
DROP FUNCTION IF EXISTS wallet.request_payout(UUID, UUID, NUMERIC);
DROP FUNCTION IF EXISTS wallet.append_journal_entry(TEXT, TEXT, TEXT, JSONB);
