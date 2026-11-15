# KEKE — Blueprint Index

**Milestone 1 — Engineering Blueprint** for KEKE (tricycle ride-hailing, Kumasi,
Ghana). This index lists all generated documents, their purpose, and the shared
canonical vocabulary that keeps them consistent.

---

## 1. Document list

| # | Document | Purpose |
|---|---|---|
| 1 | `KEKE_SYSTEM_ARCHITECTURE.md` | System context, components, technology choices (with trade-offs), service boundaries, data flow, security, deployment. **Read first.** |
| 2 | `KEKE_DATABASE_DESIGN.md` | Entities, canonical enums, PostgreSQL+PostGIS DDL, indexing, financial ledger, audit logging. |
| 3 | `KEKE_API_SPECIFICATION.md` | Auth, passenger/driver/ride/dispatch/location/payment/admin endpoints, request/response examples, error handling, WebSocket contract. |
| 4 | `KEKE_DISPATCH_ENGINE.md` | Driver eligibility, nearby discovery, ranking, offer delivery, timeouts, rejection/reassignment, race handling, fairness. |
| 5 | `KEKE_RIDE_LIFECYCLE.md` | Ride state machine, transitions, pickup code, trip start/completion, cancellation, network-failure recovery. |
| 6 | `KEKE_PAYMENT_AND_WALLET.md` | Cash + Mobile Money, provider abstraction, webhook verification, idempotency, earnings/commission, double-entry ledger, payouts, reconciliation. |
| 7 | `KEKE_MOBILE_APPLICATIONS.md` | Passenger + driver features, maps/navigation, location permissions, background location, notifications, auth, offline behavior. |
| 8 | `KEKE_ADMIN_DASHBOARD.md` | Driver/vehicle approval, passenger management, live monitoring, pricing, settlements, disputes, analytics, audit. |
| 9 | `KEKE_IMPLEMENTATION_ROADMAP.md` | Phases, dependencies, deliverables, testing, deployment, MVP definition, future enhancements. |

---

## 2. Canonical shared vocabulary

Single source of truth: `KEKE_DATABASE_DESIGN.md` §2. Key values referenced
across documents:

- **Ride status:** `REQUESTED → SEARCHING → ACCEPTED → DRIVER_EN_ROUTE →
  DRIVER_ARRIVED → IN_TRIP → COMPLETED`, terminal `CANCELLED`.
- **Offer status:** `PENDING → ACCEPTED | REJECTED | EXPIRED | WITHDRAWN`.
- **Payment method:** `CASH | MOBILE_MONEY`.
- **Payout status:** `PENDING → PROCESSING → COMPLETED | REJECTED`.
- **Ledger account types:** `DRIVER_WALLET`, `COMPANY_COMMISSION`,
  `MOMO_CLEARING`, `CASH_CLEARING`. A dedicated **Promotions/Bonuses** account is
  **CONFIRMED** (Phase 5B) but not yet implemented in SQL.
- **Auth roles:** `passenger | driver | admin`.

Money is expressed in integer **pesewas** over the API and `NUMERIC(12,2)` GHS in
the DB. Coordinates are WGS84 `{lat, lng}`. Timestamps are ISO-8601 UTC.

---

## 3. Evidence discipline (applies to every document)

- **VERIFIED** = observed in Bolt artifacts; **INFERRED** = deduced from shape;
  **UNKNOWN** = not resolvable; **KEKE (proposed)** = our design.
- Bolt backend behavior (dispatch algorithm, fares, state transitions, money) is
  **not** observable and is **never** reconstructed as fact.
- No Bolt branding, assets, or source are reused.

---

## 4. Key architectural decisions (summary)

