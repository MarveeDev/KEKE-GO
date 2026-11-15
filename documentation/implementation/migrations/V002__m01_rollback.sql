-- ============================================================================
-- KEKE — Rollback for Migration M-01 (V002__m01_users_profiles.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY the objects created by M-01, in dependency-safe order, WITHOUT
-- CASCADE. M-00 objects (roles, wallet schema, PostGIS) are preserved.
--
-- ORDER: drop the child profile tables (which reference users via FK) before
-- dropping users, so no CASCADE is required and no dependent object is lost.
-- ============================================================================

DROP TABLE IF EXISTS public.admins;
DROP TABLE IF EXISTS public.drivers;
DROP TABLE IF EXISTS public.passengers;
DROP TABLE IF EXISTS public.users;
