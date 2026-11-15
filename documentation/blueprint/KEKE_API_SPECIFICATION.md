# KEKE — API Specification

**Status:** Engineering blueprint. REST (JSON) + WebSocket realtime.
**Base URL:** `https://api.keke.gh/v1`
**Auth:** JWT Bearer (`Authorization: Bearer <access_token>`).

**Authoritative references:** `KEKE_DATABASE_DESIGN.md` (entities, canonical
enums, money precision) and `KEKE_SYSTEM_ARCHITECTURE.md` (services, security,
realtime, transactional outbox). This document defines the contract; the backend
is server-authoritative for all state. Where an endpoint depends on a persistence
entity not yet defined in the database design, that gap is called out in
[§12](#12-persistence-mapping-and-gaps).

---

## 1. Conventions

- **Content type:** `application/json; charset=utf-8`.
- **Ids:** UUID v4 strings for entities; `journal_lines` and `outbox_events` use
  bigint internally but are never exposed directly.
- **Money:** the API uses integer **pesewas** (`*_pesewas`) to avoid floating-point;
  GHS display is a client concern. Database storage is GHS `NUMERIC`: the **ledger**
  (`ledger_accounts.balance`, `journal_lines.amount`, `journal_lines.balance_after`)
  uses `NUMERIC(16,2)`; rides/payments fare and amount columns use `NUMERIC(12,2)`.
  Pesewas→GHS is `/100` and is lossless at exactly two decimals.
- **Timestamps:** ISO-8601 UTC (`2026-11-11T09:30:00Z`).
- **Coordinates:** `{ "lat": 6.6937, "lng": -1.6228 }` (WGS84).
- **Pagination:** `?cursor=<opaque>&limit=50` (cursor-based); response
  `{ "items": [...], "next_cursor": "..." }`.
- **Versioning:** mutable aggregates (`rides`, `offers`, `driver_availability`)
  carry a `version`; write responses and many read responses include it so clients
  can detect staleness and pass it back as a concurrency token.

### 1.1 Roles

| Role | Scope |
|---|---|
| `passenger` | request/cancel/rate rides, payments, support |
| `driver` | availability, offers, trip actions, earnings, payouts |
| `admin` | approvals, monitoring, pricing, settlements, support, audit |

---

## 2. Authentication and authorization

### 2.1 Request OTP

`POST /auth/otp/request`

```json
{ "phone": "+233241234567" }
```

→ `200`

```json
{ "request_id": "9f1c...", "expires_in": 300, "retry_after": 60 }
```

Rules:
- **Rate limit:** at most 1 request per phone per 60 s, and 10 per phone per 24 h
  (Redis).
- **Attempt limit:** at most 5 verification attempts per `request_id`.
- **Expiry:** the OTP expires in 5 minutes (`expires_in`).
- **Enumeration protection:** the request response is identical whether or not the
  phone has an account; there is no "unknown phone" variant. No account existence
  signal is returned at this stage.

### 2.2 Verify OTP

`POST /auth/otp/verify`

```json
{ "request_id": "9f1c...", "code": "123456" }
```

→ `200`

```json
{
  "access_token": "eyJ...",
  "refresh_token": "rt_...",
  "token_type": "Bearer",
  "expires_in": 900,
  "user": { "id": "uuid", "role": "passenger", "is_new": true }
}
```

- **No client-controlled role.** The request body contains **no `role` field**. The
  role is resolved **server-side** from the account record: an existing account
  returns its stored `users.role`; a brand-new account is always created as
  `passenger`.
- **No admin escalation.** Driver and admin roles cannot be requested via OTP.
  Driver accounts are provisioned through the driver-onboarding flow (still
  `users.role = 'driver'` but gated by server checks); admin accounts are created
  out-of-band by a super-admin. Public registration can never produce an admin or
  driver role directly.

### 2.3 JWT access tokens

- **Claims:** `sub` (user id), `role` (`passenger`|`driver`|`admin`), `aud`
  (`keke:mobile` or `keke:admin`), `iss` (`https://api.keke.gh`), `iat`, `exp`,
  `jti` (unique token id).
- **Signing:** RS256 (asymmetric). The verification key/algorithm is pinned
  server-side; `alg=none` and downgrade attacks are rejected.
- **Expiry:** ~15 minutes (`expires_in` 900 s).
- **Validation:** signature, `exp`, `aud` (must match the API surface), `iss`, and
  `role` are all validated on every request.

### 2.4 Refresh tokens (rotation + reuse detection)

`POST /auth/refresh` `{ "refresh_token": "rt_..." }` → a new access+refresh pair.

- Refresh tokens are opaque random strings stored **hashed** server-side
  (`auth_sessions`), bound to a `device_id`, and **rotated** on every use (the old
  token is invalidated).
- **Reuse detection:** if a refresh token that has already been rotated is
  presented again, the server treats it as token theft and revokes the **entire
  session/device** (all active refresh tokens for that device), returning
  `401 TOKEN_REUSE_DETECTED`.

### 2.5 Logout and revocation

`POST /auth/logout` (authenticated) revokes the current refresh token and clears
the device's push registration server-side (see §7).

- **Access-token revocation:** access tokens are short-lived and **not individually
  revocable**; revocation is achieved through refresh-token rotation/session
  revocation. A revoked session's access token remains valid only until its ≤15 min
  expiry. This is an explicit design trade-off, documented here.

### 2.6 Authorization model

- **Role** grants coarse access to endpoint families.
- **Resource** checks (ownership) are enforced **in the owning service**, not only
  at the edge: a passenger may only read/cancel/rate *their own* ride; a driver may
  only act on offers/rides *assigned to them*; admins require the specific RBAC
  role (§8).

---

## 3. Passenger endpoints

> **Ownership rule:** every `/rides/:id` operation verifies the caller is that
> ride's passenger (or driver for driver-side actions, or an authorized admin).
> Cross-user access returns `404 NOT_FOUND` (never `403`) to avoid existence leaks.

### 3.1 Profile

- `GET /me` → profile + rating summary.
- `PATCH /me` → update `first_name`, `last_name`, `email`.

### 3.2 Saved places

- `GET /me/saved-places`
- `POST /me/saved-places` `{ "label", "address", "lat", "lng" }`
- `DELETE /me/saved-places/:id`

### 3.3 Create a ride

`POST /rides`

```json
{
  "pickup":      { "lat": 6.6937, "lng": -1.6228, "address": "Kejetia Market" },
  "dropoff":     { "lat": 6.6780, "lng": -1.6150, "address": "KNUST" },
  "category":    "KEKE",
  "payment_method": "CASH"
}
```

→ `201`

```json
{
  "ride_id": "uuid",
  "status": "REQUESTED",
  "version": 0,
  "category": "KEKE",
  "fare_estimate": {
    "currency": "GHS",
    "min_amount_pesewas": 1000,
    "max_amount_pesewas": 1400
  },
  "pickup_eta_s": 180
}
```

- **`category`** is the vehicle-category string. The MVP has a single category
  `"KEKE"`, corresponding to `driver_vehicles.type`. It is server-validated against
  the configured category set; there is no separate `ride_categories` table in the
  current database design (see §12).
- **Fare estimate** uses `min_amount_pesewas`/`max_amount_pesewas` (never an
  ambiguous string `range`). The estimate is advisory; the authoritative fare is
  finalized at completion.
- **`REQUESTED` → `SEARCHING`:** the ride is created in `REQUESTED`; the dispatch
  worker transitions it to `SEARCHING` (server-initiated) and notifies the
  passenger via `ride.status`. Clients should render `REQUESTED` and `SEARCHING`
  equivalently as "finding a driver".
- **No-driver-found:** if dispatch exhausts candidates, the server transitions the
  ride to `CANCELLED` with `reason_code = NO_DRIVER_FOUND` and notifies the
  passenger. This is an asynchronous lifecycle outcome, not an HTTP error on
  `POST /rides`.

Synchronous creation errors: `422 SERVICE_AREA_UNSUPPORTED` (pickup outside a
pricing zone), `422 NO_CATEGORY_AVAILABLE`, `422 PAYMENT_REQUIRED` (MoMo pre-auth
needed).

### 3.4 Get a ride

`GET /rides/:id` → the ride's current server state (see §3.3 fields plus
`status`, `version`, assigned `driver`/`vehicle` when present and authorized).

