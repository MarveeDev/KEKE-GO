-- ============================================================================
-- KEKE — Rollback for Migration M-08 (V010__m08_outbox_infrastructure.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-08, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles + wallet schema) and M-01 .. M-07.
--
-- ORDER:
--   1. Drop the five functions BEFORE the composite type (outbox_claim returns
--      SETOF wallet.outbox_claim_result).
--   2. Drop the composite type.
--   3. Drop the table.
--   4. Revoke the schema USAGE grant this migration issued to keke_outbox_worker.
-- ============================================================================

DROP FUNCTION IF EXISTS wallet.outbox_dead_letter(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS wallet.outbox_retry(UUID, UUID, TEXT, INT);
DROP FUNCTION IF EXISTS wallet.outbox_ack(UUID, UUID);
DROP FUNCTION IF EXISTS wallet.outbox_renew_lease(UUID, UUID, INT);
DROP FUNCTION IF EXISTS wallet.outbox_claim(INT, INT);

DROP TYPE IF EXISTS wallet.outbox_claim_result;

DROP TABLE IF EXISTS public.outbox_events;

REVOKE USAGE ON SCHEMA wallet FROM keke_outbox_worker;
