-- ============================================================================
-- KEKE — Migration M-04B (trip track / ride_locations)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-04B)
--                  KEKE_DATABASE_DESIGN.md §6.1 (ride_locations)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+ with PostGIS.
-- Depends on: M-04 (rides), M-01 (drivers), M-00 (PostGIS). All must have run.
--
-- SCOPE (and ONLY this scope): ride_locations + its two indexes.
--   * NO dispatch_events (PENDING).
--   * PostGIS is already enabled by M-00; not repeated here.
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Application table in `public`, NOT transferred to keke_wallet.
--   * No GRANT/REVOKE issued here. No unrestricted privileges.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ride_locations — durable trip track (down-sampled ~5s), populated ONLY during
-- an active trip. This is the durable GPS record for trip distance / dispute;
-- it is distinct from the transient Redis GEO proximity index.
--   geom: WGS84 geography point (SRID 4326); PostGIS validates lon/lat.
--   id: BIGSERIAL (canonical; not UUID).
-- ----------------------------------------------------------------------------
CREATE TABLE public.ride_locations (
    id           BIGSERIAL PRIMARY KEY,
    ride_id      UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    driver_id    UUID NOT NULL REFERENCES public.drivers(user_id),
    geom         GEOGRAPHY(Point, 4326) NOT NULL,   -- WGS84 (PostGIS validates lon/lat)
    accuracy_m   DOUBLE PRECISION CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
    speed_mps    DOUBLE PRECISION CHECK (speed_mps IS NULL OR speed_mps >= 0),
    recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ride_locations_ride_time
    ON public.ride_locations (ride_id, recorded_at);
CREATE INDEX idx_ride_locations_geom
    ON public.ride_locations USING GIST (geom);
