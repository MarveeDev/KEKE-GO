# KEKE — Phase 5A: Financial Security & Policy Design Review

**Status:** Technical decision document (read-only design; no implementation).
**Scope:** the three highest-priority production blockers identified in Phase 4C.
**Classification labels:** `VERIFIED` (in shipped SQL/runtime evidence), `PROPOSED`
(recommended design), `OPEN` (requires explicit business decision), `UNKNOWN`
(insufficient evidence).

---

## 1. Executive Summary

The SQL migrations (V001–V013) are correct and the financial core is runtime-validated,
but three decisions gate production readiness:

1. **Journal posting authorization** — `wallet.append_journal_entry()` is currently
   executable by `keke_app` with any of the six entry types against any existing account
   (balanced). This permits arbitrary money minting. Fix: revoke direct `EXECUTE`, keep the
   primitive internal, and expose narrowly scoped SECURITY DEFINER writers per operation.
2. **Audit enforcement** — `audit_logs` has no database-level writer protection. Fix: a
   dedicated `keke_audit_writer` owner + `audit.append_log()` SECURITY DEFINER writer.
3. **Payment failure/callback policy** — a `FAILURE` callback must not blindly reverse every
   transaction; collection vs disbursement vs reservation vs settlement need distinct rules.
   The FAILURE review-gating question is now **CONFIRMED** (auto-reverse only on verified
   definitive provider failure; see §1A).

All three are design decisions, not SQL defects. This document recommends an architecture
and lists the exact business decisions a human must approve before implementation.

---

## 1A. Phase 5B Confirmed Decisions (CONFIRMED)

The following eight business decisions were confirmed in Phase 5B and are **not** to be
changed. Each is recorded here with its required schema/architecture consequence; where a
schema change is required it is `CONFIRMED but not yet implemented` (no SQL has been added).

| # | Decision | Status | Required change |
|---|---|---|---|
| 1 | **Driver bonus funding** uses a dedicated Promotions/Bonuses account; promotional expenditure must be distinguishable from commission revenue. | **CONFIRMED** | New `ledger_accounts.account_type` value (`PROMOTIONS`/`BONUSES`) — **not yet in SQL** (CHECK + migration). |
| 2 | **Refund funding:** the driver bears the full cost of an approved passenger refund. Insufficient driver balance handling is **OPEN** (do not silently permit negative balances). | **CONFIRMED** | `REFUND` debits `DRIVER_WALLET`; counterpart credit account is **OPEN**; insufficient-balance recovery is an unresolved implementation requirement. |
| 3 | **Commission accounting:** record KEKE commission directly as company revenue in `COMPANY_COMMISSION`; keep cash settlement and clearing movements separately traceable. | **CONFIRMED** | `RIDE_FARE`/`COMMISSION` credit `COMPANY_COMMISSION`; `CASH_CLEARING`/`MOMO_CLEARING` remain distinct. |
| 4 | **Journal writer authorization:** dedicated backend services only; `keke_app` may invoke narrowly scoped, approved operations; outbox workers, reconciliation services and administrators must not have arbitrary journal-writing access; the general `append_journal_entry` must not be executable by untrusted application roles. | **CONFIRMED** | Option A (dedicated backend services; revoke `append_journal_entry` from untrusted roles; add scoped writers). |
| 5 | **Audit coverage:** audit all sensitive financial, payment, ride, driver-verification and administrative actions; capture actor, action, entity, timestamp, correlation ID, before/after; protect PII. | **CONFIRMED** | `audit.append_log()` writer + audited-action matrix. |
| 6 | **Audit survival:** successful-operation audit records may be transactional; failed/rolled-back sensitive attempts must be preserved via an independent durable security-audit mechanism; ordinary roles must not alter/delete audit records. | **CONFIRMED** | Same-transaction audit for success + out-of-band mechanism for failed attempts (**mechanism OPEN**). |
| 7 | **Failed payout policy:** auto-reverse a reserved payout only after a verified, definitive provider failure (verify signature, reference, amount); idempotent reversal exactly once; timeouts/uncertain remain pending for reconciliation; preserve evidence. | **CONFIRMED** | `fail_payout()` auto-reverse on verified definitive failure; no `REVIEW_REQUIRED` dual-control. |
| 8 | **Reconciliation:** frequent automated checks plus a complete daily reconciliation; detect missing/duplicated/delayed/mismatched; escalate unresolved; cadence configurable (**exact interval OPEN**). | **CONFIRMED** | Automated + daily reconciliation; cadence configuration. |

---

