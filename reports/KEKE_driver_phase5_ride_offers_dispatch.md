# BOLT Driver — Phase 5: Ride Offers & Dispatch Analysis

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`
**Tooling:** REA MCP + JADX headless 0.7.1 (`get_class_summary` + class search + sub-agent extraction of large dumps).
**Scope:** Read-only static analysis. No APK modification, no runtime, **no credential/data extraction**.

Confidence labels:
- **VERIFIED** — directly observed in JADX metadata (class/field/method/enum names).
- **INFERRED** — deduced from dependency types/module naming; not proven by method bodies.
- **UNKNOWN** — not resolvable (obfuscation / backend-only).

**Central finding:** The driver order/dispatch subsystem is **backend-driven**. The offer screen and the FIFO queue are rendered from server-provided models (`IncomingOrderResponse`, `FifoQueueState*`), and the client only *renders* them and *submits* accept/reject state changes. The matching algorithm itself is **not** present in the APK and is **not** claimed.

---

## 1. Ride Offer Receiving

### 1.1 Entry points (VERIFIED)
- `ee.mtakso.driver.ui.screens.order.incoming.v2.IncomingOrderActivity` (manifest activity) — the incoming-offer screen.
- `ee.mtakso.driver.ui.screens.order.incoming.v2.IncomingOrderRoute` — RIB route for the offer flow.

### 1.2 Push notification handlers (VERIFIED)
- `ee.mtakso.driver.platform.google.push.FirebasePushService` + `FirebaseMessagingService` / `FirebaseInstanceIdReceiver` (Phase 2) — FCM push. Incoming-offer pushes are **INFERRED** to route here (the push→offer wiring is obfuscated).

### 1.3 Polling mechanisms (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.polling.*` (`a`–`d`) — polling transport module.
- `ee.mtakso.driver.service.pollerv2.b` — a **polling v2** dependency of `OrderStateManager` (VERIFIED field type).
- **INFERRED**: offer/queue state is synchronized via FCM (realtime triggers) **and** polling (pollerv2) as fallback/steady-state.

### 1.4 Dispatch queue interaction (VERIFIED — via `OrderStateManager` wiring)
- `OrderStateManager` holds `OrderProvider` + `OrdersCache` + `service.pollerv2.b` + `service.geo.transmitter.g` — the manager consumes offers from the order provider/cache and the polling/geo transports.

---

## 2. Ride Offer Presentation

### 2.1 Backend-driven UI (VERIFIED)
The offer screen is rendered from server-provided models in `ee.mtakso.driver.network.client.order.*`:
- `IncomingOrderResponse` — the offer payload.
- `IncomingOrderButton`, `IncomingOrderFooter` — server-defined action buttons/footer.
- `Label`, `LabelSeverity` — labeled UI rows with severity.
- `OptionalRideInfo` — optional info rows.
- `RideDetailChip`, `RideDetailInfoBlock`, `RideDetailLabel`, `RideDetailLabelTypeInfo` — the "ride detail" info blocks.

### 2.2 Passenger / pickup / destination info (VERIFIED — model presence)
- `OrderMapPoint`, `OrderStop`, `UpcomingStop`, `StopType`, `StopSummary`, `RideDetailRoutePoint` — route/stop/point models.
- `PassengerMarking` — passenger marking (used by `OrderStateManager.D1(...PassengerMarking)`).
- `DriverPickupSafetyData` — pickup safety data.
- Specific passenger name/phone/ETA fields are carried by the server-driven `IncomingOrderResponse` labels; exact fields **UNKNOWN** (obfuscated inner models).

### 2.3 Distance / ETA / fare (VERIFIED — presence; specifics UNKNOWN)
- `Price`, `PriceReviewInfo`, `PriceReviewState`, `PriceCalculationItem`, `PriceCalculationForRouteChangeConfirmationRequest/Response`, `DriverOrderPaymentDetails`, `PaymentType` — fare/earnings models.
- Distance/ETA are presented via `RideDetailInfoBlock`/`OptionalRideInfo` (server-provided strings); the numeric field mapping is **UNKNOWN**.

