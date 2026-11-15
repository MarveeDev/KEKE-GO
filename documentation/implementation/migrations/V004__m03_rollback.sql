-- ============================================================================
-- KEKE — Rollback for Migration M-03 (V004__m03_availability_pricing_geo.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-03, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles/schema/PostGIS), M-01
-- (users/passengers/drivers/admins) and M-02 (vehicles/documents).
--
-- ORDER: pricing_zones has no FK dependencies; driver_availability references
-- drivers (M-01, NOT dropped). Drop order mirrors creation order in reverse.
-- ============================================================================

DROP TABLE IF EXISTS public.pricing_zones;
DROP TABLE IF EXISTS public.driver_availability;
