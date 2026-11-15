# BOLT Driver — Phase 4: Availability & Background Location

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`
**Tooling:** REA MCP + JADX headless 0.7.1 (`get_class_summary` + class search).
**Scope:** Read-only static analysis. No APK modification, no runtime, **no credential/data extraction**.

Confidence labels:
- **VERIFIED** — directly observed in JADX class metadata / manifest.
- **INFERRED** — deduced from field/method types and module naming; not proven by bytecode.
- **UNKNOWN** — not resolvable from static evidence (obfuscation / backend-only).

**Overarching note:** The driver service core lives in `ee.mtakso.driver.service.*`. Its sub-modules are largely readable by *package* (`status`, `polling`, `reporters`, `fifo`, `map`, `distance`, `order.v2`, `driverdestinations`, `emergencyassist`) but their *class* names are obfuscated (`a`–`z`). Backend dispatch/approval logic is not observable and is not claimed.

---

## 1. Driver Online/Offline

### 1.1 Availability state model (VERIFIED)
- `ee.mtakso.driver.service.modules.status.DriverOnlineStatus` — a **sealed class with 8 subclasses** (`a`–`h`). These represent the distinct online/offline availability states. Structure VERIFIED; individual state names **UNKNOWN** (obfuscated).
- `ee.mtakso.driver.service.modules.status.GoOnlineFlowResult` — a **sealed class with 7 subclasses** (`a`–`g`) representing the go-online *result* (success vs. blockers). Structure VERIFIED; result names **UNKNOWN**.

### 1.2 Go-online UI & blockers (VERIFIED)
- `ee.mtakso.driver.ui.screens.work.GoOnlineButton` — the go-online control.
- `ee.mtakso.driver.ui.screens.work.GoOnlineIssueDialogDelegate` — dialog surfacing issues/blockers that prevent going online.

### 1.3 Online/offline transitions & persistence (VERIFIED — mechanism)
`ee.mtakso.driver.service.AwakeService` (the online "awake" foreground service, `foregroundServiceType="location"`):
- Lifecycle: `onCreate`, `onStartCommand`, `onDestroy`, `onBind`.
- Notification management: methods `g(...)`/`h(...)` → `android.app.Notification`; `N(Notification)`, `T(Notification)`, `U(...)`, `V(Notification)` (notification update/validation).
- Stop/failure telemetry: `S(AwakeServiceAnalytics$StopReason)`, `Q(AwakeServiceAnalytics$FailureReason)`; `AwakeServiceAnalytics` has nested `EntryPoint`, `FailureReason`, `StopReason`, `Path`.
- Dependencies (field types reveal the wiring):
  - `ee.mtakso.driver.service.auth.u` — auth/session.
  - `ee.mtakso.driver.param.DriverProvider` — driver params/identity.
  - `ee.mtakso.driver.platform.core.PlatformManager` — platform.
  - `ee.mtakso.driver.utils.power.a` — **power/battery handling** (see §3.4).
  - `ee.mtakso.driver.service.k`, `service.m`, `service.j` — service sub-modules (obfuscated; `j` is a state/status type used by notification + stop logic).
  - `kotlinx.coroutines.CoroutineScope` + `Job` — coroutine-driven lifecycle.
  - `ee.mtakso.driver.service.quickaccess.b` — quick-access/notification tile.

**INFERRED:** `AwakeService` is the persistent "online" process/foreground service: it keeps a foreground notification while the driver is online, observes power/battery state, and reports start/stop/failure with typed analytics reasons. Exact transition rules are **UNKNOWN** (obfuscated + backend).

### 1.4 Eligibility checks (VERIFIED — mechanism)
- `GoOnlineFlowResult` (7 outcomes) + `GoOnlineIssueDialogDelegate` prove server-authoritative eligibility gating; the client only renders results/blockers. (Phase 3 also linked onboarding `OnBoardingStep.Severity` and `InternalVerificationStatus`.)

### 1.5 Availability persistence (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.order.v2.PersistedClientRatingTimeout`, `PersistedPriceReviewInfo` (persisted state models) and `OrderClientRatingTimeoutService` — evidence of persisted service state. Overall availability persistence (online status across restarts) is **INFERRED** (auth prefs + `AwakeService` re-entry), not directly proven.

---

## 2. Location Acquisition