### 2.4 Offer countdown / expiration (VERIFIED — presence)
- `FifoQueueButtonWithTimeout`, `DriverCategoryQueueStateWithWaitingTime`, `StopTimerResponse` — timeout/waiting-time models. A dedicated "offer countdown" timer is **INFERRED** (not a distinct class); `OrderStateManager.t0(long, order.details.j)` (timer) and `U0(StopTimerResponse)` support timing.

---

## 3. Accepting a Ride

### 3.1 Accept action (VERIFIED)
- `OrderStateChangeType.ACCEPT` (enum constant) — the accept transition type.
- `OrderStateManager` executes state changes via generic executors: `n2(OrderStateChangeType, …)`, `w1(...)`, `m1(...)`, `y1(...)`, `o2(...)`, `Z0(...)` (all take `OrderStateChangeType`).

### 3.2 Accept API models (VERIFIED)
- `AcceptScheduledRideResponse`, `AcceptedScheduledRides` (scheduled-ride accept).
- `AcceptanceBlockAppearance` — acceptance-block UI.
- `AcknowledgeRiderConfirmationRequest`, `RiderConfirmationDialog`, `RiderConfirmationStatus`, `OrderConfirmationState` (confirmation sub-package) — rider confirmation after accept.

### 3.3 Error handling (VERIFIED)
- `AcceptOrderNotFoundAlertingException` — accept fails when the order is already gone/assigned.
- `OrderStateManager` error handlers: `A0/C/C0/w0/W/z0/u0/B0/k1/h2/O0/P0/r1` (typed `Throwable` handling per state change).

### 3.4 Loading/confirmation states (INFERRED)
- `OrderStateManager.s = MutableStateFlow<order.v2.m>` and `r = subjects.e<…m0>` expose reactive state; loading/confirmation UI is driven by these flows. Exact state values **UNKNOWN** (obfuscated `m`/`m0`).

---

## 4. Rejecting or Ignoring a Ride

### 4.1 Reject action (VERIFIED)
- `OrderStateManager.A(…RejectReasonInfo, order.details.j)` — reject with reason.
- `N0(RejectOrderResponse)`, `S(...RejectOrderResponse)` — reject response handling.
- `RejectOrderRequest`, `RejectOrderResponse`, `RejectReason`, `RejectReasonInfo`, `RejectResponseType` — reject API models.

### 4.2 Expiration / timeout (VERIFIED — model presence)
- `FifoQueueButtonWithTimeout`, `StopTimerResponse`, `DriverCategoryQueueStateWithWaitingTime`; `OrderStateManager.t0(long, …)` (timer) — offer/queue timeout handling.

### 4.3 Cancellation & dismissal (VERIFIED)
- `OrderStateChangeType.CANCEL_CURRENT_ORDER`, `CANCEL_NEXT_ORDER`, `DECLINE_ARRIVAL` — cancellation/decline transitions.
- `OrderStateManager.f2(CancellationReason)`, `g2(...CancellationReason...)` — cancellation with reason.
- `CancelOrderCreationBody`, `CancellationConfirmationScreen` — cancellation confirmation UI.

### 4.4 Availability changes after rejection (INFERRED)
- Rejecting/ignoring changes order state (`CANCEL_*`) which (via `DriverOnlineStatus`/`GoOnlineFlowResult`, Phase 4) may return the driver to the available/searching state. Exact linkage **UNKNOWN** (obfuscated).

---

## 5. Dispatch Queue (FIFO)

### 5.1 `fifo.*` classes (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.fifo.*` (obfuscated `a`–`d`, `a1`–`d1`, `k`, `l`, `m`, `y0`, `z0`).

