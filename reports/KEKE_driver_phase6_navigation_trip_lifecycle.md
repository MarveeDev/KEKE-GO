# BOLT Driver — Phase 6: Navigation & Trip Lifecycle

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`
**Tooling:** REA MCP + JADX headless 0.7.1 (class search + `get_class_summary`).
**Scope:** Read-only static analysis. No APK modification, no runtime, **no credential/data extraction**.

Confidence labels:
- **VERIFIED** — directly observed in JADX metadata (class/field/method/enum names).
- **INFERRED** — deduced from dependency types/naming; not proven by method bodies.
- **UNKNOWN** — not resolvable (obfuscation / backend-only).

---

## 1. Driver Navigation

### 1.1 Mapbox Maps integration (VERIFIED)
- `libmapbox-maps.so`, `libmapbox-common.so` (Phase 1); `com.mapbox.common.location.LocationUpdatesReceiver`, `sdk_versions/com.mapbox.*`, `vector_tile.proto` (Phase 1/2).
- Mapbox is the **map rendering** layer (tiles, camera, markers, user location).

### 1.2 Ferrostar navigation integration (VERIFIED — comprehensive)
`com.stadiamaps.ferrostar.*` (Java/Kotlin bindings) + `uniffi.ferrostar.*` (Rust FFI via UNIFFI):
- Core: `FerrostarCoreException`, `NoCachedSession`, `UserLocationUnknown`, `FerrostarForegroundService`, `FerrostarForegroundServiceManager` (navigation foreground service).
- Navigation engine: `Navigator`, `NavigationController`, `NavigationSession`, `NavigationSessionSnapshot`.
- Route model: `Route`, `RouteStep`, `Waypoint`, `WaypointAdvanceMode`, `WaypointKind`.
- Routing request/response: `RouteRequest`, `RouteRequestGenerator`, `RouteResponseParser`, `RouteAdapter`.
- **Rerouting:** `RouteDeviation`, `RouteDeviationDetector`, `RouteDeviationTracking` (deviation detection → reroute).
- Turn-by-turn: `ManeuverType`, `ManeuverModifier`, `SpokenInstruction`, `VisualInstruction`, `LaneInfo`, `RoadEvent`, `Incident`.
- Progress: `TripProgress`, `TripState`, `TripSummary`.
- **Routing backend = Valhalla** (VERIFIED): `WellKnownRouteProvider`, `ValhallaRoadClass`, `ValhallaLocationSearchFilter`, `annotation.valhalla.*`.
- Compose UI: `composeui.*` (maneuver, speedlimit, controls, overlays, formatting, measurement, notification).
- Simulation/recording: `LocationSimulationState`, `SimulationException`, `NavigationCache`, `NavigationRecorder`, `NavigationReplay`.

### 1.3 Route retrieval & rendering (VERIFIED — mechanism)
- Route geometry is produced by Ferrostar (`RouteRequestGenerator`/`RouteResponseParser`/`RouteAdapter`) against the **Valhalla** routing provider (`WellKnownRouteProvider`); rendered on Mapbox.
- **INFERRED:** the Bolt backend supplies waypoints/route origin+destination to Ferrostar; the actual routing request/response happens via Ferrostar's HTTP client (`ferrostar.core.http.*`).

### 1.4 Navigation session management (VERIFIED)
- `NavigationSession` / `NavigationSessionSnapshot` / `NavigationCache` — session lifecycle + persistence (resume a cached session; `NoCachedSession` when absent).

### 1.5 Turn-by-turn navigation (VERIFIED)
- Maneuver + spoken + visual instruction + lane models above; `FerrostarForegroundService` runs the active navigation.

### 1.6 Distance & ETA (VERIFIED — model presence)
- `TripProgress`, `TripSummary` (Ferrostar) — distance/duration/progress; `OrderStateManager.t0(long, order.details.j)` (timer) and `service.modules.distance.*` (distance module, Phase 4).

### 1.7 Rerouting & route updates (VERIFIED)
- `RouteDeviationDetector`/`RouteDeviationTracking` — off-route detection and re-route.

### 1.8 External navigation handoff (VERIFIED — presence; INFERRED — specifics)
- Phase 2 `<queries>`: Google Maps, maps.me, 2GIS, Waze, Yandex Maps/Navi — external navigation apps. No dedicated handoff class identified by name in this phase → **INFERRED** (opening an external nav app is possible via these queries); specifics UNKNOWN.

---

## 2. Pickup Workflow

### 2.1 Accepted-order handling (VERIFIED)
- `OrderStateChangeType.ACCEPT` → `OrderStateManager` state change (Phase 5); order flows into `ActiveOrderDetails` (`OrderProvider`/`OrdersCache`).

### 2.2 Navigate to pickup (VERIFIED — mechanism)
- Navigation to the pickup is handled by Ferrostar (`Navigator`/`NavigationSession`) with pickup coordinates from `OrderMapPoint`/`OrderStop`/`RideDetailRoutePoint`.

### 2.3 Driver arrival confirmation (VERIFIED)
- `OrderStateChangeType.CONFIRM_ARRIVAL` / `DECLINE_ARRIVAL` — arrival transitions.
- `ee.mtakso.driver.ui.interactor.order.automatic_arrival.*` (field `automatic_arrival.a` in `OrderStateManager`) — automatic arrival detection.

### 2.4 Pickup instructions (VERIFIED — presence)
- `DriverPickupSafetyData`, `BadPickupReason`, `ReportBadPickUpRequest` — pickup instructions/issues (e.g. "passenger not found", report bad pickup).

### 2.5 Passenger contact & communication (VERIFIED)
- `eu.bolt.driver.chat.ui.screen.conversation.ConversationActivity` (Phase 2) — in-app chat with passenger.
- `PassengerMarking` model (Phase 5).

### 2.6 Pickup confirmation — **pickup code** (VERIFIED)
- `ee.mtakso.driver.ui.screens.pickup_code.*`: `PickupCodeRib*` (Builder/Interactor/Presenter/Router/View), `PickupCodeStateManager`.
- Use cases: `ObservePickupCodeStateUseCase`, `ObservePickupCodeStatusUseCase`, `ValidatePickupCodeUseCase` (package `ui.interactor.order.active`).
- `PickupCodeBluetoothPermissionDelegate`, `PickupCodeSkipRationaleDelegate` — Bluetooth-based pickup code + skip rationale.
- `PickupConfirmationCodeStatus` (Phase 5 model), `PickupCodeAnalytics`.
- **INFERRED:** pickup/trip-start is gated by a verified pickup code (shared between passenger and driver), with Bluetooth proximity and skip handling.

---

## 3. Trip Start

### 3.1 Start-trip actions (VERIFIED)
- No class named `StartTrip*` (0 matches). Trip start is expressed through the order state machine (`OrderStateManager` + `OrderStateChangeType`) and the pickup-code flow (`ValidatePickupCodeUseCase`).
- `RiderConfirmationDialog`, `RiderConfirmationStatus`, `AcknowledgeRiderConfirmationRequest`, `OrderConfirmationState` (Phase 5 `confirmation.*`) — rider confirmation around start.

### 3.2 Trip-start validation (VERIFIED)
- `ValidatePickupCodeUseCase` validates the pickup code before proceeding.
- `OrderStateChangeType.CONFIRM_ARRIVAL` marks arrival; starting the trip follows (INFERRED ordering).

### 3.3 Passenger pickup confirmation (VERIFIED)
- Pickup code + rider confirmation (`RiderConfirmation*`, `AcknowledgeRiderConfirmationRequest`) — passenger confirms pickup.

### 3.4 Error handling (VERIFIED — model presence)
- `BadPickupReason`, `ReportBadPickUpRequest`, `OrderStateManager` typed error handlers (Phase 5).

---

## 4. Active Trip

### 4.1 Active order state (VERIFIED — structure)
- `OrderStateManager.s = MutableStateFlow<order.v2.m>` + `r = subjects.e<…m0>` (reactive state); `ActiveOrderDetails`, `OrderHandle` (Phase 5). State value classes are obfuscated (`m`/`m0`) → **UNKNOWN** names.

### 4.2 GPS transmission during trip (VERIFIED — wiring)
- `OrderStateManager` field `service.geo.transmitter.g` — **geo transmitter** (VERIFIED dependency). GPS location is transmitted during the trip. Endpoint/payload **UNKNOWN**.

### 4.3 Route progress (VERIFIED)
- Ferrostar `TripProgress`/`TripState`/`NavigationSession` — live route progress.

### 4.4 Destination changes (VERIFIED)
- `ChangeRouteRequest` (+ `ChangeRouteRequest$DestinationStop`), `OrderStateChangeType.CHANGE_DESTINATION`, `SetDestinationRequest`, `PriceCalculationForRouteChangeConfirmationRequest/Response` — destination change with price recalculation.

### 4.5 Stop / waypoint management (VERIFIED)
- `OrderStop`, `UpcomingStop`, `StopType`, `StopSummary`, `StopRequest`, `StopTimerResponse`, `OrderStateChangeType.SWITCH_STOP`, `AddressChangeType` — multi-stop handling.

### 4.6 Passenger communication (VERIFIED)
- `eu.bolt.driver.chat.*` (chat), `PassengerMarking`.

---

## 5. Trip Completion

### 5.1 Finish-trip actions (VERIFIED)
- `FinalizeOrderRequest` — finish/finalize order request.
- `OrderStateChangeType.BEFORE_FINISH_ORDER`, `FINISH_PARCEL_ORDER` — completion transitions.

### 5.2 Final distance & duration (VERIFIED)
- Ferrostar `TripSummary` (final distance/duration); `OrderCompletionReason`, `OrderReceipt` (post-trip receipt model).

### 5.3 Completion confirmation (VERIFIED)
- `OrderReceipt`, `PriceReviewInfo`/`PriceReviewState` (earnings review), `RateClientRequest` (driver rates passenger) — post-trip confirmation/rating.

### 5.4 Post-trip state transitions (VERIFIED — type level)
- `BEFORE_FINISH_ORDER` → completion → rating/price-review; `OrderStateChangeType` governs. Exact sequence **UNKNOWN**.

---

## 6. Cancellation

### 6.1 Driver cancellation (VERIFIED)
- `OrderStateChangeType.CANCEL_CURRENT_ORDER`, `CANCEL_NEXT_ORDER`.
- `CancelOrderCreationBody` (cancel request), `CancellationConfirmationScreen` (confirmation UI).
- `OrderStateManager.f2(CancellationReason)`, `g2(...CancellationReason...)`.

### 6.2 Passenger cancellation (VERIFIED — mechanism; INFERRED — specifics)
- Passenger-initiated cancellation arrives as an order state change (server-driven), handled by `OrderStateManager`; `CancelRideNotification`/`CancelRideNavigationScreen` (Phase 5, scheduled-rides models). No dedicated passenger-cancel endpoint on the driver client (the passenger cancels via the Passenger app/backend) → **INFERRED** the driver client just observes the state change.

### 6.3 Cancellation reasons (VERIFIED)
- `CancellationReason`, `RejectReason`, `RejectReasonInfo`, `CancelRideReason` (Phase 5).

### 6.4 Cancellation fees / penalties (UNKNOWN)
- No fee/penalty model surfaced on the driver client; any cancellation fee is server-computed and not observable.

### 6.5 Order-state cleanup (VERIFIED)
- `OrdersCache` + `OrderStateManager` cancellation error/cleanup handlers (Phase 5) clear the active order and return the driver to available (`DriverOnlineStatus`, Phase 4).

---

## 7. Trip State Machine

### 7.1 `OrderStateManager` (VERIFIED — structure)
- 22 fields, 177 methods, 33 inner classes (all obfuscated). Key deps: `OrderProvider`, `OrdersCache`, `pollerv2.b`, `geo.transmitter.g`, `DriverDestinationsManager`, `automatic_arrival.a`, RxJava subjects, `MutableStateFlow<order.v2.m>`.

### 7.2 Readable state names (VERIFIED — the transition enum only)
- `OrderStateChangeType`: `ACCEPT`, `BEFORE_FINISH_ORDER`, `CANCEL_CURRENT_ORDER`, `CANCEL_NEXT_ORDER`, `CHANGE_DESTINATION`, `CONFIRM_ARRIVAL`, `DECLINE_ARRIVAL`, `DEFAULT`, `FINISH_PARCEL_ORDER`, `SWITCH_STOP`.
- This is the **driver-initiated action** vocabulary, not the full trip state.

### 7.3 Transitions & triggering methods (VERIFIED — dispatch pattern)
- `OrderStateManager.n2/w1/m1/y1/o2/Z0/x1/z1/A1/B1` all dispatch on `OrderStateChangeType`; `X1(): OrderStateChangeType` returns the current change type; `Z1(): StateFlow<m>` exposes current state.
- Specific per-transition method bodies **UNKNOWN** (obfuscated).

### 7.4 Obfuscated states (UNKNOWN)
- `order.v2.m` and `order.v2.m0` (the state value + change-event types) are obfuscated; their enum/values are **UNKNOWN**.

### 7.5 Server-provided vs local UI states (VERIFIED boundary)
- **Server-provided:** trip lifecycle status (offer → accepted → arriving → on-trip → finished) is reflected via `Order`/`ActiveOrderDetails` and `OrderStateChangeType` responses.
- **Local:** Ferrostar navigation state (`TripState`), pickup-code UI state, and `MutableStateFlow<m>` derived UI state.
- The server is the source of truth for order status; the client applies local navigation/UI state on top.

---

## 8. Navigation SDK Boundary

### 8.1 Mapbox (VERIFIED)
- Map rendering, camera, markers, user-location layer, vector tiles (`vector_tile.proto`), location updates (`com.mapbox.common.location`).

### 8.2 Ferrostar (VERIFIED)
- Rust turn-by-turn navigation engine (UNIFFI FFI): route requests/parsing, maneuver/instruction/lane generation, deviation detection + rerouting, session cache/replay, foreground navigation service, `TripProgress`/`TripSummary`.

### 8.3 Remote routing (VERIFIED — Valhalla provider; specifics INFERRED)
- Ferrostar routes via **Valhalla** (`WellKnownRouteProvider`, `ValhallaRoadClass`, `annotation.valhalla.*`) through its HTTP client. The Bolt backend supplies order waypoints; the concrete Valhalla endpoint/token config is **UNKNOWN**.

### 8.4 Not assumed (explicit)
- The routing backend/algorithm details beyond "Valhalla provider present" are **not** assumed; Ferrostar's internal Valhalla URL/auth and Bolt's server-side dispatch are out of scope.

---

## 9. Unresolved Questions (for Phase 7)

1. **Order state values:** decompile `order.v2.m` / `m0` to enumerate the actual trip states and change events.
2. **Start-trip trigger:** which `OrderStateManager` method fires trip start after pickup-code validation (obfuscated).
3. **Pickup code semantics:** is the code local (Bluetooth) or server-verified via `ValidatePickupCodeUseCase`?
4. **Geo transmitter payload:** `service.geo.transmitter.g` request/response model and upload endpoint.
5. **Ferrostar route origin:** how Bolt passes waypoints into Ferrostar (a `RouteRequestGenerator` adapter?) — trace the adapter implementation.
6. **Valhalla endpoint/token:** where the Valhalla base URL / API key is configured.
7. **Cancellation fee:** confirm absence of a client-side fee model (expected: server-only).
8. **Trip summary mapping:** how Ferrostar `TripSummary` (distance/duration) maps into `FinalizeOrderRequest`/`OrderReceipt`.
9. **External nav handoff:** the concrete class that opens Waze/Google/Yandex (INFERRED, not found).

---

## 10. Limitations

1. Heavy obfuscation — `OrderStateManager` internals and `order.v2.m`/`m0` are unreadable; only type/enum names are reliable.
2. No runtime/network capture; routing/transmission behaviour is inferred.
3. No credentials/tokens/personal data extracted.
4. Split APKs (native libs incl. Ferrostar/Mapbox `.so`) not decompiled this phase.
5. Routing backend (Valhalla) configuration and Bolt server-side dispatch are not observable and are not claimed.
