-- ============================================================================
-- KEKE — Rollback for Migration M-07 (V009__m07_ledger_foundation.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-07, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles + wallet schema + PostGIS) and M-01 .. M-06.
--
-- ORDER:
--   1. Drop the trigger BEFORE its function (the trigger depends on the function).
--   2. Drop the trigger function, then the hash helpers (dependent functions).
--   3. Drop tables in dependency order: journal_lines (references journal_entries
--      and ledger_accounts) → journal_entries → ledger_head → ledger_accounts.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_journal_entry_balanced ON public.journal_entries;

DROP FUNCTION IF EXISTS wallet.validate_journal_entry();
DROP FUNCTION IF EXISTS wallet.journal_entry_hash(TEXT);
DROP FUNCTION IF EXISTS wallet.canonical_entry(BIGINT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS wallet.canonical_line(UUID, TEXT, NUMERIC, BOOLEAN);

DROP TABLE IF EXISTS public.journal_lines;
DROP TABLE IF EXISTS public.journal_entries;
DROP TABLE IF EXISTS public.ledger_head;
DROP TABLE IF EXISTS public.ledger_accounts;