### 5.2 FIFO role from models (VERIFIED — backend queue state, not local ordering)
The network models reveal FIFO is the **server-side dispatch queue** the client renders/polls:
- `FifoDispatchingState`, `FifoQueueDispatchAreaState`, `FifoQueueInfoCard`, `FifoQueueTextAppearance`, `FifoQueueButtonWithTimeout`.
- `FifoQueueStateForDriverRequest` / `FifoQueueStateForDriverResponse` — driver's own queue state (request/response).
- `FifoQueueStateRequest` / `FifoQueueStateResponse`, `GetFifoQueueStateResponse`, `GetFifoQueueStateForAreaResponse`, `GetFifoQueueStateForDispatchingResponse`.
- `DriverCategoryQueueStateWithWaitingTime` — per-category queue + waiting time.
- `CounterOffer`, `DriverCounterOfferOptions` — driver counter-offers (driver-side price bidding).

**Conclusion (VERIFIED):** FIFO represents the backend's first-in-first-out **dispatch queue** (a driver joins/waits in a queue for their next offer). It is **not** a local ordering structure and **not** the matching algorithm. The client `fifo.*` module renders the server `FifoQueueState*` and lets the driver join/leave the queue (with timeout/waiting-time UI). The actual queue/matching logic is server-side (UNKNOWN).

### 5.3 Callers/references (VERIFIED — via `OrderStateManager`)
- `OrderStateManager` integrates `OrderProvider`, `OrdersCache`, `pollerv2.b`, `geo.transmitter.g` — the queue state flows in through the order provider/polling and is rendered by the `fifo` UI module.

---

## 6. Order Assignment

### 6.1 `OrderStateManager` (VERIFIED — structure)
- 22 fields, 177 methods, 33 inner classes (obfuscated).
- Key dependencies (field types): `OrderProvider`, `OrdersCache`, `service.pollerv2.b`, `service.geo.transmitter.g`, `DriverDestinationsManager`, `automatic_arrival.a`, `DeviceSettings`, `DriverFeatures`, RxJava subjects, `MutableStateFlow<order.v2.m>`.
- Reactive state: `r = subjects.e<…m0>` (state-change subject), `s = MutableStateFlow<…m>` (current state); flows `a2()`, `b2()`, `Z1(): StateFlow<m>`.
- State-change execution: `n2/w1/m1/y1/o2/Z0/x1/z1/A1/B1` all keyed on `OrderStateChangeType`.
- Order operations referencing `ActiveOrderDetails`/`OrderHandle`/`order.details.j`: accept, reject, confirm-arrival, finish, change destination, price review, cancellation.

### 6.2 `OrderStateChangeType` (VERIFIED — full enum, readable)
`ACCEPT`, `BEFORE_FINISH_ORDER`, `CANCEL_CURRENT_ORDER`, `CANCEL_NEXT_ORDER`, `CHANGE_DESTINATION`, `CONFIRM_ARRIVAL`, `DECLINE_ARRIVAL`, `DEFAULT`, `FINISH_PARCEL_ORDER`, `SWITCH_STOP`.

This is the driver-side order **transition vocabulary** (10 states/actions). It directly maps the ride lifecycle actions the driver can take.

### 6.3 `OrderTracker` (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.order.v2.OrderTracker` (readable class) — order tracking alongside `OrderStateManager`.

### 6.4 Assignment confirmation / duplicate-conflict handling (VERIFIED — presence)
- `AcceptOrderNotFoundAlertingException` (order already gone).
- `AcceptedScheduledRides` (list of accepted), `GetSubstituteDriversRequest/Response`, `SubstituteDriverOrderRequest` (substitute driver) — conflict/substitution.
- Exact duplicate-offer dedup logic **UNKNOWN** (obfuscated within `OrdersCache`/`OrderStateManager`).

### 6.5 State transitions after acceptance (VERIFIED — type level)
- After `ACCEPT`, the manager transitions the order through `CONFIRM_ARRIVAL`, `CHANGE_DESTINATION`, `SWITCH_STOP`, `BEFORE_FINISH_ORDER`, `FINISH_PARCEL_ORDER` etc. (enum-driven). Specific transition function bodies **UNKNOWN**.

---

## 7. Real-Time Communication

### 7.1 FCM + polling (VERIFIED)
- FCM: `FirebasePushService`/`FirebaseMessagingService`.
- Polling: `service.modules.polling.*` + `service.pollerv2.b` (field of `OrderStateManager`).

