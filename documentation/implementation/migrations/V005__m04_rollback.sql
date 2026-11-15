-- ============================================================================
-- KEKE — Rollback for Migration M-04 (V005__m04_rides_dispatch.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-04, in dependency-safe order, WITHOUT
-- CASCADE. Preserves M-00 (roles/schema/PostGIS), M-01 (users/profiles),
-- M-02 (vehicles/documents) and M-03 (availability/pricing-geo).
--
-- ORDER: ratings, cancellations and ride_offers all reference rides, so they are
-- dropped before rides. (ride_offers also cascades ON DELETE from rides, but we
-- drop it explicitly rather than relying on cascade.)
-- ============================================================================

DROP TABLE IF EXISTS public.ratings;
DROP TABLE IF EXISTS public.cancellations;
DROP TABLE IF EXISTS public.ride_offers;
DROP TABLE IF EXISTS public.rides;