### 2.1 Providers (VERIFIED)
- **Mapbox Maps/Common** — native `libmapbox-maps.so`/`libmapbox-common.so`, `com.mapbox.common.location.LocationUpdatesReceiver` (manifest), `sdk_versions/com.mapbox.*` (Phase 1/2). Mapbox is the primary map + location stack.
- `ee.mtakso.driver.service.modules.map.*` — driver map/location service module (VERIFIED package; classes obfuscated).

### 2.2 Repositories / use cases (UNKNOWN)
- No readable location repository/use-case class names surfaced (`driver.location` → 0, `LocationReporter` → 0). Location acquisition is embedded in Mapbox SDK + obfuscated `service.modules.map.*`/`distance.*`/`reporters.*`.

### 2.3 Update intervals & accuracy (UNKNOWN)
- No explicit interval/accuracy constant was observed by name. `RibMapDelegate`-equivalent accuracy handling (zoom-from-accuracy) was seen in Passenger but not independently confirmed here.

### 2.4 Last-known location (INFERRED)
- Mapbox location + the reporting/polling modules imply last-known caching; not directly evidenced in driver class names.

### 2.5 Location permission handling (VERIFIED)
- Manifest: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` (Phase 2).
- `ee.mtakso.driver.utils.power.a` and `PlatformManager` are in `AwakeService`; permission-gating logic itself is obfuscated (**UNKNOWN** specifics).

---

## 3. Background Location

### 3.1 AwakeService (VERIFIED)
- `ee.mtakso.driver.service.AwakeService` — `foregroundServiceType="location"` (manifest), exported=false. This is the background/location foreground service (see §1.3 field evidence).

### 3.2 ACCESS_BACKGROUND_LOCATION usage (VERIFIED — declared)
- `ACCESS_BACKGROUND_LOCATION` is declared (Phase 2). Combined with `AwakeService` (location FGS) and Mapbox location, this indicates the app requests/uses background location while online. Exact background location *code paths* are **UNKNOWN** (obfuscated).

### 3.3 Foreground location service lifecycle (VERIFIED — structure)
- `AwakeService`: `onStartCommand`/`onCreate`/`onDestroy` + persistent notification + typed stop/failure reasons. Start/stop is driven by online/offline state (INFERRED).

### 3.4 WorkManager & boot receiver (VERIFIED)
- WorkManager services (`SystemAlarmService`, `SystemJobService`, `SystemForegroundService`), `WorkManagerInitializer` startup, and boot/time receivers (`RescheduleReceiver`, `ConstraintProxy*`) — background task rescheduling (Phase 2).

### 3.5 Battery optimization handling (VERIFIED — presence)
- `ee.mtakso.driver.utils.power.a` (power utility referenced by `AwakeService`) and Phase 2 `<queries>` into OEM power/battery managers (miui, letv, asus, huawei, coloros, iqoo, evenwell, meizu, oppo) — a battery-optimisation whitelisting/exemption flow for the online service. Specific exemption logic **UNKNOWN**.

---

## 4. Location Transmission

### 4.1 Upload interfaces (UNKNOWN)
- No readable Retrofit endpoint for driver location upload was surfaced (obfuscated). Networking is OkHttp-based (Phase 1).

### 4.2 Reporter module (VERIFIED — presence; INFERRED — purpose)
- `ee.mtakso.driver.service.modules.reporters.*` (`a`–`f`) — reporter classes. **INFERRED** to transmit driver location/state to the backend (reporting module). Exact request/response models **UNKNOWN**.

### 4.3 Polling module (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.polling.*` (`a`–`d`) — a **polling** transport mechanism (VERIFIED existence). **INFERRED**: driver availability/order state is synchronized via polling (in addition to FCM).

### 4.4 Batching / buffering / retry (UNKNOWN)
- No explicit batching/buffering/retry classes were identified by name. `reporters.*` + `polling.*` imply periodic reporting, but buffer/retry semantics are UNKNOWN.

### 4.5 Local vs remote (VERIFIED boundary)
- **Local:** Mapbox location acquisition + map rendering (device-side), `distance.*` module (local distance tracking), `AwakeService` presence.
- **Remote:** reporter/polling transmission to backend (INFERRED mechanism; endpoints/algorithm UNKNOWN). No backend dispatch logic is claimed.

---

## 5. Availability Communication