### 7.2 Retry / synchronization (INFERRED)
- `OrderStateManager` has extensive per-`OrderStateChangeType` error handlers (`A0/C/C0/w0/u0/B0/k1/h2/…`) → retry-on-failure for state changes is INFERRED (not proven).

### 7.3 Connectivity loss (UNKNOWN)
- No readable offline/retry policy class surfaced. `OrderStateManager` error paths + polling imply graceful degradation, but specific offline behaviour is UNKNOWN.

### 7.4 Client vs backend (VERIFIED boundary)
- **Client:** renders `IncomingOrderResponse`/`FifoQueueState*`, submits accept/reject/cancel/change-destination state changes, tracks order state.
- **Backend (not observable):** who receives which offer, FIFO ordering, waiting-time computation, substitution, counter-offer evaluation.

---

## 8. Passenger–Driver Matching Boundary (explicit)

### 8.1 What the driver client receives (VERIFIED — models)
- Offer: `IncomingOrderResponse` (+ buttons/footer/labels/ride-details).
- Queue: `FifoQueueStateForDriverResponse`, `GetFifoQueueStateForDispatchingResponse`, `DriverCategoryQueueStateWithWaitingTime`, `FifoDispatchingState`.
- Order: `Order`, `ActiveOrderDetails`, `OrderMapPoint`, `OrderStop`, `PriceReviewInfo`, `DriverPickupSafetyData`.
- Substitution: `GetSubstituteDriversResponse`, `ScheduledRideDetails`.

### 8.2 What the driver client sends back (VERIFIED — models)
- `RejectOrderRequest` (with `RejectReason`), accept (`OrderStateChangeType.ACCEPT`), `CancelOrderCreationBody`, `ChangeRouteRequest`, `SetDestinationRequest`, `StopRequest`, `FinalizeOrderRequest`, `ReportBadPickUpRequest`, `ReportMapIssueRequest`, `RateClientRequest`, `PriceReviewRequest`, `AcknowledgeRiderConfirmationRequest`, `GetSubstituteDriversRequest`, `FifoQueueStateForDriverRequest`.

### 8.3 What remains server-side (UNKNOWN — not in APK)
- The matching/dispatch algorithm (which driver receives an offer), FIFO queue ordering, surge/pricing decisions, offer expiration policy, counter-offer acceptance, and all passenger-side state. None is present in the APK and none is claimed.

---

## 9. Unresolved Questions (for Phase 6)

1. **Offer model internals:** exact fields of `IncomingOrderResponse` (passenger name/phone, pickup/destination addresses, ETA, fare, countdown seconds) — decompile the class.
2. **Push→offer wiring:** which FCM handler delivers `IncomingOrderResponse` to `IncomingOrderActivity` (obfuscated `fcm.handlers`/`FirebasePushService`).
3. **Accept/reject endpoints:** the concrete Retrofit interface behind `network.client.order.n2`/`w1` — endpoint paths and HTTP methods.
4. **FIFO semantics:** does the driver "join/leave" the queue explicitly (`FifoQueueStateForDriverRequest`), and what triggers offer delivery from the queue?
5. **State machine values:** `OrderStateManager.s` (`MutableStateFlow<m>`) and `r` (`subjects.e<m0>`) — decompile `m`/`m0` to enumerate order states.
6. **Countdown/expiration:** where the offer/queue timeout is enforced (client timer `t0(long,…)` vs server).
7. **Retry policy:** whether failed accept/reject is auto-retried (pollerv2) or surfaced to the driver.
8. **Connectivity loss:** offline handling of queue/offer state.

---

## 10. Limitations

1. Heavy obfuscation — `OrderStateManager` (177 methods, all single-letter) and `fifo.*`/`polling.*`/`reporters.*` internals are unreadable; only type/enum/package names are reliable.
2. No runtime/network capture; transport and retry behaviour are inferred, not observed.
3. No credentials/tokens/personal data extracted.
4. Split APKs not decompiled this phase.
5. Backend matching/dispatch logic is explicitly out of scope (not observable, not claimed).