### 3.5 Cancel a ride

`POST /rides/:id/cancel` `{ "reason_code": "CHANGED_MIND" }` → `200`

```json
{ "ride_id": "uuid", "status": "CANCELLED", "version": 4, "fee_amount_pesewas": 0 }
```

Fee policy is in `KEKE_RIDE_LIFECYCLE.md`.

### 3.6 Rate the driver

`POST /rides/:id/rate-driver` `{ "score": 5, "comment": "..." }` → `204`.

(Driver-rates-passenger is a separate operation, §4.8.)

### 3.7 History

`GET /rides/history?cursor=...` → page of completed/cancelled rides.

### 3.8 Support tickets

- `POST /support/tickets` `{ "subject", "category", "ride_id", "body" }` → `201`
  `{ "ticket_id", "status": "OPEN" }`.
- `GET /support/tickets?cursor=...` → the caller's tickets.
- `GET /support/tickets/:id` → ticket + messages (caller is the owner or admin).
- `POST /support/tickets/:id/messages` `{ "body" }` → `201`.

---

## 4. Driver endpoints

### 4.0 Become a driver (application)

`POST /driver/apply` (authenticated `passenger`):

- The request carries **no `role` field** — a passenger cannot self-assign a role.

**The authorized server-side transaction** performs, in order:

1. `BEGIN`.
2. `SELECT ... FOR UPDATE` the applicant's `users` row.
3. Verify the user exists, `users.status = 'ACTIVE'`, and
   `users.role = 'passenger'`.
4. Check whether a `drivers` row already exists for that `user_id`.
5. If a `drivers` row exists or the role is already `driver`, return
   `422 ALREADY_DRIVER` **without creating another record**.
6. `INSERT` the `drivers` row (`driver_status = 'ONBOARDING'`,
   `verification_status = 'PENDING'`).
7. `UPDATE users SET role = 'driver', version = version + 1`.
8. `COMMIT` — the driver row and the role change commit **together**.

- → `201` `{ "driver_status": "ONBOARDING" }`.

**Uniqueness safeguard:** `drivers.user_id` is a `PRIMARY KEY`, so a concurrent
duplicate insert raises a uniqueness violation; the endpoint maps that violation to
`422 ALREADY_DRIVER`, never an unhandled 5xx.

**Idempotency:** `POST /driver/apply` relies on its **transaction +
`drivers.user_id` uniqueness constraint** for safe duplicate handling — it does
**not** use the generic `Idempotency-Key` contract (§11). A duplicate application
is rejected by the uniqueness constraint and the pre-check, and reported as
`ALREADY_DRIVER`. (A client `Idempotency-Key` is tolerated but not required for
correctness here.)

**Application status** is the `drivers.driver_status` value (`ONBOARDING` = under
review). A separate `driver_applications` table is **not required** — the `drivers`
row serves as the application record (no new DDL).

**Privilege escalation:** this endpoint can only produce a `driver` role from an
authenticated `passenger`. Admin roles are provisioned out-of-band by a super-admin
and are never reachable through any client endpoint.

**Onboarding gating:** the account stays `driver_status = ONBOARDING` and cannot go
`ONLINE` until `verification_status = 'APPROVED'` **and** an approved vehicle
exist, at which point the server advances `driver_status` to `ACTIVE`. Dispatch
eligibility (per `KEKE_DATABASE_DESIGN.md`) additionally requires
`users.status = 'ACTIVE'` and `driver_availability.status = 'ONLINE'`.

