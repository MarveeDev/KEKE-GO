-- ============================================================================
-- KEKE — Rollback for Migration M-05 (V007__m05_payments_idempotency.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-05, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles/schema/PostGIS), M-01 .. M-04B.
--
-- ORDER: idempotency_keys has no FK; payment_events references payments;
-- payments references rides/users (M-04/M-01, NOT dropped). Drop children first.
-- ============================================================================

DROP TABLE IF EXISTS public.idempotency_keys;
DROP TABLE IF EXISTS public.payment_events;
DROP TABLE IF EXISTS public.payments;