| Decision | Choice | Rationale (see doc) |
|---|---|---|
| Mobile | React Native + TypeScript (bare) | one codebase, faster delivery; native modules for driver background location |
| Admin | Next.js + TypeScript | SSR, shared TS/React toolchain |
| Backend | NestJS + TypeScript | modules/DI/guards/gateway mirror the discipline Bolt uses |
| DB | PostgreSQL + PostGIS | ACID + geospatial |
| Cache | Redis | live GEO + dispatch leases + idempotency |
| Realtime | WebSocket (primary) + FCM (background) + polling (fallback) | low-latency stateful coordination |
| Storage | S3-compatible | verification docs |
| Money | Hubtel first (Paystack alternate) behind abstraction | Ghana MoMo coverage |
| Authority | Server-authoritative state + money; thin clients | Bolt's backend-driven-UI pattern |

---

## 5. Consistency check (recorded at generation)

- Ride/offer status, payment/payout status, ledger accounts, roles, and
  money-units are identical across documents 2–6.
- Every API endpoint in doc 3 maps to tables in doc 2 and a state transition in
  docs 4–5.
- The dispatch single-winner invariant (doc 4 §8) is backed by the partial unique
  index (doc 2 §5.2) and tested in the roadmap (doc 9 §5).
- Open decisions are listed consistently in doc 1 §11, doc 9 §7, and each
  domain doc's "Open questions".

---

## 6. Open decisions (not silently resolved)

1. MoMo provider (Hubtel vs Paystack) — sandbox evaluation at P5.
2. Navigation engine (MapLibre Navigation vs Ferrostar) — spike at P3.
3. SMS provider — evaluation at P1.
4. Commission rate — business decision (placeholder 20%).
5. Kumasi zone polygon source/maintenance — ops at P3.
6. Cloud/hosting region — P0.
7. MoMo pre-auth vs capture-at-completion — provider capability.
8. Cancellation-fee amounts/grace windows — pricing config.
9. Raw request-byte capture capability (webhook handler) — UNKNOWN.
10. Raw evidence retention period.
11. `keke_audit` role and exact column-level grants.
12. `PX001` SQLSTATE adoption (function-body edit authorization).
13. Exact reconciliation findings + resolution-history DDL.
14. Maximum outbox retry count and backoff configuration.
15. Provider payout statement/report capability — UNKNOWN.
16. Provider idempotency-key fallback for `payout.submit`.
17. Reconciliation schedule and aging threshold (proposed 24h).
18. FINANCE approval / dual-control policy — **CONFIRMED** (auto-reverse on verified definitive failure; no `REVIEW_REQUIRED` dual-control).
19. `processing_started_at` schema adoption and historical backfill.
20. `dedup_key` schema adoption (outbox dedup).
21. `outbox_requeue()` function and its authorized recovery role.
22. `ride.accepted` notification consumer and its idempotency.
23. `keke_reconciliation` role and exact grants.
24. FAILURE callback review/reversal policy — **CONFIRMED** (auto-reverse only on verified definitive provider failure).
25. Controlled outbox producer / enqueue mechanism (no unrestricted `INSERT`).
26. Pending wallet balance accounting model (`pending_pesewas` source).
27. Audit-log database permission model (`keke_audit_writer` / `audit.append_log`) — **CONFIRMED** architecture; exact `audit.append_log` signature + identity-trust model + grants remain OPEN.
28. `fare_rules` and `surge_multipliers` persistence decision.
29. `admin_actions` persistence decision.
30. Payment idempotency model (`payments.idempotency_key` vs `idempotency_keys`).
31. Reconciliation DDL ownership (canonical location).
32. Promotions/Bonuses `account_type` value and schema change (**CONFIRMED**, not yet implemented; exact value OPEN).
33. Refund counterpart credit account + insufficient-driver-balance recovery mechanism.
34. Audit failed-attempt out-of-band security-audit mechanism + identity-trust model.
35. Reconciliation automated-check cadence/interval.
36. Scoped journal-writer role-invocation matrix (which role calls which scoped writer).

---

## 7. How to use this blueprint

1. Read document 1 (architecture) for the whole-system picture and decisions.
2. Docs 2–6 specify the backend contract; docs 7–8 specify the clients.
3. Doc 9 sequences the build.
4. Any implementation that deviates from a stated decision must update the
   affected document(s) and this index (the blueprint is a living artifact, but
   Milestone 1 freezes the baseline).