### 4.1 Profile & onboarding

- `GET /me`, `PATCH /me`.
- `GET /onboarding` → ordered step list + per-step status (server-driven).

```json
{ "steps": [
  { "id": "phone",     "status": "COMPLETE", "blocking": true },
  { "id": "profile",   "status": "COMPLETE", "blocking": true },
  { "id": "documents", "status": "IN_REVIEW", "blocking": true },
  { "id": "vehicle",   "status": "PENDING", "blocking": true }
] }
```

### 4.2 Vehicle registration

- `POST /vehicles` — register a keke (`type` defaults to `KEKE`, make/model/color/
  plate/capacity).
- `GET /vehicles` — list the driver's vehicles + approval status.
- `PATCH /vehicles/:id` — edit before approval only.

### 4.3 Documents (upload + retrieval)

Two-step upload:

1. `POST /uploads/presign`

```json
{ "document_type": "DRIVER_LICENSE", "content_type": "image/jpeg", "sha256": "…" }
```

→ `201`

```json
{ "upload_url": "…", "object_key": "…", "expires_in": 900 }
```

- **Presigned URL expiry:** `expires_in` 15 minutes (short-lived).
- **Ownership:** `object_key` is scoped to the caller's driver id; another driver
  cannot reference it in step 3.
- **Content-type allowlist:** `image/jpeg`, `image/png`, `image/heic`, `application/pdf`.
- **Size limit:** ≤ 10 MB per document (enforced at presign and on ingest).
- **Integrity:** the uploaded object's `sha256` must equal the declared digest; the
  server rejects a mismatch on ingest/registration.

2. Client `PUT`s bytes to `upload_url` (object storage).
3. `POST /documents` `{ "document_type", "object_key", "vehicle_id" }` → `201`
   creates a `verification_documents` row (`PENDING`), verifying the object's
   sha256 and ownership.

Retrieval/status:

- `GET /documents` → the driver's documents + `status`.
- `GET /documents/:id` → one document (metadata + short-lived signed read URL for
  the owner only; admins use §8 review endpoints).

### 4.4 Availability

`POST /availability` `{ "status": "ONLINE" }` → `200`

```json
{ "status": "ONLINE", "blockers": [] }
```

`POST /availability` `{ "status": "OFFLINE" }` → `{ "status": "OFFLINE" }`.

- **Requirements:** going `ONLINE` requires an `ACTIVE` account and driver, `APPROVED`
  verification and vehicle, and a **fresh** location (see §5.1). A go-online
  attempt with a stale/missing location is rejected.
- **Stale-location rejection:** if the driver's last location is older than
  `STALE_AFTER` (15 s) or accuracy worse than `MAX_ACCURACY` (50 m), the server
  returns `422 STALE_LOCATION` (request a fresh fix first).
- **Blocked:** if eligibility blockers exist, returns `422 GO_ONLINE_BLOCKED`:

```json
{ "error": { "code": "GO_ONLINE_BLOCKED", "message": "…",
  "details": { "blockers": [ { "id": "documents", "message": "Driver license pending review" } ] } } }
```

### 4.5 Dispatch / offers

- `GET /offers/pending` → the driver's currently pending offers (server-driven
  payload). Each offer carries `offer_id`, `ride_id`, pickup/dropoff, `distance_m`,
  `pickup_eta_s`, `fare` (estimate), and `expires_at`.

```json
{ "offers": [
  { "offer_id": "uuid", "ride_id": "uuid", "version": 0,
    "pickup":  { "address": "Kejetia", "lat": 6.69, "lng": -1.62 },
    "dropoff": { "address": "KNUST" },
    "distance_m": 3200, "pickup_eta_s": 240,
    "fare": { "currency": "GHS", "amount_pesewas": 1200 },
    "expires_at": "2026-11-11T09:31:00Z" }
] }
```

- `POST /offers/:id/accept` → `200`

```json
{ "offer_id": "uuid", "ride_id": "uuid", "status": "ACCEPTED", "version": 2 }
```

  or `409 OFFER_EXPIRED` / `409 OFFER_WITHDRAWN` / `409 OFFER_ALREADY_RESPONDED`.

- **Acceptance is atomic:** the server performs the single acceptance transaction
  defined in `KEKE_DATABASE_DESIGN.md` §5.4 (conditional offer update matching
  `offer_id`+`ride_id`+`driver_id`, `SEARCHING` ride guard, eligibility row locks,
  `ONLINE` availability check, driver/vehicle assignment, accepted-offer
  uniqueness, and outbox insertion). A failed step returns the corresponding `409`
  with the terminal reason.

- `POST /offers/:id/reject` `{ "reason_code": "TOO_FAR" }` → `204`.

### 4.6 Trip actions

Each response includes the authoritative `version`:

- `POST /rides/:id/start_navigation` → `200`
  `{ "ride_id", "status": "DRIVER_EN_ROUTE", "version" }`.
- `POST /rides/:id/arrive` → `200` `{ "ride_id", "status": "DRIVER_ARRIVED", "version" }`.
- `POST /rides/:id/start` `{ "pickup_code": "1234" }` → `200`
  `{ "ride_id", "status": "IN_TRIP", "version" }` or `400 INVALID_PICKUP_CODE`.
- `POST /rides/:id/complete` → `200` `{ "ride_id", "status": "COMPLETED", "version",
  "fare": { "currency": "GHS", "total_amount_pesewas": 1200 } }`.

### 4.7 Driver cancellation

`POST /rides/:id/cancel` `{ "reason_code": "PASSENGER_NO_SHOW" }` → `200`.

- **Driver vs passenger cancellation** are the same endpoint but distinguished by
  the caller's role: a `driver` cancelling is authorized only for rides assigned to
  them and only in driver-legal states; a `passenger` cancelling is authorized only
  for their own rides. The `cancellations.initiated_by` value is derived from the
  authenticated role, never from the request body.