## 2. Current Implementation & Evidence

### 2.1 Journal writer (`VERIFIED`)

- `wallet.append_journal_entry(TEXT, TEXT, TEXT, JSONB) RETURNS uuid` — `SECURITY DEFINER`,
  `SET search_path = pg_catalog, wallet`, owned by `keke_wallet`, `EXECUTE` granted to
  `keke_app` (V012). Accepts arbitrary balanced `p_lines` against any existing
  `ledger_accounts` (`V009` + `V012` runtime evidence).
- Entry types (`CHECK` on `journal_entries.entry_type`): `RIDE_FARE`, `COMMISSION`,
  `PAYOUT`, `REFUND`, `ADJUSTMENT`, `BONUS` (`V009`).
- Account types (`CHECK` on `ledger_accounts.account_type`): `DRIVER_WALLET`,
  `COMPANY_COMMISSION`, `MOMO_CLEARING`, `CASH_CLEARING` (`V009`).
- The payout writers (`request_payout`, `reject_payout`, `fail_payout`) inline their own
  journal writes and do **not** call `append_journal_entry` (`V012`; confirmed by
  decompiled bodies and Batch 3 runtime tests).
- `keke_app` holds `SELECT` on all four ledger tables and `EXECUTE` on the seven writers,
  but no `INSERT/UPDATE/DELETE` on ledger tables (Batch 5 PR2/PR4 evidence).

### 2.2 Audit (`VERIFIED` / `PROPOSED`)

- `audit_logs` columns: `id BIGSERIAL PK`, `actor_user_id UUID` (nullable), `actor_role TEXT`,
  `action TEXT NOT NULL`, `entity_type TEXT NOT NULL`, `entity_id TEXT NOT NULL`,
  `before JSONB`, `after JSONB`, `ip_address INET`, `correlation_id TEXT`, `created_at`
  (`V011`; `KEKE_DATABASE_DESIGN.md` §11).
- No owner transfer, no writer role, no writer function, no grants (`V011` scope). The
  "Audit module sole writer" is an **application-layer convention** only (`VERIFIED` gap).
- `PROPOSED` (DB §11.1): `keke_audit_writer` NOLOGIN owner + `audit.append_log(...)`
  SECURITY DEFINER writer; raw-evidence reader `keke_audit` is a separate concern.

### 2.3 Payment/payout callbacks (`VERIFIED` / `OPEN`)

- `payment_events` (immutable log) with partial unique `(provider, provider_event_id)`
  (`V007`); `payout_events` with `event_type ∈ {SUCCESS, FAILURE, UNKNOWN}` and
  `UNIQUE(provider, provider_event_id)` (`V008`).
- `payments.status ∈ {PENDING, AUTHORIZED, CAPTURED, FAILED, REFUNDED, EXPIRED}`;
  `payouts.status ∈ {PENDING, PROCESSING, COMPLETED, REJECTED}` (`V007`/`V008`).
- `fail_payout()` currently reverses on a definitive `FAILURE` (`PROCESSING → REJECTED` +
  `:reversal`) — the "auto-reverse" default (`V012`; Batch 3 LC4).
- `REVIEW_REQUIRED` review-gated alternative was `PROPOSED/OPEN` and is now **superseded**
  by the Phase 5B CONFIRMED auto-reverse policy (§1A); not implemented.

---

## 3. Security Threat Analysis

### 3.1 Journal authorization

- **Threat A (money minting):** a compromised `keke_app` (or buggy internal caller) posts
  `REFUND`/`ADJUSTMENT`/`BONUS` crediting a `DRIVER_WALLET` from `COMPANY_COMMISSION`/clearing,
  creating value with no underlying ride/payment. `VERIFIED` possible today.
- **Threat B (payout-flow bypass):** direct `PAYOUT` entry, bypassing `request_payout`'s
  destination/balance guards.
- **Threat C (clearing drift):** arbitrary clearing-account movements to mask reconciliation
  discrepancies.

### 3.2 Audit

- **Threat D (unaudited mutation):** application services can write `audit_logs` directly or
  (worse) a compromised role can `UPDATE`/`DELETE` audit rows (append-only is not DB-enforced).
- **Threat E (evidence tampering):** without a SECURITY DEFINER writer, no guarantee that
  actor/action/before/after are written atomically with the mutation.

### 3.3 Callback/failure

- **Threat F (double reversal):** replayed `FAILURE` callback → second `:reversal`.
- **Threat G (wrong auto-reversal):** a `FAILURE` on a *collection* (passenger paid) must not
  reverse a *disbursement* reservation; auto-reversal without context is dangerous.
