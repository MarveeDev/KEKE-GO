-- ============================================================================
-- KEKE — Migration M-04 (rides & dispatch records)
-- ----------------------------------------------------------------------------
-- Source of truth: KEKE_SQL_IMPLEMENTATION_MANIFEST.md §6 (M-04)
--                  KEKE_DATABASE_DESIGN.md §5.1 (rides), §5.2 (ride_offers),
--                  §5.3 (cancellations, ratings)
--
-- Framework: Flyway-style (V-prefixed). Target: PostgreSQL 16+.
-- Depends on: M-01 (users/passengers/drivers/admins), M-02 (driver_vehicles).
--
-- SCOPE (and ONLY this scope):
--   * rides, ride_offers, cancellations, ratings.
--   * NO ride_locations (deferred — PostGIS trip track), NO dispatch_events
--     (PENDING), NO payments/wallet/ledger/reconciliation.
--
-- SCHEMA / OWNERSHIP / PRIVILEGES:
--   * Application tables in `public`, NOT transferred to keke_wallet.
--   * No GRANT/REVOKE issued here. No unrestricted privileges.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- rides — the ride aggregate and lifecycle state machine.
--   Composite FK fk_rides_vehicle_owner enforces that vehicle_id belongs to
--   driver_id (via driver_vehicles (id, driver_id)). MATCH SIMPLE means it is not
--   enforced while either column is NULL (pre-acceptance); once accepted both are
--   set and ownership is enforced by the database.
--   Two CHECK constraints enforce atomic driver+vehicle assignment: a vehicle is
--   never set without a driver, and ACCEPTED/later statuses require both.
-- ----------------------------------------------------------------------------
CREATE TABLE public.rides (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    passenger_id       UUID NOT NULL REFERENCES public.passengers(user_id),
    driver_id          UUID REFERENCES public.drivers(user_id),   -- null until accepted
    vehicle_id         UUID REFERENCES public.driver_vehicles(id),
    status             TEXT NOT NULL DEFAULT 'REQUESTED'
                       CHECK (status IN ('REQUESTED','SEARCHING','ACCEPTED',
                        'DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_TRIP','COMPLETED','CANCELLED')),
    -- pickup / dropoff
    pickup_lat         DOUBLE PRECISION NOT NULL,
    pickup_lng         DOUBLE PRECISION NOT NULL,
    pickup_address     TEXT NOT NULL,
    dropoff_lat        DOUBLE PRECISION,
    dropoff_lng        DOUBLE PRECISION,
    dropoff_address    TEXT,
    -- fare (server-computed, snapshot at completion; see ledger for authoritative money)
    currency           TEXT NOT NULL DEFAULT 'GHS',
    fare_base          NUMERIC(12,2),
    fare_distance      NUMERIC(12,2),
    fare_time          NUMERIC(12,2),
    fare_total         NUMERIC(12,2),
    commission_pct     NUMERIC(5,2),       -- snapshot of rate at ride time
    payment_method     TEXT CHECK (payment_method IN ('CASH','MOBILE_MONEY')),
    -- lifecycle timestamps
    requested_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at        TIMESTAMPTZ,
    en_route_at        TIMESTAMPTZ,
    arrived_at         TIMESTAMPTZ,
    started_at         TIMESTAMPTZ,
    completed_at       TIMESTAMPTZ,
    cancelled_at       TIMESTAMPTZ,
    -- trip measurements
    distance_m         DOUBLE PRECISION,
    duration_s         INT,
    version            INT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_rides_vehicle_owner
        FOREIGN KEY (vehicle_id, driver_id)
        REFERENCES public.driver_vehicles (id, driver_id),
    -- no vehicle without a driver
    CHECK (vehicle_id IS NULL OR driver_id IS NOT NULL),
    -- accepted (and later) rides require both driver and vehicle
    CHECK (status NOT IN ('ACCEPTED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_TRIP','COMPLETED')
           OR (driver_id IS NOT NULL AND vehicle_id IS NOT NULL)),
    -- coordinate ranges
    CHECK (pickup_lat BETWEEN -90 AND 90),
    CHECK (pickup_lng BETWEEN -180 AND 180),
    CHECK (dropoff_lat IS NULL OR dropoff_lat BETWEEN -90 AND 90),
    CHECK (dropoff_lng IS NULL OR dropoff_lng BETWEEN -180 AND 180),
    -- dropoff lat/lng are a pair: both set or both null
    CHECK ((dropoff_lat IS NULL) = (dropoff_lng IS NULL))
);

CREATE INDEX idx_rides_passenger ON public.rides (passenger_id, created_at DESC);
CREATE INDEX idx_rides_driver    ON public.rides (driver_id, created_at DESC);
CREATE INDEX idx_rides_status    ON public.rides (status) WHERE status IN ('REQUESTED','SEARCHING','ACCEPTED');

-- at most one active ride per passenger / per driver
CREATE UNIQUE INDEX uq_rides_passenger_active
    ON public.rides (passenger_id)
    WHERE status IN ('REQUESTED','SEARCHING','ACCEPTED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_TRIP');
CREATE UNIQUE INDEX uq_rides_driver_active
    ON public.rides (driver_id)
    WHERE status IN ('ACCEPTED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_TRIP');

-- ----------------------------------------------------------------------------
-- ride_offers — dispatch offers (batched fanout). Independent of ride status.
--   Partial unique index uq_ride_offers_accepted enforces the single-winner
--   invariant: exactly one ACCEPTED offer per ride.
-- ----------------------------------------------------------------------------
CREATE TABLE public.ride_offers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id         UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    driver_id       UUID NOT NULL REFERENCES public.drivers(user_id),
    status          TEXT NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','ACCEPTED','REJECTED','EXPIRED','WITHDRAWN')),
    offer_rank      SMALLINT NOT NULL DEFAULT 0,   -- 0 = first batch, 1 = second, ...
    offered_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    responded_at    TIMESTAMPTZ,
    reject_reason   TEXT,
    version         INT NOT NULL DEFAULT 0
);

-- exactly one accepted offer per ride
CREATE UNIQUE INDEX uq_ride_offers_accepted
    ON public.ride_offers (ride_id) WHERE status = 'ACCEPTED';
CREATE INDEX idx_ride_offers_driver ON public.ride_offers (driver_id, offered_at DESC);
CREATE INDEX idx_ride_offers_pending ON public.ride_offers (expires_at) WHERE status = 'PENDING';

-- ----------------------------------------------------------------------------
-- cancellations — one per ride (UNIQUE ride_id), with initiator + reason.
-- ----------------------------------------------------------------------------
CREATE TABLE public.cancellations (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id        UUID NOT NULL REFERENCES public.rides(id),
    initiated_by   TEXT NOT NULL CHECK (initiated_by IN ('passenger','driver','system')),
    reason_code    TEXT NOT NULL,      -- e.g. 'NO_DRIVER_FOUND','DRIVER_TOO_FAR','WRONG_ADDRESS','DRIVER_CANCELLED'
    fee_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
    note           TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ride_id)                     -- one cancellation per ride
);

-- ----------------------------------------------------------------------------
-- ratings — one rating per (ride, rater, ratee) pair; score 1..5.
-- ----------------------------------------------------------------------------
CREATE TABLE public.ratings (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id        UUID NOT NULL REFERENCES public.rides(id),
    rater_user_id  UUID NOT NULL REFERENCES public.users(id),
    ratee_user_id  UUID NOT NULL REFERENCES public.users(id),
    score          SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment        TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ride_id, rater_user_id, ratee_user_id)
);