### 4.8 Rate the passenger

`POST /rides/:id/rate-passenger` `{ "score": 5, "comment": "..." }` → `204`.

### 4.9 Earnings & wallet

- `GET /earnings` → server-computed summary (period, gross, net, commission,
  bonuses). Server-supplied; no client money math.
- `GET /earnings/breakdown?from=...&to=...`
- `GET /wallet` → `{ "available_pesewas": 8000, "pending_pesewas": 2000 }`.
- `GET /wallet/transactions?cursor=...` → journal lines (projected to the caller's
  `DRIVER_WALLET` account).

> **Wallet field sources (see `KEKE_PAYMENT_AND_WALLET.md` §6):** `available_pesewas`
> is `ledger_accounts.balance` for the `DRIVER_WALLET` account. `pending_pesewas` has
> no single database column yet; its accounting model (derived from ride/payment
> lifecycle vs. a separate accrual account) is **OPEN** and must be documented before
> `GET /wallet` is implemented.

---

## 5. Location endpoints

### 5.1 Driver location heartbeat

Primary transport is the WebSocket `location.update` (§9). REST fallback:

`POST /location` `{ "lat", "lng", "accuracy_m", "speed_mps", "heading_deg",
"recorded_at" }` → `204`.

- **Fields:** `lat`/`lng` (WGS84), `accuracy_m` (≥0), `speed_mps` (≥0),
  `heading_deg` (0–360), `recorded_at` (device capture time, ISO-8601).
- **Freshness:** a fix is fresh if `now − recorded_at ≤ 15 s` and
  `accuracy_m ≤ 50 m` (both tunable). Stale/inexact fixes are not used for
  dispatch; the server stores the last fresh fix and marks the driver stale.
- **Timestamp handling:** `recorded_at` is the device time; the server also records
  `server_received_at`. Clock skew is reconciled at ingest (see DB design §7).

### 5.2 Passenger driver-position stream

`GET /rides/:id/location` returns the last known driver position for first paint
(authorized: ride passenger/driver/admin); live updates flow over `ride.driver_position`.

### 5.3 Trip track