- **Threat H (unknown-outcome reversal):** treating a timeout as failure and reversing.

---

## 4. Options & Trade-offs — Decision 1 (Journal Authorization)

### Option A (CONFIRMED) — Dedicated backend services only

Only dedicated backend services post journal entries, through narrowly scoped, approved
financial operations. `keke_app` may invoke only these scoped SECURITY DEFINER writers.
Outbox workers, reconciliation services and administrators have **no** arbitrary
journal-writing access. The general-purpose `append_journal_entry` is **not executable** by
untrusted application roles (it becomes internal to `keke_wallet`-owned writers).

- **Security:** application cannot mint money; the primitive is out of reach; each operation
  encodes its permitted accounts/direction.
- **Complexity:** moderate (scoped functions + revoke).
- **Payout compatibility:** payout writers already separate; unchanged.
- **Auditability:** strongest (function name = operation; correlation IDs enforced inside).
- **Migration impact:** `REVOKE EXECUTE … FROM keke_app` on `append_journal_entry` + new
  scoped functions + `GRANT EXECUTE` to `keke_app`.
- **Testing:** per-operation positive/negative + a regression proving `append_journal_entry`
  is no longer `keke_app`-callable.

### Option B — In-writer allowlist (evaluated, not chosen)

Keep `append_journal_entry` executable; add a `(entry_type, account_type[])` allowlist.

- **Security:** centralized; blocks invalid pairs at a choke point.
- **Complexity:** low (one validation table/array + check).
- **Payout compatibility:** payout writers don't call it, so unaffected.
- **Auditability:** good (rejections logged by the writer itself).
- **Migration impact:** allowlist config; no signature change.
- **Testing:** positive/negative pair matrices.
- **Weakness:** an allowlist of *pairs* still allows an `ADJUSTMENT` credit to any
  `DRIVER_WALLET` (the amount/source legitimacy is still caller-supplied).

### Explicit business decisions — resolution status
1. `ADJUSTMENT` / `BONUS` funding source — **CONFIRMED** (Phase 5B): a dedicated
   Promotions/Bonuses account (new `account_type`; exact value still **OPEN**).
2. `REFUND` account semantics — **CONFIRMED**: the driver bears the full cost
   (debit `DRIVER_WALLET`); the counterpart credit account and insufficient-balance
   recovery remain **OPEN**.
3. `COMMISSION` entry type — **CONFIRMED**: recorded directly as company revenue in
   `COMPANY_COMMISSION`; clearing movements kept separately traceable.
4. Which roles invoke each scoped writer (driver-initiated vs admin-only) — **OPEN**.

---

## 5. Options & Trade-offs — Decision 2 (Audit Enforcement)

### Recommended design (PROPOSED)

- **`keke_audit_writer` (NOLOGIN)** owns `audit_logs` and a SECURITY DEFINER
  `audit.append_log(actor_user_id, actor_role, action, entity_type, entity_id, before,
  after, correlation_id)` with `SET search_path = pg_catalog, wallet`.
- **`keke_app`** gets `EXECUTE` on `audit.append_log` only; **no** `INSERT/UPDATE/DELETE`
  on `audit_logs`. `keke_audit` (evidence reader) stays separate from the writer.
- **Attribution:** `actor_user_id`/`actor_role` resolved from the authenticated principal
  (JWT `sub`/`role`), `correlation_id` carried from the request context.
- **Rollback behavior:** audit rows are written in the **same transaction** as the mutation,
  so a rolled-back mutation also rolls back its audit row (consistent trail). A separate
  "audit of attempted-but-failed" event, if required, is a policy decision (not default).

### Operations to audit (PROPOSED; final scope is a policy decision)
- Payout lifecycle: `process/reject/complete/fail_payout`, `record_provider_ref`.
- Payment: webhook `SUCCESS`/`FAILURE`/amount-mismatch, manual refund/adjustment.
- Ride: acceptance, cancel, completion, rating disputes.
- Driver verification: document approve/reject, vehicle approve/reject/suspend.
- Admin: force-cancel, manual journal adjustments, sensitive personal-data/document views.

### Explicit decisions (OPEN)
1. Exact audited action list per module — **OPEN**.
2. Whether audit must survive transaction rollback (autonomous/out-of-band) — **OPEN**
   (PostgreSQL has no native autonomous transaction; this implies a dedicated worker).
3. `before`/`after` snapshot depth and PII sanitization rules — **OPEN**.

---