### 5.1 FCM (VERIFIED)
- `ee.mtakso.driver.platform.google.push.FirebasePushService`, `FirebaseMessagingService`, `FirebaseInstanceIdReceiver` (Phase 2) — push for incoming offers/status.

### 5.2 Polling & FIFO dispatch (VERIFIED — presence)
- `ee.mtakso.driver.service.modules.polling.*` — polling transport.
- `ee.mtakso.driver.service.modules.fifo.*` — a **FIFO** module (queue ordering — INFERRED: driver dispatch/offer queue).

### 5.3 Order state synchronization (VERIFIED — model presence)
- `ee.mtakso.driver.service.modules.order.v2.OrderStateManager`, `OrderTracker`, `OrderStateChangeType`, `AcceptOrderNotFoundAlertingException` — order state management and change-type model (readable). This is the driver-side order/availability state machine (details belong to a later phase).

### 5.4 Realtime transport (UNKNOWN)
- No first-party WebSocket class was identified by name in this phase. Native SDKs (Mapbox, Ferrostar, Sinch) carry their own transports. Availability/order sync appears to be **FCM push + polling** (INFERRED); a dedicated WebSocket is not evidenced.

### 5.5 Background synchronization (VERIFIED — presence)
- WorkManager + boot receivers (Phase 2) + `polling.*` + `reporters.*` — background synchronization of state/location while offline.

---

## 6. Driver Location Visibility

### 6.1 Representation of current location (VERIFIED)
- Mapbox Maps renders the driver location; `ee.mtakso.driver.service.modules.map.*` (map module) + `distance.*` (distance tracking) represent current position and travelled distance.
- `ee.mtakso.driver.service.modules.driverdestinations.DriverDestinationsManager` — driver destination (set destination while online).

### 6.2 Background continuation (INFERRED)
- `AwakeService` (location FGS) + `ACCESS_BACKGROUND_LOCATION` + Mapbox `LocationUpdatesReceiver` → location updates **continue while backgrounded** while the driver is online. This is INFERRED from the manifest/service declarations; no runtime confirmation.

### 6.3 Lifecycle & service dependencies (VERIFIED)
- `AwakeService` lifecycle (`onStartCommand`/`onDestroy`), notification, power utility, `PlatformManager`, `DriverProvider`, analytics — the online/background-location lifecycle is bound to `AwakeService`.

---

## 7. Local vs Backend Boundary (explicit)

- **Client-side (VERIFIED/INFERRED):** online/offline state model (`DriverOnlineStatus`, `GoOnlineFlowResult`), go-online UI/blockers, `AwakeService` foreground presence + notification + power handling, Mapbox location acquisition/rendering, distance tracking, polling/reporter synchronization, FCM reception.
- **Backend-side (UNKNOWN, not claimed):** availability authorization, dispatch/FIFO ordering, driver matching, location consumers, surge/dispatch rules. None is observable here.

---

## 8. Unresolved Questions (for Phase 5 and beyond)

1. **`DriverOnlineStatus` states:** what are the 8 sealed states (`a`–`h`)? Decompile each subclass / the analytics name mapper.
2. **`GoOnlineFlowResult` states:** what are the 7 go-online outcomes? Decompile subclasses.
3. **Location provider/repository:** which class acquires GPS/fused location (Mapbox `LocationUpdate` client wrapper)? `driver.location` and `LocationReporter` were absent — find the obfuscated provider.
4. **Location upload endpoint & payload:** what is the request/response model used by `reporters.*`/`polling.*`?
5. **Transmission transport:** is driver location sent over HTTP polling, a persistent socket, or both? Confirm with method-body decompilation.
6. **Background-location cadence:** what interval/accuracy and background-restriction policy (Android 12+ `ACCESS_BACKGROUND_LOCATION` + FGS) does `AwakeService` enforce?
7. **Battery exemption flow:** how does `utils.power.a` + OEM `<queries>` actually request battery optimization exemption?
8. **Order state machine:** `OrderStateManager`/`OrderTracker`/`OrderStateChangeType` transitions (defer to Phase 5).

---

## 9. Limitations

1. Heavy obfuscation — most service-module classes are single-letter; state/enum *names* are unreadable.
2. No runtime/network capture; conclusions are static and transmission is inferred, not observed.
3. No credentials/tokens/personal data extracted.
4. Split APKs (native libs) not decompiled this phase (filenames only, Phase 1).
5. Backend dispatch/availability rules are out of scope (not observable, not claimed).
