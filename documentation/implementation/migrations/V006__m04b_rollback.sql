-- ============================================================================
-- KEKE — Rollback for Migration M-04B (V006__m04b_ride_locations.sql)
-- ----------------------------------------------------------------------------
-- Drops ONLY ride_locations (and its indexes) created by M-04B, WITHOUT CASCADE.
-- Preserves M-00 (roles/schema/PostGIS), M-01 .. M-04.
--
-- Dropping the table also drops its own indexes; ride_locations is the REFERENCING
-- table (its FKs point to rides/drivers), so no CASCADE is required and the parent
-- tables are untouched.
-- ============================================================================

DROP TABLE IF EXISTS public.ride_locations;