## 6. Options & Trade-offs — Decision 3 (Payment Failure & Callback Policy)

### Outcome taxonomy (PROPOSED)
`SUCCESS` (definitive), `FAILURE` (definitive), `PENDING` (unknown/unresolved),
`REVIEW_REQUIRED` (definitive failure awaiting finance approval — dual-control).

### Four distinct money contexts (must not be conflated)
1. **Passenger collection** (`payments`, passenger→KEKE): a `FAILURE` means the charge did
   not settle; release any pre-auth hold; **no wallet credit/debit** (nothing was earned).
2. **Driver disbursement** (`payouts`, KEKE→driver): a `FAILURE` reverses the wallet
   reservation (`PROCESSING → REJECTED` + `:reversal`).
3. **Internal wallet reservation** (`request_payout`): the reservation is already journaled;
   only a definitive failure or admin rejection reverses it.
4. **Provider settlement/reconciliation**: provider-only / KEKE-only / amount-mismatch rows
   are flagged for finance; never auto-posted to the ledger.

### Callback rules (PROPOSED)
- **Duplicate callback:** `payout_events`/`payment_events` unique `(provider,
  provider_event_id)` dedupes; identical → no-op.
- **Out-of-order callback:** `PREMATURE` (arrived while `PENDING`) is classified, retained,
  re-evaluated later; not applied.
- **Invalid signature:** rejected before any state change (`401`/ignored).
- **Provider timeout / no webhook:** `PENDING` (unresolved); **never** treated as failure;
  flagged for reconciliation.
- **Conflicting references:** `PROVIDER_REF_CONFLICT` (never overwritten).
- **Failure after successful reservation (disbursement):** reversal is idempotent
  (`:reversal` correlation + `uq_journal_payout_correlation`).
- **Manual reconciliation:** finance resolves via the existing guarded
  `complete_payout`/`fail_payout`; no new signatures.

### The central decision (CONFIRMED, Phase 5B)
A reserved payout is auto-reversed **only** after a verified, definitive provider failure.
The handler must verify callback authenticity (signature), payout reference and amount, and
enforce idempotency so the reversal happens exactly once. Timeouts and uncertain responses
remain `PENDING` for reconciliation (never auto-reversed); callback and reversal evidence is
preserved. The `REVIEW_REQUIRED` dual-control alternative is **not** the chosen policy.

---

## 7. Recommended Architecture (summary)

1. **Journal:** Option A — dedicated backend services only; `append_journal_entry` becomes
   internal-only (not executable by untrusted roles); add scoped
   `wallet.post_ride_fare / post_refund / post_adjustment / post_bonus` (SECURITY DEFINER,
   `keke_wallet`-owned, `EXECUTE` to `keke_app`), each encoding approved account pairs.
2. **Audit:** `keke_audit_writer` + `audit.append_log()` (SECURITY DEFINER, fixed
   `search_path`, `EXECUTE` to `keke_app`), same-transaction audit writes.
3. **Callbacks:** keep the guarded `complete_payout`/`fail_payout`; add an application-layer
   savepoint classifier (§16.7) that maps `SUCCESS/FAILURE/UNKNOWN/PREMATURE/CONTRADICTORY`
   to dispositions and applies the (to-be-approved) review policy.

---

## 8. Business Decisions

### 8.1 Confirmed (Phase 5B — resolved, do not change)

1. **Driver bonus funding** — dedicated Promotions/Bonuses account (schema not yet implemented).
2. **Refund funding** — driver bears the full cost of an approved passenger refund.
3. **Commission accounting** — KEKE commission recorded directly in `COMPANY_COMMISSION`; clearing kept separately traceable.
4. **Journal writer authorization** — Option A (dedicated backend services; scoped writers; `append_journal_entry` not executable by untrusted roles).
5. **Audit coverage** — all sensitive financial/payment/ride/verification/admin actions with attribution + before/after + PII protection.
6. **Audit survival** — transactional for success; independent durable mechanism for failed/rolled-back attempts.
7. **Payout FAILURE** — auto-reverse only on verified definitive provider failure (idempotent, evidence-preserving).
8. **Reconciliation** — frequent automated checks + complete daily reconciliation; escalate unresolved.

### 8.2 Remaining Open (require explicit approval)

