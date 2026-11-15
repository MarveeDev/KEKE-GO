-- ============================================================================
-- KEKE — Rollback for Migration M-09 (V011__m09_audit.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-09 (the two indexes + audit_logs), WITHOUT
-- CASCADE. Preserves M-00 (roles/schema/PostGIS) and M-01 .. M-08.
--
-- ORDER: drop the indexes first (explicit), then the table.
-- ============================================================================

DROP INDEX IF EXISTS public.idx_audit_entity;
DROP INDEX IF EXISTS public.idx_audit_actor;

DROP TABLE IF EXISTS public.audit_logs;