`GET /rides/:id/track` → down-sampled `ride_locations` polyline (admin, or the
ride's participants post-trip).

---

## 6. Payments, wallet and payouts

> All money is **server-authoritative**. The API exposes integer pesewas; the
> ledger stores `NUMERIC(16,2)` GHS. Provider signature verification, webhook
> replay protection, and reconciliation are defined in `KEKE_PAYMENT_AND_WALLET.md`
> (§3 and §8) and are not repeated here.

### 6.1 Initiate Mobile Money charge

`POST /payments` (passenger)

```json
{ "ride_id": "uuid", "method": "MOBILE_MONEY", "phone": "+233241234567" }
```

→ `202` `{ "payment_id": "uuid", "status": "PENDING", "provider": "HUBTEL" }`.

### 6.2 Provider webhook

`POST /payments/webhook/:provider` — server-to-server; signature-verified, replay-
protected, idempotent (see payment doc).

### 6.3 Payment status

`GET /payments/:id` → `{ "payment_id", "status", "amount_pesewas" }`.

### 6.4 Payment ↔ journal ↔ payout relationship

- A ride completion produces a `payment` record and a balanced `journal_entries`
  (header + `journal_lines`) that credits `DRIVER_WALLET`/`COMPANY_COMMISSION` and
  debits the clearing account — atomically in the Wallet service.
- A **payout** reduces the driver's `DRIVER_WALLET` balance via a `PAYOUT` journal
  entry and creates a `payouts` record. The journal is the financial truth; the
  payout record is the operational workflow.

### 6.5 Payout destinations

- `POST /payouts/destinations` `{ "type": "MOBILE_MONEY", "phone": "+233…" }` →
  `201` `{ "destination_id", "status": "PENDING" }`.
- `GET /payouts/destinations` → the driver's registered destinations.
- `POST /payouts/destinations/:id/verify` `{ "code": "123456" }` → verifies the
  MoMo phone via OTP (`PENDING` → `VERIFIED`).
- `DELETE /payouts/destinations/:id`.

**Entity:** `payout_destinations` (`KEKE_DATABASE_DESIGN.md` §8.1) — fields
`id (UUID)`, `driver_id (→ drivers.user_id)`, `destination_type (MOBILE_MONEY)`,
`phone (E.164)`, `status (PENDING | VERIFIED)`, `verified_at`, `created_at`. A
payout references a **verified** destination only (enforced by
`wallet.request_payout`, DB §9).

### 6.6 Payouts

- `POST /payouts` `{ "amount_pesewas": 8000, "destination_id": "uuid" }` → `201`
  `{ "payout_id", "status": "PENDING", "amount_pesewas" }`.
- `GET /payouts?cursor=...` → payout history.

**Entity:** `payouts` (`KEKE_DATABASE_DESIGN.md` §8.2) — fields `id (UUID)`,
`driver_id (→ drivers.user_id)`, `destination_id (→ payout_destinations.id)`,
`amount (GHS NUMERIC(12,2), exposed as amount_pesewas)`, `status
(PENDING | PROCESSING | COMPLETED | REJECTED)`, `provider_ref`, `requested_at`,
`processed_at`, `rejection_reason`, `version`. It is related to the journal via
`journal_entries.correlation_id = payout_id` (the `PAYOUT` journal entry).

**State machine:** `PENDING → PROCESSING → COMPLETED | REJECTED`, with the safety
rules (see `KEKE_DATABASE_DESIGN.md` §8.2):

- `PENDING` — reserved, not yet submitted; admin may reject before submission.
- `PROCESSING` — submitted to the provider, outcome pending. Never reversed while
  the outcome is unknown; a timeout/missing webhook is **not** failure.
- `COMPLETED` — provider-confirmed success; terminal, never reversed.
- `REJECTED` — terminal (pre-submission rejection, or provider-confirmed failure);
  never transitioned back to `COMPLETED`.

A payout request always creates a **new** `payouts` record; no terminal payout can
return to `PENDING`, and a re-request never reopens or overwrites an earlier payout.

- **Balance validation:** `amount_pesewas` > 0 (else `422 INVALID_PAYOUT_AMOUNT`)
  and ≤ available wallet balance (else `422 INSUFFICIENT_BALANCE`).
- **Atomic reserve/debit:** the payout request runs through the dedicated
  controlled operation `wallet.request_payout(driver_id, destination_id, amount)`
  (see `KEKE_DATABASE_DESIGN.md` §9), which validates the amount, locks and
  validates the destination (owned by the driver and `VERIFIED`), takes the
  `ledger_head` lock and `SELECT … FOR UPDATE` on the `DRIVER_WALLET` row, checks
  the available balance **while it is locked**, then writes the `PAYOUT` journal
  entry and inserts the `payouts` record. The balance check, reservation/debit,
  `payouts` insert, and idempotency completion commit in one transaction — so
  simultaneous payout requests are serialized and cannot both spend the same
  available balance, and a retry cannot debit twice.
- **Submission (`PENDING → PROCESSING`):** `wallet.process_payout(payout_id)`
  transitions the payout to `PROCESSING` and enqueues a durable `payout.submit`
  outbox event in the same transaction. A worker performs the provider disburse
  call using `payout_id::text` as the provider idempotency key, then persists the
  provider reference via `wallet.record_provider_ref` (initial assignment only; an
  identical retry is idempotent, a different reference is rejected with
  `PROVIDER_REF_CONFLICT`, and a null/blank reference is rejected with
  `INVALID_PROVIDER_REF`). A timeout or unknown submission outcome never restores
  the wallet.
- **Idempotency:** `Idempotency-Key` required; a retry with the same key returns
  the original payout and **cannot debit twice**.
- **Failure/rejection (two distinct paths):**
  - **Administrative rejection before submission:** `wallet.reject_payout`
    (`PENDING → REJECTED`) reverses the reservation, exactly once.
  - **Provider-confirmed failure (two forms):**
    - **Definitive synchronous rejection** (the disburse call returns a definitive
      failure): the worker calls `wallet.fail_payout(payout_id, NULL, reason)` —
      evidence is the synchronous rejection reason; no provider event id is
      invented.
    - **Verified webhook failure** (later): the webhook handler inserts a
      `payout_events` row and calls `wallet.fail_payout(payout_id,
      provider_event_id, reason)` in the same transaction — evidence is the FAILURE event.
  - **Unknown outcome:** `PROCESSING` stays unresolved; the balance is not
    restored and the payout is flagged for reconciliation.
  - **Success:** `wallet.complete_payout` (`PROCESSING → COMPLETED`), no reversal.
  A `COMPLETED` payout can never be reversed, and a `REJECTED` payout can never be
  completed (`409 INVALID_PAYOUT_STATE`).
- **No negative-balance policy** is invented here: whether `DRIVER_WALLET` may go
  negative is an unresolved business decision (`KEKE_DATABASE_DESIGN.md` §9).

### 6.7 Payout provider webhook

`POST /payouts/webhook/:provider` — server-to-server disbursement callback. The
handler must:

1. Verify the provider signature (as for payments — `KEKE_PAYMENT_AND_WALLET.md`).
   `provider` and `provider_event_id` are required (non-null) for authenticated
   callbacks.
2. In **one transaction**: insert the `payout_events` row (`ON CONFLICT DO
   NOTHING`); on a duplicate event id, compare `payout_id`, `event_type`, and
   payload hash — identical ⇒ no-op, conflicting ⇒ reject + flag for
   reconciliation/security review.
3. Apply the outcome (same transaction): `SUCCESS` → `wallet.complete_payout`;
   `FAILURE` → `wallet.fail_payout(payout_id, provider_event_id, reason)`;
   `UNKNOWN` → leave unresolved and flag for reconciliation.

A duplicate callback is a no-op; a conflicting outcome returns
`409 INVALID_PAYOUT_STATE` and is reconciled, never auto-reversed.

> **FAILURE review policy (OPEN):** step 3's immediate `FAILURE → fail_payout`
> reversal is the current documented default; a review-gated (`REVIEW_REQUIRED`)
> dual-control alternative is proposed in `KEKE_DATABASE_DESIGN.md` §16.9 and is
> tracked as an open decision in `KEKE_BLUEPRINT_INDEX.md` §6. No new wallet
> function signature is introduced by either option.

---

## 7. Notifications and devices

> **Persistence gap:** device tokens map to `notification_tokens` (referenced in
> `KEKE_SYSTEM_ARCHITECTURE.md` §5 but whose DDL is not yet in
> `KEKE_DATABASE_DESIGN.md` — see §12).

- `POST /devices` `{ "token": "fcm…", "platform": "android"|"ios" }` → `201`
  registers/upserts a push token for the current user. **Multiple devices** per
  user are supported (a user may have several tokens).
- `GET /devices` → list the user's registered devices.
- `DELETE /devices/:id` → remove a device token.
- **Logout revocation:** `POST /auth/logout` clears the current device's token; an
  explicit `DELETE /devices/:id` clears others.
- **Invalid-token handling:** when FCM/APNs reports a token `NotRegistered`, the
  server removes it from `notification_tokens` so future sends skip it.

---

## 8. Admin endpoints and security

**Admin auth:** admin tokens use a distinct audience/issuer (`aud: keke:admin`),
issued only to admin accounts, and **MFA (TOTP)** is required at admin sign-in
beyond OTP. A mobile token is never valid for admin endpoints.

**RBAC:** `SUPER_ADMIN`, `OPS`, `SUPPORT`, `FINANCE` (matches
`admins.admin_role`). Every admin endpoint checks the role server-side; the client
role is never trusted. Sensitive actions emit an audit event to the Audit module
(sole writer of `audit_logs`) — including driver/vehicle approval, payout
processing/rejection, force-cancel, refund/adjustment, and personal-data/document
views.

| Endpoint | Method | RBAC | Purpose |
|---|---|---|---|
| `/admin/drivers` | GET | OPS/SUPER | list/filter drivers |
| `/admin/drivers/:id` | GET | OPS/SUPER | detail + documents + vehicles |
| `/admin/drivers/:id/approve` | POST | OPS/SUPER | approve verification (audit) |
| `/admin/drivers/:id/reject` | POST | OPS/SUPER | reject with reason (audit) |
| `/admin/drivers/:id/suspend` | POST | OPS/SUPER | suspend (audit) |
| `/admin/vehicles/:id/approve` / `reject` | POST | OPS/SUPER | vehicle approval (audit) |
| `/admin/documents/:id/review` | POST | OPS/SUPER | `{ "status": "APPROVED"\|"REJECTED", "reason" }` (audit) |
| `/admin/rides` | GET | OPS/SUPPORT | live + historical |
| `/admin/rides/:id` | GET | OPS/SUPPORT | detail incl. track (audit for PII view) |
| `/admin/pricing/zones` | GET/POST/PATCH | OPS/SUPER | zones (audit on write) |
| `/admin/pricing/fare-rules` | GET/POST/PATCH | OPS/SUPER | fares (audit on write) |
| `/admin/pricing/surge` | POST | OPS/SUPER | surge (audit) |
| `/admin/payments` | GET | FINANCE | payment ledger |
| `/admin/payouts` | GET | FINANCE | payout queue |
| `/admin/payouts/:id/process` | POST | FINANCE | call `wallet.process_payout` → `PROCESSING` (audit) |
| `/admin/payouts/:id/reject` | POST | FINANCE | call `wallet.reject_payout` → `REJECTED` (audit; `PENDING`-only, `409 INVALID_PAYOUT_STATE` otherwise) |
| `/admin/support/tickets` | GET/PATCH | SUPPORT | manage tickets |
| `/admin/analytics/summary` | GET | OPS/SUPER | KPIs |
| `/admin/audit-logs` | GET | SUPER | audit trail |

### 8.1 Reconciliation & resolution endpoints (PROPOSED — NOT YET IMPLEMENTED)

| Endpoint | Method | RBAC | Purpose |
|---|---|---|---|
| `/admin/reconciliation/payouts` | POST | FINANCE | trigger an on-demand payout reconciliation run |
| `/admin/reconciliation/runs` | GET | FINANCE | list reconciliation runs/findings |
| `/admin/reconciliation/runs/:id` | GET | FINANCE | run detail + findings |
| `/admin/payouts/:id/resolve` | POST | FINANCE | operator resolution of a stuck/`REVIEW_REQUIRED` payout |

`POST /admin/payouts/:id/resolve` accepts `{ "outcome": "COMPLETED" | "REJECTED" |
"UNRESOLVED", "provider_ref"?, "provider_event_id"?, "reason"? }`:

- `provider_ref` = provider transaction reference (used by `complete_payout`).
- `provider_event_id` = unique callback/event id (used by `fail_payout`; `NULL` for
  synchronous/statement failure).
- `reason` = operator explanation (audit).
- `"COMPLETED"` → `complete_payout(payout_id, provider_ref)` (only if `PROCESSING`).
- `"REJECTED"` → `fail_payout(payout_id, provider_event_id, reason)` (only if
  `PROCESSING`; `FAILURE` resolution is review-gated).
- `"UNRESOLVED"` → no transition; a "still uncertain" finding is recorded.
- Contradictory terminal payouts are refused (`409 INVALID_PAYOUT_STATE`) and
  escalated — never auto-reversed.

No new wallet function signatures are introduced.

---

## 9. WebSocket realtime contract

Endpoint: `wss://api.keke.gh/v1/ws`.

- **Authentication:** the JWT must be sent in the first `auth` message. An
  **unauthenticated connection is closed after 10 s**.
- **JWT expiry/revocation:** a socket whose access token expires or whose session
  is revoked is disconnected (or forced to re-auth); the client refreshes and
  re-subscribes.

Messages are JSON `{ "type": "...", "seq": n, "data": {...} }`. Every **server→
client** event carries a monotonically increasing `seq` (per channel) for client
replay detection and deduplication.

### 9.1 Client → server

| Event | Payload | Notes |
|---|---|---|
| `auth` | `{ "token" }` | authenticate; must be first |
| `location.update` | `{ lat, lng, accuracy_m, speed_mps, heading_deg, recorded_at }` | driver heartbeat (validated, rate-limited) |
| `ride.subscribe` | `{ "ride_id" }` | join a ride channel |

### 9.2 Server → client

| Event | Audience | Payload |
|---|---|---|
| `offer.new` | driver | `{ offer_id, ride_id, pickup, dropoff, fare, expires_at }` |
| `offer.withdrawn` | driver | `{ offer_id, reason }` |
| `ride.status` | passenger+driver | `{ ride_id, status, version, updated_at }` |
| `ride.driver_position` | passenger | `{ ride_id, lat, lng, heading_deg, recorded_at }` |
| `ride.driver_assigned` | passenger | `{ ride_id, driver, vehicle, eta_s }` |
| `ride.fare_updated` | passenger | `{ ride_id, amount_pesewas }` |
| `payment.status` | passenger/driver | `{ payment_id, status }` |
| `notification` | any | `{ notification_id, type, title, body, payload }` |

### 9.3 Security and reliability

- **Subscription authorization:** every `ride.subscribe` is authorized against the
  ride's participants (passenger, assigned driver) or an admin; a user **cannot**
  subscribe to another user's ride channel (rejected with `FORBIDDEN`).
- **Message validation & rate limits:** inbound events are schema-validated
  (`class-validator`) and rate-limited per connection and per user; connection
  count is bounded (e.g. per-user and global limits).
- **Per-channel sequence:** `seq` is a monotonically increasing integer **per
  channel** (e.g. `ride:<id>`), not global. Each channel has its own sequence.
- **Gap detection:** a client detects a gap when it receives `seq > last_seen + 1`;
  it must treat the gap as a missed-event condition and resync — it must never
  infer state from missing events.
- **Reconnect/resync:** on reconnect the client re-auths, re-subscribes, and
  resyncs **authoritative state from REST** (`GET /rides/:id`,
  `GET /offers/pending`, `GET /wallet`). The client does **not** resume solely from
  a stored `seq`; the REST snapshot is authoritative, and `seq` is used only to
  discard already-applied events.
- **Deduplication:** replayed events (same `seq`/`version`) must not cause
  duplicate client-side state transitions — clients dedupe by `seq` and treat state
  transitions as idempotent by `version`.

---

## 10. Error handling

### 10.1 Error envelope

```json
{
  "error": {
    "code": "OFFER_EXPIRED",
    "message": "This ride offer is no longer available.",
    "request_id": "req_abc123",
    "details": {}
  }
}
```

### 10.2 HTTP mapping

| Status | Use |
|---|---|
| 400 | malformed request / validation (`VALIDATION_ERROR`) |
| 401 | missing/expired token (`UNAUTHORIZED`, `TOKEN_REUSE_DETECTED`, `INVALID_REFRESH_TOKEN`) |
| 403 | role/resource not permitted (`FORBIDDEN`) |
| 404 | resource not found (`NOT_FOUND`; used for cross-user access to avoid leaks) |
| 409 | state conflict / stale `version` (`CONFLICT`, `OFFER_*`, `INVALID_STATE_TRANSITION`) |
| 422 | semantically invalid / business-rule rejection (`GO_ONLINE_BLOCKED`, `STALE_LOCATION`, `INSUFFICIENT_BALANCE`, `SERVICE_AREA_UNSUPPORTED`, `NO_CATEGORY_AVAILABLE`, `IDEMPOTENCY_KEY_REUSED`, `PAYMENT_REQUIRED`) |
| 429 | rate limited (`RATE_LIMITED`) |
| 5xx | internal (`INTERNAL`) with `request_id` |

**Resolved:** `GO_ONLINE_BLOCKED` is canonical **422** (a business-eligibility
rejection), not `409`. `409` is reserved for concurrency/state conflicts.

### 10.3 Canonical error codes

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INVALID_REFRESH_TOKEN`, `TOKEN_REUSE_DETECTED`,
`FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `OFFER_EXPIRED`, `OFFER_WITHDRAWN`,
`OFFER_ALREADY_RESPONDED`, `INVALID_PICKUP_CODE`, `INVALID_STATE_TRANSITION`,
`GO_ONLINE_BLOCKED`, `STALE_LOCATION`, `SERVICE_AREA_UNSUPPORTED`,
`NO_CATEGORY_AVAILABLE`, `NO_DRIVER_FOUND`, `ALREADY_DRIVER`, `PAYMENT_FAILED`,
`PAYMENT_ALREADY_PROCESSED`, `INSUFFICIENT_BALANCE`, `INVALID_PAYOUT_AMOUNT`,
`INVALID_PAYOUT_DESTINATION`, `INVALID_PAYOUT_STATE`, `INVALID_PROVIDER_REF`,
`PROVIDER_REF_CONFLICT`, `RATE_LIMITED`,
`IDEMPOTENCY_KEY_REUSED`,
`SURGE_CONFIRMATION_REQUIRED`.

- `VALIDATION_ERROR` `details` is a stable shape:
  `{ "fields": [ { "field": "pickup.lat", "reason": "out_of_range" } ] }`.
- `INVALID_STATE_TRANSITION` carries
  `details: { "from", "to", "expected" }`.
- **Concurrency conflicts** (`409 CONFLICT`) return the current `version` where the
  caller is authorized to view the resource, so the client can retry.

---

## 11. Idempotency and concurrency

### 11.1 Generic idempotency contract

Mutating endpoints (ride create/cancel, offer accept/reject, payment initiate,
payout request, payout-destination verify) accept an `Idempotency-Key` header.
The generic contract:

- **Scope:** a key is unique per **authenticated principal + operation**
  (endpoint). A passenger's ride-create key and a driver's payout key are distinct
  even if the raw string collides.
- **Payload hash:** the server stores a hash of the request payload (canonical
  JSON) alongside the key.
- **Processing states:** each record is `IN_PROGRESS` (first request executing) or
  `COMPLETED` (a response already produced).
- **Stored result:** on completion the server stores the original response (or the
  resulting resource id/version) and replays it for retries.
- **Concurrency:** a second request with the same key while `IN_PROGRESS` is
  serialized (waits for the first, then receives the same result) — never two side
  effects.
- **Payload mismatch:** the same key with a **different** payload hash returns
  `422 IDEMPOTENCY_KEY_REUSED`.
- **Retention/cleanup:** records are retained **24 hours**, then purged by a
  background job.

**Crash recovery requirements:**

1. **Database uniqueness:** `idempotency_keys` must have
   `UNIQUE (principal_id, operation, key_hash)` as the final safeguard.
2. **Processing lease:** an `IN_PROGRESS` record carries a `lease_expires_at` and a
   processing-owner marker; a worker must not assume an abandoned request is safe
   to execute again.
3. **Atomic completion:** where the business operation and the idempotency record
   share a database, the business mutation and the transition to `COMPLETED` commit
   in the **same transaction**.
4. **Crash recovery:** after a lease expires, recovery first determines whether the
   business operation already committed; if it did, it reconstructs/stores the
   original result and marks the record `COMPLETED` — it does **not** repeat the
   side effect.
5. **External side effects:** external payments/payouts are fenced by the
   transactional outbox and provider-side idempotency/reference; an API-worker
   crash never blindly repeats an external payment or payout.
6. **Fencing:** an expired worker must not complete/overwrite a record after
   another worker has taken over — enforced via a lease generation/version
   (compare-and-set) on the completion update.
7. **Concurrent retries:** same key + same payload → original result; same key +
   different payload → `422 IDEMPOTENCY_KEY_REUSED`.

**Persistence:** `idempotency_keys` is defined in `KEKE_DATABASE_DESIGN.md` §8.3
with `UNIQUE (principal_id, operation, key_hash)`.

**Payout transaction workflow** (the canonical use of this contract) — a single
PostgreSQL transaction:

1. `BEGIN`.
2. **Claim or lock** the idempotency record: `INSERT ... ON CONFLICT
   (principal_id, operation, key_hash) DO NOTHING`; if it already exists,
   `SELECT ... FOR UPDATE`.
3. **Compare payload hash**; mismatch → `422 IDEMPOTENCY_KEY_REUSED`.
4. **Replay** the stored `response_json`/`resource_ref` if already `COMPLETED`, and
   stop (no side effect).
5. **Execute once:** `wallet.request_payout(driver_id, destination_id, amount)`.
6. **Store result:** `resource_ref = payout_id`, `response_json`.
7. **Mark `COMPLETED`.**
8. `COMMIT`.

The payout record, the original journal entry, the ledger updates, and the
idempotency completion all commit or roll back **together**. If the transaction
rolls back, none of them remain; if it commits, they all exist.

**Lost response (not a mid-transaction crash):** if the transaction commits but the
HTTP response is lost, a retry claims the same key, finds the `COMPLETED` record,
and returns the stored original response — `request_payout` is **not** executed
again. Under this single-transaction model there is no state where the payout is
committed but the idempotency record is uncommitted, because they are written in
the same transaction.

**Lease vs single-transaction:** the lease/fencing recovery in the "Crash recovery
requirements" above applies to workflows with **independently persisted processing
claims** (e.g. the `payout.submit` outbox event, whose worker holds a lease).
Payout **creation** uses the single-transaction model above — the payout, journal,
ledger projection, and idempotency completion commit or roll back together, with
no separate lease. Do not apply lease-recovery to the single-transaction creation
path.

### 11.2 Concurrency

- Ride/offer transitions pass `version`; a stale `version` returns `409 CONFLICT`
  with the current `version`.
- Offer acceptance and payout requests use the atomic transactions defined in
  `KEKE_DATABASE_DESIGN.md` (§5.4 acceptance; §9 wallet writer).

### 11.3 Payment idempotency model (OPEN)

Two idempotency mechanisms exist and must not disagree:

1. **Generic request idempotency** — the `idempotency_keys` table
   (`KEKE_DATABASE_DESIGN.md` §8.3), keyed `UNIQUE (principal_id, operation,
   key_hash)`, is the **authoritative** request-level deduplication mechanism for the
   mutating endpoints listed in §11.1, including `POST /payments`.
2. **Payment-domain idempotency key** — `payments.idempotency_key`
   (`KEKE_DATABASE_DESIGN.md` §8) is a `TEXT NOT NULL UNIQUE` column on the payment
   row. It records the client-supplied key value for provider correlation and acts
   as a second, payment-specific uniqueness guard.

**Proposed precedence (OPEN, not yet approved):** the generic `idempotency_keys`
record is authoritative for deciding *whether the request executes* (replay vs. new
side effect); `payments.idempotency_key` remains a per-row uniqueness backstop and
audit/correlation field. Because the two can disagree (the generic table hashes the
key; the payment column stores the raw key, globally unique rather than
principal+operation scoped), the design must either (a) keep both with the generic
table as sole authority and document the payment column as a derived backstop, or
(b) retire `payments.idempotency_key` in favor of the generic table. **No existing
constraint is removed without documenting the reason and migration implications.**
The final model is **OPEN** (Index §6).

---

## 12. Persistence mapping and gaps

Every endpoint family maps to a database entity (or an explicitly documented
service-owned resource). An entity's presence in the architecture ownership map or
the ER diagram does **not**, by itself, provide persistence — a `CREATE TABLE`
must exist. The following entities are **referenced** but their **DDL is not yet
present in `KEKE_DATABASE_DESIGN.md`**; they are implementation prerequisites, not
silently assumed:

| Entity | Needed for | Status |
|---|---|---|
| `auth_sessions` | refresh tokens, rotation, reuse detection | DDL pending |
| `otp_codes` | OTP request/verify | DDL pending |
| `notification_tokens` | device token registration | DDL pending |
| `notifications` | push/in-app notification records | DDL pending |
| `support_tickets` / `support_messages` | passenger + admin support | DDL pending |
| `ride_categories` | multi-category model | not needed for MVP (single `"KEKE"`) |
| `fare_rules` | pricing (fares per category/zone) | DDL pending (proposed schema, DB §6.5) |
| `surge_multipliers` | surge pricing | DDL pending (proposed schema, DB §6.5) |
| `admin_actions` | admin decision audit trail | DDL pending (proposed schema, DB §6.6) |

All financial operations remain server-authoritative; no client computes fares,
balances, or ledger entries.

---

## 13. Open questions

1. **MoMo pre-auth UX** — pre-authorize at request vs capture at completion;
   pending provider sandbox behavior (see payment doc).
2. **Pickup-code channel** — PIN in-app vs SMS; pending Kumasi driver-phone
   assessment.
3. **External navigation handoff** — deep-link schemes for Google Maps/OSM (driver).
4. **Payout destination types** — MVP is `MOBILE_MONEY` only; bank-account payout
   is a future decision.
5. **`ride_categories`** — whether to add a category table before multi-category
   support (MVP uses the single `"KEKE"` category).
6. **Cancellation-fee amounts and grace windows** — business policy, unresolved.