1. Exact Promotions/Bonuses `account_type` value/name (`PROMOTIONS` vs `BONUSES`) and its sign semantics. **OPEN**
2. Refund counterpart credit account (passengers lack ledger accounts) + insufficient-driver-balance recovery mechanism. **OPEN**
3. Scoped-writer role-invocation matrix (which role may call each scoped writer). **OPEN**
4. Audit "failed-attempt" out-of-band mechanism design + identity-trust model. **OPEN** (do not invent)
5. Reconciliation automated-check cadence/interval + `keke_reconciliation` role grants. **OPEN**
6. Remaining carried-forward items: `processing_started_at`, `dedup_key`, `outbox_requeue`, application-table access model, `pending_pesewas`, `fare_rules`/`surge_multipliers`/`admin_actions` persistence.

---

## 9. Proposed Database Changes (design only — not implemented)

1. `REVOKE EXECUTE ON wallet.append_journal_entry(...) FROM keke_app` (make internal).
2. Add scoped SECURITY DEFINER writers (per Decision 1) + `GRANT EXECUTE` to `keke_app`.
3. `ALTER TABLE audit_logs OWNER TO keke_audit_writer` (new NOLOGIN role) +
   `audit.append_log()` + `REVOKE … FROM PUBLIC` + `GRANT EXECUTE` to `keke_app`.
4. (Later, once approved) `payout_events.disposition`, findings/resolution tables,
   `keke_reconciliation` role — per the existing `PROPOSED` §16 design.

---

## 10. Proposed NestJS Service Responsibilities

- **WalletService** calls only scoped writers (never `append_journal_entry` directly).
- **AuditService** is the sole caller of `audit.append_log()`; emits typed audit events.
- **PaymentWebhookService** implements signature verify + savepoint classification + the
  approved FAILURE policy; calls `complete_payout`/`fail_payout`.
- **ReconciliationService** reads evidence and writes findings (no ledger writes).
- **AuthService/Guards** supply `actor_user_id`/`actor_role`/`correlation_id` to audit.

---

## 11. Required Test Cases

1. `keke_app` cannot call `append_journal_entry` (42501) after revoke.
2. Each scoped writer accepts only its approved account pairs (reject others).
3. `audit.append_log` as `keke_app` succeeds; direct `INSERT` into `audit_logs` fails (42501).
4. Duplicate/out-of-order `FAILURE` callback → no second reversal.
5. Collection `FAILURE` does not debit a wallet; disbursement `FAILURE` reverses once.
6. `REVIEW_REQUIRED` path (once approved) blocks auto-reversal until finance approval.
7. Regression: payout state machine + hash chain unchanged after the authorization changes.

---

## 12. Dependency-Ordered Implementation Roadmap

1. Approve business decisions (§8).
2. Implement journal authorization (Decision 1) + tests.
3. Implement audit enforcement (Decision 2) + tests.
4. Implement callback disposition + FAILURE policy (Decision 3) + tests.
5. Reconciliation + roles.
6. Application integration + provider sandbox.

---

## 13. Updated Production Blocker Register

| # | Blocker | Severity | Category | Status |
|---|---|---|---|---|
| 1 | `append_journal_entry` broad authorization | HIGH | Security / Financial | **CONFIRMED** (Option A decided; implementation pending) |
| 2 | Audit-log DB enforcement | HIGH | Security | **CONFIRMED** (`keke_audit_writer` + `audit.append_log`; implementation pending) |
| 3 | Payout FAILURE review/reversal policy | HIGH | Financial | **CONFIRMED** (auto-reverse on verified definitive failure; implementation pending) |
| 4 | Application-level idempotency orchestration | HIGH | Financial | **OPEN** |
| 5 | Reconciliation workflow + role | MEDIUM | Operational | **CONFIRMED** (automated + daily; cadence + `keke_reconciliation` grants **OPEN**) |
| 6 | Promotions/Bonuses `account_type` schema | MEDIUM | Financial / Design | **CONFIRMED** (not yet implemented) |
| 7 | Refund counterpart + insufficient-driver-balance recovery | MEDIUM | Financial / Design | **OPEN** |
| 8 | `payment_events` grants + app-table access model | MEDIUM | Security / Operational | **OPEN** |
| 9 | `pending_pesewas` accounting model | MEDIUM | Design | **OPEN** |
| 10 | `fare_rules`/`surge_multipliers`/`admin_actions` persistence | MEDIUM | Design | **OPEN** |
| 11 | Audit failed-attempt out-of-band mechanism | MEDIUM | Security / Design | **OPEN** (do not invent identity-trust) |
| 12 | `published_at` outbox traceability semantics | LOW | Operational | Documented (Batch 4A) |

---

*End of Phase 5A design document. No migrations, records, roles, grants, or functions were
modified; no code was implemented; no production readiness is claimed.*
