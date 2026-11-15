-- ============================================================================
-- KEKE — Migration M-03 (driver availability & pricing/geography)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-03)
--                  KEKE_DATABASE_DESIGN.md §6.2 (pricing_zones), §7 (driver_availability)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+ with PostGIS.
-- Depends on: M-00 (PostGIS extension) and M-01 (drivers). Both must have run.
--
-- SCOPE (and ONLY this scope):
--   * driver_availability (durable online/offline + last-fix snapshot).
--   * pricing_zones (service-area polygon) + its GIST index.
--   * NO fare_rules / surge_multipliers (PROPOSED/OPEN — see DB §6.5).
--   * NO rides/offers/payments/wallet/ledger/reconciliation.
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Application tables in `public`, NOT transferred to keke_wallet.
--   * No GRANT/REVOKE issued here. No unrestricted privileges.
--
-- PostGIS is enabled by M-00; this migration only uses GEOGRAPHY types.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- driver_availability — SINGLE durable source of truth for a driver's
-- online/offline state and last-fix snapshot.
--
--   * status is the durable ONLINE/OFFLINE flag; it survives Redis loss.
--   * last_location + accuracy/speed/heading are the LAST-fix snapshot (a single
--     current-state row, NOT a location history). No idle/offline position
--     history is retained.
--   * Redis `keke:drivers` is a TRANSIENT proximity index only and is rebuilt
--     from this row plus the latest heartbeat on failover; it is never a second
--     source of truth.
--   * location_recorded_at (device) vs server_received_at (server) support the
--     STALE_AFTER / MAX_ACCURACY freshness checks; the CHECK enforces snapshot
--     ordering (clock skew is reconciled at ingest by the Location service).
-- ============================================================================
CREATE TABLE public.driver_availability (
    driver_id            UUID PRIMARY KEY REFERENCES public.drivers(user_id),
    status               TEXT NOT NULL DEFAULT 'OFFLINE'
                         CHECK (status IN ('OFFLINE','ONLINE')),
    last_location        GEOGRAPHY(Point, 4326),  -- PostGIS validates lon/lat
    accuracy_m           DOUBLE PRECISION CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
    speed_mps            DOUBLE PRECISION CHECK (speed_mps IS NULL OR speed_mps >= 0),
    heading_deg          DOUBLE PRECISION CHECK (heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360)),
    location_recorded_at TIMESTAMPTZ,        -- device capture time of last fix
    server_received_at   TIMESTAMPTZ,        -- server ingest time of last fix
    last_seen_at         TIMESTAMPTZ,        -- last heartbeat received (any)
    version              INT NOT NULL DEFAULT 0,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- snapshot consistency: capture time precedes ingest time (clock skew reconciled at ingest)
    CHECK (location_recorded_at IS NULL OR server_received_at IS NULL
           OR location_recorded_at <= server_received_at)
);

-- ----------------------------------------------------------------------------
-- pricing_zones — service-area / fare-zone polygon (WGS84 multi-polygon).
--   geom is the authoritative zone geometry; the GIST index below serves the
--   ST_Contains zone-lookup query in the canonical design.
-- ----------------------------------------------------------------------------
CREATE TABLE public.pricing_zones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    geom        GEOGRAPHY(MultiPolygon, 4326) NOT NULL,
    active      BOOLEAN NOT NULL DEFAULT true,
    version     INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_pricing_zones_geom ON public.pricing_zones USING GIST (geom);
