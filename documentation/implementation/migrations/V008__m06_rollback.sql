-- ============================================================================
-- KEKE — Rollback for Migration M-06 (V008__m06_payout_destinations_payouts.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-06, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles/schema/PostGIS), M-01 .. M-05.
--
-- ORDER: payout_events references payouts; payouts references
-- payout_destinations (composite) and drivers (M-01, NOT dropped).
-- ============================================================================

DROP TABLE IF EXISTS public.payout_events;
DROP TABLE IF EXISTS public.payouts;
DROP TABLE IF EXISTS public.payout_destinations;
