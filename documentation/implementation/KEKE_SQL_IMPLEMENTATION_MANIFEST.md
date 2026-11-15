# KEKE — SQL Implementation Manifest

**Status:** Implementation planning artifact (not a migration, not code).
**Source of truth:** `C:\REA-BOLT\documentation\blueprint\` (primarily
`KEKE_DATABASE_DESIGN.md`, cross-checked against `KEKE_SYSTEM_ARCHITECTURE.md`,
`KEKE_API_SPECIFICATION.md`, `KEKE_PAYMENT_AND_WALLET.md`,
`KEKE_DISPATCH_ENGINE.md`, `KEKE_IMPLEMENTATION_ROADMAP.md`,
`KEKE_BLUEPRINT_INDEX.md`).

**Discipline:** every object below is classified **READY** (approved DDL exists in
the blueprint), **PENDING** (referenced but DDL not yet in
`KEKE_DATABASE_DESIGN.md`), or **PROPOSED/BLOCKED** (design exists but the decision
is OPEN). Nothing is invented here; nothing PROPOSED is treated as approved.

---

## 1. Approved database tables and their dependencies

### 1.1 READY — tables with DDL in `KEKE_DATABASE_DESIGN.md`

| # | Table | Owner domain | Schema | Key dependencies (FK →) | Notes |
|---|---|---|---|---|---|
| T1 | `users` | User & Profile | `public` | — | `phone` UNIQUE, `email` UNIQUE |
| T2 | `passengers` | User & Profile | `public` | `users(id)` | PK = `user_id` |
| T3 | `drivers` | User & Profile | `public` | `users(id)` | PK = `user_id` |
| T4 | `admins` | User & Profile | `public` | `users(id)` | PK = `user_id` |
| T5 | `driver_vehicles` | Vehicle & Verification | `public` | `drivers(user_id)`, `admins(user_id)` | `UNIQUE(id, driver_id)` FK target |
| T6 | `verification_documents` | Vehicle & Verification | `public` | `drivers(user_id)`, `driver_vehicles(id)`, `admins(user_id)` | `vehicle_id` nullable |
| T7 | `driver_availability` | Location | `public` | `drivers(user_id)` | PostGIS `GEOGRAPHY(Point,4326)` |
| T8 | `pricing_zones` | Pricing | `public` | — | PostGIS `GEOGRAPHY(MultiPolygon,4326)` |
| T9 | `rides` | Ride | `public` | `passengers(user_id)`, `drivers(user_id)`, `driver_vehicles(id, driver_id)` | composite ownership FK |
| T10 | `ride_offers` | Dispatch | `public` | `rides(id)`, `drivers(user_id)` | `ON DELETE CASCADE` (ride) |
| T11 | `cancellations` | Ride | `public` | `rides(id)` | `UNIQUE(ride_id)` |
| T12 | `ratings` | Ride | `public` | `rides(id)`, `users(id)` ×2 | `UNIQUE(ride_id, rater_user_id, ratee_user_id)` |
| T13 | `ride_locations` | Ride | `public` | `rides(id)`, `drivers(user_id)` | PostGIS, `BIGSERIAL` |
| T14 | `payments` | Payment | `public` | `rides(id)`, `users(id)` | `idempotency_key` UNIQUE |
| T15 | `payment_events` | Payment | `public` | `payments(id)` | immutable log, `BIGSERIAL` |
| T16 | `payout_destinations` | Wallet & Ledger | `public` (wallet-owned) | `drivers(user_id)` | `UNIQUE(id, driver_id)` |
| T17 | `payouts` | Wallet & Ledger | `public` (wallet-owned) | `drivers(user_id)`, `payout_destinations(id, driver_id)` | composite ownership FK |
| T18 | `payout_events` | Wallet & Ledger | `public` (wallet-owned) | `payouts(id)` | immutable log, `BIGSERIAL` |
| T19 | `idempotency_keys` | API/service | `public` (wallet-owned) | — | `principal_id` is a bare UUID (not FK'd) |
| T20 | `ledger_accounts` | Wallet & Ledger | `public` (wallet-owned) | `drivers(user_id)` | `UNIQUE(id, currency)` |
| T21 | `ledger_head` | Wallet & Ledger | `public` (wallet-owned) | — | singleton `CHECK(id = 1)` |
| T22 | `journal_entries` | Wallet & Ledger | `public` (wallet-owned) | — | `UNIQUE(seq)` |
| T23 | `journal_lines` | Wallet & Ledger | `public` (wallet-owned) | `journal_entries(id)`, `ledger_accounts(id, currency)` | composite currency FK |
| T24 | `outbox_events` | cross-cutting | `public` (wallet-owned) | — | `event_id` UNIQUE, `BIGSERIAL` |
| T25 | `audit_logs` | Audit | `public` | — (owner module convention) | append-only, `BIGSERIAL` |

### 1.2 PENDING — referenced, DDL not yet in `KEKE_DATABASE_DESIGN.md`

| # | Entity | Referenced by | Status |
|---|---|---|---|
| P1 | `auth_sessions` | Architecture §5; API §2.4, §12 | DDL pending |
| P2 | `otp_codes` | Architecture §5; API §2, §12 | DDL pending |
| P3 | `notification_tokens` | Architecture §5; API §7, §12 | DDL pending |
| P4 | `notifications` | Architecture §5; API §7, §12 | DDL pending |
| P5 | `support_tickets` / `support_messages` | Architecture §5; API §3.8, §12 | DDL pending |
| P6 | `dispatch_events` | Architecture §5; Dispatch §9 (DDL present there) | DDL lives outside DB design |
| P7 | `reconciliation_runs` | Payment §8 (DDL present there) | canonical location open |
| P8 | `ride_categories` | API §3.3, §12 | explicitly not needed for MVP |

> `dispatch_events` and `reconciliation_runs` have DDL in their domain documents
> but are **not** consolidated into `KEKE_DATABASE_DESIGN.md`. They are PENDING
> canonical-consolidation, not blocked.

### 1.3 PROPOSED/BLOCKED — design only, decision OPEN

- `fare_rules`, `surge_multipliers` (DB §6.5) — PROPOSED, no DDL.
- `admin_actions` (DB §6.6) — PROPOSED, no DDL.
- `payout_callback_integrity_conflicts`, `payout_orphan_callbacks` (DB §16.2) — PROPOSED.
- Reconciliation **findings** table + resolution history (DB §16.3) — PROPOSED.
- Extended `reconciliation_runs.domain` (DB §16.3) — PROPOSED.

**Column-level PROPOSED additions (not approved):**
- `payout_events.disposition` (DB §16.1).
- `outbox_events.dedup_key` (DB §16.4).
- `payouts.processing_started_at` (DB §16.5).

---

## 2. Canonical enums and creation order

All enums are implemented as `TEXT` columns with `CHECK` constraints (DB §2), **not**
PostgreSQL `CREATE TYPE ... ENUM`. There is therefore no separate enum migration
object; each value-set is enforced inline in its table DDL. The canonical value
sets (source: DB §2) are listed here for reference and order-of-reference:

| Enum | Values | First referencing table |
|---|---|---|
| `user_role` | `passenger`, `driver`, `admin` | `users` |
| `user_status` | `ACTIVE`, `SUSPENDED`, `DEACTIVATED` | `users` |
| `driver_status` | `ONBOARDING`, `ACTIVE`, `SUSPENDED`, `DEACTIVATED` | `drivers` |
| `document_status` (verification) | `PENDING`, `IN_REVIEW`, `APPROVED`, `REJECTED` | `drivers`, `verification_documents` |
| `vehicle_status` | `PENDING`, `APPROVED`, `REJECTED`, `SUSPENDED` | `driver_vehicles` |
| `driver_availability` | `OFFLINE`, `ONLINE` | `driver_availability` |
| `ride_status` | `REQUESTED`, `SEARCHING`, `ACCEPTED`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `IN_TRIP`, `COMPLETED`, `CANCELLED` | `rides` |
| `offer_status` | `PENDING`, `ACCEPTED`, `REJECTED`, `EXPIRED`, `WITHDRAWN` | `ride_offers` |
| `cancellation_initiator` | `passenger`, `driver`, `system` | `cancellations` |
| `payment_method` | `CASH`, `MOBILE_MONEY` | `payments` |
| `payment_status` | `PENDING`, `AUTHORIZED`, `CAPTURED`, `FAILED`, `REFUNDED`, `EXPIRED` | `payments` |
| `payout_status` | `PENDING`, `PROCESSING`, `COMPLETED`, `REJECTED` | `payouts` |
| `document_type` | `DRIVER_LICENSE`, `NATIONAL_ID`, `VEHICLE_REGISTRATION`, `INSURANCE`, `ROADWORTHINESS`, `PROFILE_PHOTO`, `OTHER` | `verification_documents` |
| `ledger_entry_type` | `RIDE_FARE`, `COMMISSION`, `PAYOUT`, `REFUND`, `ADJUSTMENT`, `BONUS` | `journal_entries` |
| `ledger account_type` | `DRIVER_WALLET`, `COMPANY_COMMISSION`, `MOMO_CLEARING`, `CASH_CLEARING` | `ledger_accounts` |
| `ticket_status` | `OPEN`, `PENDING_DRIVER`, `PENDING_PASSENGER`, `RESOLVED`, `CLOSED` | `support_tickets` (PENDING) |
| `notification_type` | `OFFER`, `RIDE_STATUS`, `PAYMENT`, `VERIFICATION`, `SUPPORT`, `MARKETING` | `notifications` (PENDING) |
| `outbox_status` | `PENDING`, `PROCESSING`, `PROCESSED`, `DEAD_LETTER` | `outbox_events` |

**Creation order note:** because these are inline CHECKs, the "creation order" is
implicit in the table order of §1.1; no standalone enum objects precede the tables.
PostgreSQL `CREATE EXTENSION postgis` must precede any `GEOGRAPHY` column.

---

## 3. Primary keys, foreign keys, unique constraints and indexes

### 3.1 Primary keys

| Table | PK |
|---|---|
| `users`, `rides`, `ride_offers`, `driver_vehicles`, `verification_documents`, `cancellations`, `ratings`, `pricing_zones`, `payments`, `payout_destinations`, `payouts`, `idempotency_keys` (bigserial), `ledger_accounts`, `journal_entries`, `outbox_events` (event_id is a separate UNIQUE; id is bigserial), `audit_logs` (bigserial) | `UUID` (mostly `gen_random_uuid()` default) |
| `passengers`, `drivers`, `admins`, `driver_availability` | `user_id`/`driver_id` (`UUID`, FK to `users`/`drivers`) |
| `ledger_head` | `id SMALLINT` with `CHECK (id = 1)` |
| `payment_events`, `payout_events`, `ride_locations`, `journal_lines` | `BIGSERIAL id` |

### 3.2 Foreign keys (ownership-relevant)

- `rides` → `driver_vehicles (id, driver_id)` **composite** FK `fk_rides_vehicle_owner` (enforces vehicle belongs to driver; `MATCH SIMPLE` so not enforced while NULL).
- `payouts` → `payout_destinations (id, driver_id)` **composite** FK `fk_payouts_destination_owner` (destination belongs to driver).
- `journal_lines` → `ledger_accounts (id, currency)` **composite** FK (currency match).
- Remaining FKs are single-column (see §1.1).

### 3.3 Unique constraints and partial unique indexes (correctness-critical)

| Object | Definition | Purpose |
|---|---|---|
| `users.phone` | UNIQUE | login identity |
| `users.email` | UNIQUE | nullable identity |
| `driver_vehicles.plate_number` | UNIQUE | vehicle identity |
| `driver_vehicles (id, driver_id)` | UNIQUE | FK target for ride→vehicle ownership |
| `rides uq_rides_passenger_active` | UNIQUE `(passenger_id)` WHERE status in active set | one active passenger ride |
| `rides uq_rides_driver_active` | UNIQUE `(driver_id)` WHERE status in post-acceptance active set | one active driver ride |
| `ride_offers uq_ride_offers_accepted` | UNIQUE `(ride_id)` WHERE status = `ACCEPTED` | single-winner dispatch |
| `cancellations (ride_id)` | UNIQUE | one cancellation per ride |
| `ratings (ride_id, rater_user_id, ratee_user_id)` | UNIQUE | one rating per pair |
| `payments.idempotency_key` | UNIQUE | payment dedup (see idempotency OPEN) |
| `payment_events uq_payment_events_provider` | UNIQUE `(provider, provider_event_id)` WHERE not null | webhook replay dedup |
| `payout_destinations (id, driver_id)` | UNIQUE | FK target for payout ownership |
| `payout_events uq_payout_events_provider` | UNIQUE `(provider, provider_event_id)` | callback dedup |
| `idempotency_keys (principal_id, operation, key_hash)` | UNIQUE | generic idempotency |
| `ledger_accounts (id, currency)` | UNIQUE | FK target for journal_lines currency |
| `ledger_accounts uq_ledger_account_owner` | UNIQUE `(owner_user_id)` WHERE type = `DRIVER_WALLET` | one wallet per driver |
| `journal_entries (seq)` | UNIQUE | hash-chain order |
| `journal_entries uq_journal_payout_correlation` | UNIQUE `(correlation_id)` WHERE type = `PAYOUT` | one original + one reversal per payout |
| `outbox_events.event_id` | UNIQUE | consumer idempotency key |

### 3.4 Other indexes (performance / sweeper)

Per DB §12: `rides(passenger_id, created_at DESC)`, `rides(driver_id, created_at
DESC)`, `rides(status)` partial for active statuses, `ride_offers(driver_id,
offered_at DESC)`, `ride_offers(expires_at)` partial `PENDING`,
`ride_locations(ride_id, recorded_at)` + `GIST(geom)`, `pricing_zones GIST(geom)`,
`payouts(driver_id, created_at DESC)`, `payouts(status)` partial
`PENDING`/`PROCESSING`, `payout_destinations(driver_id)`,
`idempotency_keys(expires_at)` partial `COMPLETED`, `idempotency_keys(lease_expires_at)`
partial `IN_PROGRESS`, `journal_lines(account_id, created_at DESC)`,
`outbox_events(status, available_at)` partial, `outbox_events(locked_until)` partial
`PROCESSING`, `outbox_events(aggregate_type, aggregate_id)`,
`audit_logs(entity_type, entity_id, created_at DESC)`, `audit_logs(actor_user_id,
created_at DESC)`.

---

## 4. Approved PostgreSQL functions and triggers

All wallet objects are `SECURITY DEFINER` with `SET search_path = pg_catalog, wallet`
and owned by `keke_wallet`. Signatures below are the approved, canonical ones (DB §9, §10.1).

### 4.1 Hash-canonicalization helpers (IMMUTABLE, no PUBLIC EXECUTE)

- `wallet.canonical_line(p_account_id UUID, p_currency TEXT, p_amount NUMERIC, p_is_debit BOOLEAN) RETURNS TEXT`
- `wallet.canonical_entry(p_seq BIGINT, p_entry_type TEXT, p_correlation_id TEXT, p_prev_hash TEXT, p_lines TEXT) RETURNS TEXT`
- `wallet.journal_entry_hash(p_canonical TEXT) RETURNS TEXT`

### 4.2 Ledger validation trigger function

- `wallet.validate_journal_entry() RETURNS trigger` (SECURITY DEFINER) — enforces ≥2 lines, single currency, debit=credit, and recomputed `entry_hash` equality.

### 4.3 Ledger / payout writers (`EXECUTE` granted to `keke_app` only)

- `wallet.append_journal_entry(p_entry_type TEXT, p_correlation_id TEXT, p_description TEXT, p_lines JSONB) RETURNS UUID`
- `wallet.request_payout(p_driver_id UUID, p_destination_id UUID, p_amount NUMERIC(16,2)) RETURNS UUID`
- `wallet.process_payout(p_payout_id UUID) RETURNS UUID`
- `wallet.record_provider_ref(p_payout_id UUID, p_provider_ref TEXT) RETURNS UUID`
- `wallet.reject_payout(p_payout_id UUID, p_reason TEXT) RETURNS UUID`
- `wallet.complete_payout(p_payout_id UUID, p_provider_ref TEXT) RETURNS UUID`
- `wallet.fail_payout(p_payout_id UUID, p_provider_event_id TEXT, p_reason TEXT) RETURNS UUID`

### 4.4 Outbox worker functions (`EXECUTE` granted to `keke_outbox_worker` only)

- Type: `wallet.outbox_claim_result` (`event_id UUID, event_type TEXT, payload JSONB, claim_token UUID, locked_until TIMESTAMPTZ, attempts INT`)
- `wallet.outbox_claim(p_batch INT, p_lease_seconds INT) RETURNS SETOF wallet.outbox_claim_result`
- `wallet.outbox_renew_lease(p_event_id UUID, p_claim_token UUID, p_lease_seconds INT) RETURNS VOID`
- `wallet.outbox_ack(p_event_id UUID, p_claim_token UUID) RETURNS VOID`
- `wallet.outbox_retry(p_event_id UUID, p_claim_token UUID, p_error TEXT, p_backoff_seconds INT) RETURNS VOID`
- `wallet.outbox_dead_letter(p_event_id UUID, p_claim_token UUID, p_error TEXT) RETURNS VOID`

### 4.5 Triggers

- `trg_journal_entry_balanced` — `CONSTRAINT TRIGGER ... AFTER INSERT ON journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION wallet.validate_journal_entry()`.

### 4.6 PROPOSED functions (NOT approved — do not create)

- `wallet.enqueue_outbox_event(...)` (DB §10.3) — outbox producer path, OPEN.
- `wallet.outbox_requeue(...)` (DB §16.4) — dead-letter recovery, OPEN.
- `audit.append_log(...)` (DB §11.1) — audit writer, OPEN.

---

## 5. Database roles, ownership and permission requirements

### 5.1 READY roles (DB §9 bootstrap)

| Role | LOGIN | Owns / privileges |
|---|---|---|
| `keke_wallet` | NO | Owns schema `wallet`; owns ledger/payout/outbox tables (`ledger_accounts`, `ledger_head`, `journal_entries`, `journal_lines`, `payouts`, `payout_destinations`, `payout_events`, `idempotency_keys`, `outbox_events`) and all `wallet.*` functions/types/trigger. |
| `keke_app` | YES | `USAGE` on `wallet`; `SELECT` on ledger/payout tables; `SELECT, INSERT` on `payout_events`; `SELECT, INSERT, UPDATE` on `idempotency_keys`; `EXECUTE` on the seven wallet writers (helpers NOT executable); `USAGE` on `payout_events_id_seq`, `idempotency_keys_id_seq`. No `INSERT/UPDATE/DELETE` on ledger/head/journal. |
| `keke_outbox_worker` | YES | `USAGE` on `wallet` + type `outbox_claim_result`; `EXECUTE` on `outbox_claim/renew_lease/ack/retry/dead_letter`. **No direct table access.** |

**Required revocations (design contract, DB §9):**
- `REVOKE CREATE ON SCHEMA public FROM PUBLIC;` and from `keke_app`.
- `REVOKE CREATE ON SCHEMA wallet FROM PUBLIC;` and from `keke_app`.
- `REVOKE EXECUTE ON` the three helpers + `validate_journal_entry` from `PUBLIC`.
- `REVOKE ALL ON wallet.append_journal_entry / request_payout / ... / fail_payout` from `PUBLIC` (then re-grant `EXECUTE` to `keke_app` only).
- `keke_app` must **not** be a member of `keke_wallet`.

**Ownership verification:** bootstrap must assert `wallet` schema `nspowner = keke_wallet` (DB §9 has an explicit `DO $$` check); do not rely on `CREATE SCHEMA ... AUTHORIZATION` alone.

### 5.2 PROPOSED roles (NOT approved — do not create)

- `keke_reconciliation` (LOGIN) — read-only payout/event/journal evidence; writes runs/findings only; no wallet EXECUTE (DB §16.6).
- `keke_audit` (LOGIN) — sole reader of raw evidence (`raw_body`, signature columns) (DB §16.6).
- `keke_audit_writer` (NOLOGIN) — proposed owner of `audit_logs` + `audit.append_log` (DB §11.1).

### 5.3 Open permission decisions (blocking, not assumed)

- Exact column-level grants for `keke_audit` (Index §6 item 11).
- Exact grants for `keke_reconciliation` (Index §6 item 23).
- Audit-log write path and `keke_audit_writer` grants (Index §6 item 27).
- Whether `payments`/`payment_events` ownership/grants (not listed in the §9 `ALTER ... OWNER` block) are finalized — **verification item**, do not invent grants.

---

## 6. Recommended migration sequence

Order is dependency-driven. A stage may only reference objects from earlier stages.

- **M-00 — Infrastructure & roles.** `CREATE EXTENSION postgis`. Create roles `keke_wallet` (NOLOGIN), `keke_app` (LOGIN), `keke_outbox_worker` (LOGIN). Create schema `wallet AUTHORIZATION keke_wallet`. Revoke `CREATE` on `public`/`wallet`. Assert wallet-schema ownership.
- **M-01 — Identity/profiles.** `users` → `passengers` → `drivers` → `admins`.
- **M-02 — Vehicles & verification.** `driver_vehicles` → `verification_documents`.
- **M-03 — Availability & pricing geo.** `driver_availability` → `pricing_zones` (both PostGIS).
- **M-04 — Rides & dispatch.** `rides` (composite vehicle-ownership FK + active-ride partial unique indexes) → `ride_offers` (single-accepted partial unique) → `cancellations` → `ratings`.
- **M-04B — Trip track (PostGIS).** `ride_locations` (GEOGRAPHY point, `ON DELETE CASCADE` from `rides`, GIST + time indexes). Depends on M-04 (`rides`) and M-01 (`drivers`).
- **M-05 — Payments & idempotency.** `payments` → `payment_events` → `idempotency_keys`.
- **M-06 — Payout destinations, payouts, events.** `payout_destinations` → `payouts` (composite destination-ownership FK) → `payout_events`.
- **M-07 — Ledger (wallet-owned, order-critical).** `ledger_accounts` → `ledger_head` (+ idempotent seed row) → `journal_entries` → `journal_lines` → helpers (`canonical_line`, `canonical_entry`, `journal_entry_hash`) → `validate_journal_entry()` → `trg_journal_entry_balanced`.
- **M-08 — Outbox.** `outbox_events` → type `outbox_claim_result` → `outbox_claim` → `outbox_renew_lease` → `outbox_ack` → `outbox_retry` → `outbox_dead_letter`.
- **M-09 — Audit.** `audit_logs`.
- **M-10 — Wallet SECURITY DEFINER writers.** `append_journal_entry` → `request_payout` → `process_payout` (depends on `outbox_events`) → `record_provider_ref` → `reject_payout` → `complete_payout` → `fail_payout`.
- **M-11 — Privileges (final pass).** All `ALTER ... OWNER TO keke_wallet`, `REVOKE ... FROM PUBLIC`, and `GRANT`/`GRANT USAGE ON SEQUENCE` statements, applied after object creation, in one idempotent privilege migration.

> The §9 bootstrap orders ownership transfer after object creation (single
> idempotent block). M-11 must run last so ownership/grants are never applied to
> objects that do not yet exist.

---

## 7. Features explicitly excluded (decisions remain OPEN)

These are **not** part of any approved migration and must not be created:

1. Payout callback `disposition` column and its classification tables
   (`payout_callback_integrity_conflicts`, `payout_orphan_callbacks`) — DB §16.1/§16.2.
2. Reconciliation findings + resolution-history tables and extended
   `reconciliation_runs.domain` — DB §16.3.
3. `outbox_events.dedup_key` and the `payout.reevaluate` event — DB §16.4.
4. `payouts.processing_started_at` — DB §16.5.
5. Reconciliation roles `keke_reconciliation`, `keke_audit` and audit-writer
   `keke_audit_writer` — DB §16.6, §11.1.
6. Application-managed savepoint webhook flow (§16.7) and PREMATURE re-evaluation
   (§16.8) — behavioral, not schema, but gated on disposition schema.
7. FAILURE-callback review-gating policy (`REVIEW_REQUIRED` dual-control) — DB §16.9.
8. `PX001` SQLSTATE adoption (requires wallet function-body edits) — DB §16.10.
9. Outbox producer enqueue function `wallet.enqueue_outbox_event(...)` — DB §10.3.
10. Dead-letter requeue function `wallet.outbox_requeue(...)` — DB §16.4.
11. `fare_rules`, `surge_multipliers`, `admin_actions` DDL — DB §6.5/§6.6.
12. Pending-wallet accounting model (`pending_pesewas` source) — Payment §6, API §4.9.
13. Payment idempotency precedence (`payments.idempotency_key` vs `idempotency_keys`)
    — API §11.3.
14. `reconciliation_runs` canonical-location consolidation — DB §16.3, Payment §8.

**PENDING-but-not-blocking:** `auth_sessions`, `otp_codes`, `notification_tokens`,
`notifications`, `support_tickets`/`support_messages`, `dispatch_events`,
`reconciliation_runs` (base), and `ride_categories` (deferred) are not in
`KEKE_DATABASE_DESIGN.md`; their DDL must be authored and migrated in their own
stages before their dependent features ship. They are excluded from the *approved*
core ledger/payout migration but are not "OPEN" decisions.

---

## 8. Verification and acceptance criteria for every migration

Per-stage, in addition to the DB §15 payout test matrix and Roadmap §5/§10 (none of
which are executed here; all are acceptance targets only):

- **M-00:** `postgis` extension present; three roles exist; `wallet` schema owner is
  exactly `keke_wallet`; `CREATE` revoked on `public` and `wallet` for `PUBLIC` and
  `keke_app`.
- **M-01–M-06:** every FK resolves; composite FKs (`rides`, `payouts`) enforce
  ownership; partial unique indexes reject a second active ride / second accepted
  offer / duplicate provider event / duplicate idempotency key / duplicate payout
  correlation (constraint-level, not runtime).
- **M-07:** `ledger_head` has exactly the idempotent seed row; helper output is
  byte-deterministic; `validate_journal_entry` raises on <2 lines, mixed currency,
  imbalance, and `entry_hash` mismatch; `trg_journal_entry_balanced` is `DEFERRABLE
  INITIALLY DEFERRED`.
- **M-08:** `outbox_claim` returns only `PENDING` (available) / expired `PROCESSING`
  rows with a unique per-row claim token; renew/ack/retry/dead-letter reject a
  mismatched token or expired lease (`OUTBOX_LEASE_NOT_HELD`).
- **M-09:** `audit_logs` exists with append-only access (no `UPDATE`/`DELETE` grant
  to application roles).
- **M-10:** `request_payout` rejects NULL/zero amount, non-owned/non-`VERIFIED`
  destination, and insufficient balance (`INSUFFICIENT_BALANCE`); `process_payout`
  writes `payout.submit` in the same transaction; `record_provider_ref` rejects
  `PROVIDER_REF_CONFLICT`/`INVALID_PROVIDER_REF`; `reject_payout`/`complete_payout`/
  `fail_payout` honor the terminal-state machine (`INVALID_PAYOUT_STATE` on illegal
  transition); each reversal posts exactly one `:reversal` `PAYOUT` entry.
- **M-11:** `keke_app` cannot `INSERT/UPDATE/DELETE` on ledger tables; cannot execute
  helpers/trigger; is not a member of `keke_wallet`; `keke_outbox_worker` has no table
  access and only the five worker `EXECUTE` grants.

Every stage is verified by migration idempotency (re-run is a no-op) and
forward-only rollback policy (Roadmap §6).

---

## 9. Dependencies between migrations

- M-00 → all (roles/schema precede every object).
- M-01 → M-02, M-03, M-04 (`users`, `drivers`, `admins`, `passengers` are FK targets).
- M-02 → M-04 (`driver_vehicles` is the `rides` composite FK target).
- M-03 → M-04 (`driver_availability` FK to `drivers`; `pricing_zones` independent but PostGIS).
- M-04 → M-04B (`ride_locations` depends on `rides` and `drivers`).
- M-04 → M-05 (`rides` is `payments` target).
- M-05 → M-06 (`payout_destinations` independent; `payouts` depends on `drivers` + `payout_destinations`).
- M-06 → M-10 (`payouts`/`payout_events`/`payout_destinations` are writer targets).
- M-07 → M-10 (writers depend on ledger tables + helpers + trigger).
- M-08 → M-10 (`process_payout` inserts `outbox_events`; must exist first).
- M-10 → M-11 (privileges last, over existing objects).
- M-09 is independent of M-07/M-08/M-10; run any time after M-00.

## 10. Final list of unresolved blockers

1. **FAILURE callback review/reversal policy** (auto-reverse vs `REVIEW_REQUIRED`)
   — blocks the disposition schema and webhook behavior (DB §16.9).
2. **Outbox producer enqueue mechanism** (`wallet.enqueue_outbox_event` signature +
   authorization) — blocks reliable production of `ride.accepted` and future events
   (DB §10.3).
3. **`processing_started_at` adoption + backfill rule** — blocks aged-PROCESSING
   reconciliation (DB §16.5).
4. **`dedup_key` adoption** — blocks `payout.reevaluate` and dead-letter dedup
   (DB §16.4).
5. **`outbox_requeue()` + authorized recovery role** — blocks dead-letter recovery
   (DB §16.4).
6. **`ride.accepted` consumer + idempotency** — blocks passenger-notification delivery
   (DB §10.2).
7. **`keke_reconciliation` / `keke_audit` / `keke_audit_writer` exact grants** — blocks
   reconciliation and audit DB enforcement (DB §16.6, §11.1).
8. **`PX001` SQLSTATE adoption** (wallet function-body edits) — blocks callback
   contradiction classification (DB §16.10).
9. **Pending-wallet `pending_pesewas` accounting model** — blocks `GET /wallet`
   correctness (Payment §6, API §4.9).
10. **Payment idempotency precedence** — blocks final `POST /payments` dedup behavior
    (API §11.3).
11. **`fare_rules` / `surge_multipliers` / `admin_actions` persistence** — blocks
    pricing and admin-decision persistence (DB §6.5/§6.6).
12. **`reconciliation_runs` canonical DDL location** — blocks single-source-of-truth
    consolidation (DB §16.3, Payment §8).
13. **Provider-specific prerequisites** (statement/report capability, idempotency-key
    fallback, retry-count/backoff configuration, raw request-byte capture, evidence
    retention) — block reconciliation and outbox tuning (Index §6 items 6, 7, 8, 9, 10, 14, 15, 16).
14. **PENDING DDL** for `auth_sessions`, `otp_codes`, `notification_tokens`,
    `notifications`, `support_tickets`/`support_messages`, `dispatch_events`,
    `reconciliation_runs` (base) — required before those features ship (API §12).

---

*End of manifest. This document only plans migrations; it does not write SQL,
create objects, modify blueprint documents, or claim any runtime testing.*
