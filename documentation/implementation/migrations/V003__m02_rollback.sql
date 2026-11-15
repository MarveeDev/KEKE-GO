-- ============================================================================
-- KEKE — Rollback for Migration M-02 (V003__m02_vehicles_verification.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-02, in dependency-safe order, WITHOUT
-- CASCADE. M-00 (roles/schema/extension) and M-01
-- (users/passengers/drivers/admins) are preserved.
--
-- ORDER: verification_documents references driver_vehicles, so it is dropped
-- first; driver_vehicles references drivers/admins (M-01), which are NOT dropped.
-- ============================================================================

DROP TABLE IF EXISTS public.verification_documents;
DROP TABLE IF EXISTS public.driver_vehicles;
