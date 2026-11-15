# BOLT Passenger — Phase 5: Core Ride-Hailing Analysis

**Target:** `C:\REA-BOLT\artifacts\passenger\base.apk`
**SHA-256:** `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`
**Package:** `ee.mtakso.client` (Bolt passenger app), versionName `CA.231.0`
**Tooling:** REA MCP + JADX headless 0.7.1 (method-body decompilation via `get_method_body`)
**Scope:** Read-only static analysis. No APK modification. No network. No runtime execution.

Confidence labels:
- **VERIFIED** — directly observed in decompiled JADX class/method metadata or decompiled method bodies.
- **INFERRED** — deduced from class/field/method naming and dependency types; not proven by bytecode.
- **UNKNOWN** — not resolvable from static evidence alone.

A key caveat applies throughout: the app is **ProGuard/R8-obfuscated**. Domain model classes and use-case internals use single-letter names (`Order.a`, `OrderState.a`–`h`, `h.a(Order)`), while higher-level UseCase/Interactor/Repository/Delegate class names remain readable. All client-side findings below describe **client behaviour only** — the app sends requests to and renders responses from a Bolt backend whose server-side logic is **not** observable from this APK. No private backend implementation is claimed.

---

## 1. Ride Request

### 1.1 Entry points (VERIFIED)
Ride request is initiated from the map RIB and reachable via deep links:

- `ee.mtakso.client.newbase.RideHailingMapActivity` — main map/ride-hailing screen (from Phase 4 manifest).
- Deep-link dispatchers (VERIFIED class names):
  - `ee.mtakso.client.newbase.deeplink.dispatcher.BookARideDispatcher` — "book a ride" deep-link entry.
  - `ee.mtakso.client.newbase.deeplink.dispatcher.OpenRideHailingDispatcher` — opens ride-hailing flow.
- Pre-order UI RIBs: `eu.bolt.ridehailing.ui.ribs.preorder.*` (category selection, confirm pickup, destination choose-on-map).

### 1.2 Pickup & destination handling (VERIFIED)
- `eu.bolt.ridehailing.core.domain.model.Destinations` — holds pickup + dropoff.
- `eu.bolt.ridehailing.core.domain.model.Order` field `c` = `eu.bolt.client.locationcore.domain.model.LatLngModel$Detailed` (pickup coordinate) and `d` = `Destinations`.
- Use cases that manipulate pickup/destination (VERIFIED names):
  - `ee.mtakso.client.core.interactors.order.UpdatePickupAddressUseCase`
  - `ee.mtakso.client.core.interactors.order.ResetPickupUseCase`
  - `ee.mtakso.client.core.interactors.order.RestoreFromGPSPickupUseCase` (`getAvaliableLocation`)
  - `ee.mtakso.client.core.interactors.order.SwapPreorderRouteUseCase`
  - `ee.mtakso.client.core.interactors.order.OverviewResetDestinationUseCase`
  - `ee.mtakso.client.core.interactors.order.GetSelectedCategoryRouteUseCase` (`getStartAndFinishPoints`, `observeDestinations`)
- `CreateOrderUseCase.getPickupPlace` / `applyGeocoder` — geocoding the pickup before submission.

### 1.3 Ride category & product selection (VERIFIED)
- `ee.mtakso.client.core.interactors.order.SelectCategoryOrOptionUseCase`
- `ee.mtakso.client.core.interactors.order.CheckCategoryConfirmationUseCase`
- `eu.bolt.ridehailing.ui.ribs.preorder.category.selection.CategorySelectionRibInteractor`
- `ee.mtakso.client.core.interactors.order.GetSelectedCategoryRouteUseCase` (routes for a selected category)

### 1.4 Request submission — classes & methods (VERIFIED)
The central submission class is:

**`ee.mtakso.client.core.interactors.order.CreateOrderUseCase`** — methods observed (VERIFIED):
- `execute(...)`
- `requestOrder(...)` — performs the actual order POST
- `createScheduledOrder(...)` — scheduled/pre-booked rides
- `createOrderIgnoringDisposal(...)`
- `applyGeocoder(...)`
- `getPickupPlace(...)`

Supporting use cases (VERIFIED names):
- `ConfirmPickupAndCreateOrderUseCase` (`execute`) — confirm pickup then create.
- `CheckReadyToCreateOrderUseCase` (`checkOrderAction`, `observeLoadedTransaction`) — pre-submit validation.
- `IsReadyToCreateOrderUseCase`, `IsInPreOrderStateUseCase`, `IsInPreOrderOrScheduleRideUseCase`.
- `InitPreOrderTransactionUseCase` (`selectDestination`), `SetPreOrderParamsUseCase`, `GetNewTransactionUseCase`, `RequestNewLoadedTransactionUseCase`.
- `SetPaymentInformationUseCase` — attach payment before/at request.

UI-side orchestration (VERIFIED): `eu.bolt.ridehailing.ui.createrideshared.BaseCreateRideSideFlowDelegate` with methods `onPriceConfirmed`, `observeThreeDS`, `observeGooglePayEvent`, `getSelectedPaymentMethod`, `resolveSelectedPaymentMethod`, `checkAndShowPreAuthRetryDialog`, `showExpenseReasonScreen`, `chooseCalendar`. This confirms the request flow is: select category → pickup/destination → price confirmation → payment → (3DS/Google Pay challenge) → submit.

---

## 2. Fare and Pricing

### 2.1 Fare estimation (VERIFIED)
- `ee.mtakso.client.core.interactors.order.GetPreOrderEtaUseCase` — ETA for the pre-order (displayed alongside price).
- Fare/offer data arrives as part of the order/transaction models; no standalone "fare estimate" class surfaced under a readable name. Price is surfaced through price-bidding offers and the `OrderConfirmationModel`.

### 2.2 Price breakdown & confirmation (VERIFIED)
- `eu.bolt.ridehailing.core.domain.model.order.OrderConfirmationModel` (field `z` of `Order`) — order/price confirmation model.
- `BaseCreateRideSideFlowDelegate.onPriceConfirmed` — user accepts the displayed price.

### 2.3 Surge / dynamic pricing indicators (VERIFIED — mechanism; INFERRED — semantics)
Bolt's dynamic-pricing mechanism is **"price bidding"** (a first-class module), plus a separate "surge confirmation" concept:

- **Surge:** `ee.mtakso.client.core.interactors.order.CheckSurgeToShowUseCase` (`execute`) and `ee.mtakso.client.core.errors.ConfirmSurgeRequiredException` (VERIFIED). The exception name implies the client must obtain user confirmation when surge applies.
- **Price bidding** (VERIFIED): `eu.bolt.client.rhpricebiddingcore.domain.model.offers.PriceBiddingOfferList` (referenced from `Order` field `F`), `eu.bolt.client.rhpricebiddingcore.domain.model.bid.PriceBiddingUi`, `eu.bolt.ridehailing.core.domain.interactor.preorder.SetPriceBiddingOnboardingModalShownUseCase`, `eu.bolt.ridehailing.core.exception.PriceBiddingRequiredException`, and the UI RIB `eu.bolt.client.rhpricebidding.rib.bid.*` (`PriceBiddingRibInteractor.onBidConfirmed`, `onSwitchChanged`, `observePriceBiddingUi`). Use cases: `GetActiveOrderPriceBiddingUiUseCase`, `GetActiveOrderOffersListUseCase`, and network model `PriceBiddingNetworkModel`.

Interpretation (INFERRED): surge/price-bidding offers are computed server-side and delivered to the client; the client renders a "confirm price / bid" UI and enforces confirmation (surge/price-bidding "required" exceptions). The exact pricing algorithm is backend-only and not claimed here.

### 2.4 Discounts & promotions (VERIFIED — presence; INFERRED — semantics)
- `ee.mtakso.client.newbase.deeplink.dispatcher.PromoCodeDispatcher` — promo-code entry point.
- `eu.bolt.campaigns.*` (campaigns module) and `eu.bolt.rentals.overview.worker.UpdateCampaignsWorker` (`observePaymentMethodChanges`, `observeBasedOnOrderState`) — campaign/discount updates.
- `BaseCreateRideSideFlowDelegate.showExpenseReasonScreen` — business-expense tagging (work profiles), a pricing/categorisation concern.

---

## 3. Driver Matching

### 3.1 Driver search & assignment (VERIFIED — partial)
- The "searching for driver" state is handled by `ee.mtakso.client.core.interactors.order.GetRequestingHeaderUseCase` (`simpleOrderResultFlow`, `iconFlow`) — builds the "requesting/searching" header shown while matching. This confirms a client-side "requesting" phase (INFERRED to represent driver search).
- `ee.mtakso.client.core.data.models.ArriveDriverEta` — driver-arrival ETA model (VERIFIED), used when a driver is assigned/en route.

### 3.2 Driver & vehicle information (VERIFIED — field-level)
`eu.bolt.ridehailing.core.domain.model.DriverDetails` (field `i` of `Order`) exposes, via readable getters:
- `getName()`, `getDriverNameExtended()` — driver name
- `getRating()` (String) — driver rating
- `getRidesCountHtml()` — ride count
- `getVehicleDetails()` → `eu.bolt.ridehailing.core.domain.model.VehicleDetails` — vehicle info
- `getCarImage()` → `ImageDataModel` — vehicle image
- `getAvatar()` / `getAvatarNode()` — driver avatar
- `getBanners()` → `List<DriverBanner>` — driver banners
- `getLanguageDetails()` → `LanguageDetails`
- `isFavorite()` (Boolean) — favourite driver flag
- `getOrderDetails()` → `List<CustomOrderDetails>`

### 3.3 Driver arrival / ETA handling (VERIFIED)
- `ArriveDriverEta` (above).
- `GetPreOrderEtaUseCase` (pre-order ETA).
- `ContactOption` list on `Order` (`eu.bolt.client.contactoptionscore.data.entities.ContactOption`) — call/chat driver once assigned.

Note: driver *assignment logic itself* (matching algorithm) is **server-side** — the client only consumes `DriverDetails` and ETA from order responses. This is VERIFIED as client behaviour; the matching engine is UNKNOWN/backend.

---

## 4. Ride Lifecycle (State Machine)

### 4.1 State model (VERIFIED — structure)
`eu.bolt.ridehailing.core.domain.model.OrderState` is a **sealed class with exactly 8 subclasses**: `OrderState.a` … `OrderState.h` (VERIFIED via `inner_class_count: 8`). It has:
- field `a` = `String` (analytics/display name)
- field `b` = `boolean`
- constructor `<init>(String, boolean)`.

Observed subclass shapes (VERIFIED):
- `OrderState.b` is an **object singleton** (`INSTANCE` field, `<clinit>`), i.e. a payload-less state.
- `OrderState.a` is a **data class carrying a value** of type `eu.bolt.ridehailing.core.domain.model.i`.

### 4.2 State observation & derivation (VERIFIED)
- `ObserveOrderStateUseCase.execute()` returns `kotlinx.coroutines.flow.Flow<OrderState>` — a reactive stream of state changes (VERIFIED).
- Decompiled `ObserveOrderStateUseCase.a(Order)`:
  ```java
  public static OrderState a(Order order) {
      if (order != null) return order.getState();
      return null;
  }
  ```
  (VERIFIED) — the current state is stored on the `Order` object (`Order.g : OrderState`, getter `J()`).
- `GetOrderStateAnalyticsNameUseCase.a()` returns the analytics name:
  ```java
  return eu.bolt.ridehailing.core.domain.model.h.a(this.orderRepository.Z2().orNull());
  ```
  and `h.a(Order)` = `order.K()` (or a fallback) — the readable name string is a property of `Order` (VERIFIED).

### 4.3 Actual state names & transitions
- **The 8 states exist** (VERIFIED, as `OrderState.a`–`h`), but their **human-readable names are obfuscated and populated from backend order status strings** (the analytics name comes from `Order.K()`, a backend-derived field). The literal English state names were **not recoverable** from static analysis → **UNKNOWN**.
- The task's suggested names (Requested / Searching / Driver assigned / Arriving / Trip started / Trip completed / Cancelled) are **not verified to exist verbatim**. I do **not** assert these exact state names.

Supporting lifecycle facts that ARE verifiable from readable class names:
- "Requesting/searching" phase: `GetRequestingHeaderUseCase` (VERIFIED) — a requesting state is rendered.
- Finish/completion: `CompleteFinishedRideUseCase` (`completeFinishedOrder`) and `SubmitFinishedOrderRatingUseCase` (VERIFIED) — finished-ride handling and post-ride rating.
- Trip anomaly: `eu.bolt.ridehailing.core.domain.model.order.TripAnomaly` (field `y` of `Order`) — anomaly/safety state (VERIFIED).
- Order confirmation: `OrderConfirmationModel` (VERIFIED).
- Payment change mid-order: `ChangePaymentMethodState` (field `A` of `Order`) and `ActiveOrderChangePaymentMethodUseCase` / `OrderWaitingStateChangePaymentMethodUseCase` (VERIFIED) — a distinct "change payment method" sub-flow with 3DS challenge.
- Ride flow type: `Order.RideFlow` enum (field `L`) — distinguishes ride types (e.g. taxi vs scheduled) (VERIFIED).

**Conclusion:** The lifecycle is modelled as a sealed state machine of 8 states carried on `Order`, observed as a `Flow`, with an analytics name per state. The exact state names and the precise transition function are UNKNOWN (obfuscated/backend-driven); the surrounding readable classes confirm requesting, confirmation, finished, rating, anomaly, and payment-change concerns (VERIFIED/INFERRED).

---

## 5. Real-Time Communication

### 5.1 WebSocket / socket libraries (VERIFIED — library presence only)
The following WebSocket/socket implementations are bundled:
- `okhttp3.WebSocket`, `okhttp3.internal.ws.RealWebSocket`, `WebSocketListener`
- `io.netty.handler.codec.http.websocketx.*` (Netty WebSocket codecs)
- `io.ktor.client.plugins.websocket.WebSocketException`, `io.ktor.client.engine.okhttp.OkHttpEngine$executeWebSocketRequest$1`

No **first-party** ride-state WebSocket client class was identified by name (the matches are all third-party libraries). INFERRED: WebSocket is used by an embedded SDK (e.g. Sinch VOIP/chat) rather than for core ride-state updates.

### 5.2 Push notifications (VERIFIED)
- `ee.mtakso.client.fcm.FcmListenerService` + Firebase `FirebaseMessagingService` / `FirebaseInstanceIdReceiver` (manifest).
- Push handlers (VERIFIED class names):
  - `ee.mtakso.client.fcm.handlers.CarsharingPushHandler`
  - `ee.mtakso.client.fcm.handlers.LiveActivityDispatcherPushHandler`
  - `ee.mtakso.client.fcm.handlers.VoipPushHandler`
  - plus obfuscated handlers `c,d,e,f,h,i,j,k,l,n` and `liveactivity.a–d` — these are almost certainly the ride-hailing push handlers (order/driver updates), but their readable names are obfuscated (UNKNOWN specifics).
- Live Activity push is confirmed (`LiveActivityDispatcherPushHandler`, `liveactivity.*`).

### 5.3 Location updates (VERIFIED)
`eu.bolt.client.locationcore.*`:
- `FetchLocationUpdatesUseCase` (`locationUpdateAvailable`)
- `ObserveLocationUpdatesUseCase`, `ObserveLocationUpdatesOptionalUseCase`
- `GoogleGpsLocationStorage` (`observeLocationUpdates`) — Google GPS-based provider
- `LocationPermissionProvider`, `LatLngModel`
Monitors/workers observing location: `ee.mtakso.client.monitors.SubscriptionsWorker`, `ServiceAvailabilityWorker`, `VehiclesWorker`, `PreOrderMonitor`.

### 5.4 Ride status updates (VERIFIED — mechanism; INFERRED — transport)
Ride state is consumed as a reactive `Flow` from `OrderRepository` (`ObserveOrderStateUseCase`). Transport is inferred to be **FCM push (realtime triggers) + REST/polling via repositories** — consistent with the FCM push handlers and worker/monitor classes. The exact push→repository wiring for ride state is obfuscated (UNKNOWN specifics).

---

## 6. Payment

### 6.1 Payment method selection (VERIFIED)
- `eu.bolt.client.payments.interactors.SelectPaymentMethodUseCase`
- `eu.bolt.client.payments.interactors.SelectOneTimePaymentMethodUseCase`
- `eu.bolt.client.payments.interactors.GetExternalPaymentMethodsUseCase`
- `eu.bolt.client.payments.PaymentInformationRepository` (`selectPaymentMethod`, `syncPaymentMethod`)
- `eu.bolt.client.payments.PaymentActiveOrderRepository` (`changPaymentMethod`)
- `eu.bolt.client.paymentmethods.interactor.ObserveSelectedPaymentMethodUseCase`
- `ee.mtakso.client.core.interactors.order.SetPaymentInformationUseCase`
- UI RIBs: `eu.bolt.client.paymentmethods.rib.*` (bottom sheet, fullscreen, selection flow)
- Models: `eu.bolt.client.payments.domain.model.v2.PaymentMethodV2`, `BalancePaymentMethod`, `PaymentMethodStatus`, `PaymentMethodSelection`

### 6.2 Payment confirmation (VERIFIED — mechanism; INFERRED — semantics)
- `PaymentMethodsChallengeDelegate` and `BlocksModalActionDispatcher.handlePostRequestWithPaymentInfo` — payment is submitted with the order and may trigger a challenge.
- `ChangePaymentMethodResponse` / `PaymentMethodResponse` — network responses (VERIFIED).
- `BaseCreateRideSideFlowDelegate.resolveSelectedPaymentMethod` / `handleInvalidPaymentMethod` / `checkAndShowPreAuthRetryDialog` — pre-auth retry handling on payment decline (VERIFIED; retry semantics INFERRED).

### 6.3 Card & wallet integrations (VERIFIED)
- Card: `eu.bolt.client.creditcard.interactor.CreatePaymentMethodUseCase`, `SyncPaymentMethodUseCase`, `eu.bolt.client.creditcard.repo.AddCreditCardRepository` (`createPaymentMethodWithBolt`).
- Google Wallet/Pay: `com.google.android.gms.wallet.PaymentMethodToken`, `PaymentMethodTokenizationParameters`; `BaseCreateRideSideFlowDelegate.observeGooglePayEvent`; `PaymentMethodsChallengeDelegate.observeGooglePayResults`; manifest meta-data `com.google.android.gms.wallet.api.enabled = true` (Phase 4).

### 6.4 3DS integration (VERIFIED)
- `ee.mtakso.client.activity.ThreeDSActivity` (manifest — 3-D Secure activity).
- `BaseCreateRideSideFlowDelegate.observeThreeDS` (two handlers) — observes 3DS result during ride creation.
- `eu.bolt.client.payment.shared.PaymentMethodsChallengeDelegate` — payment challenge.
- `ActiveOrderChangePaymentMethodDelegate.processChallengeForChangePaymentMethod` — 3DS challenge when changing payment method mid-order.
- `eu.bolt.client.blocksmodal.ribs.actions.BlocksModalActionDispatcher.handle3DSError` / `handleGooglePayChallenge` — 3DS/Google Pay challenge error handling.

---

## 7. Client vs Backend Boundary (explicit)

- **Client-side (VERIFIED/INFERRED):** request UI flows, category selection, pickup/destination editing, price/surge/price-bidding *confirmation UI*, driver/vehicle *display*, reactive state observation, FCM push handling, GPS location collection, payment method *selection UI*, 3DS *challenge display*.
- **Backend-side (UNKNOWN, not claimed):** fare computation, surge/dynamic-pricing calculation, driver matching/dispatch algorithm, ETA computation, order state transitions and status strings, payment authorisation/capture, 3DS orchestration. None of these are observable from this APK and are intentionally **not** asserted.

---

## 8. Limitations

1. **Obfuscation:** domain models and many use-case internals are ProGuard/R8-obfuscated (`OrderState.a`–`h`, `Order.a`–`N`, `h.a(Order)`). Readable English state names and the exact transition logic could not be recovered; they are marked UNKNOWN.
2. **No runtime/network observation:** conclusions are static; no behaviour was executed or captured.
3. **Backend opacity:** only client-side classes were analysed; no server logic is claimed.
4. **APK split:** analysis is limited to `base.apk`; some classes (e.g. VOIP service from Phase 4) may live in split/feature modules not present here.
5. **Method-body coverage:** a few methods were decompiled to confirm wiring; not every referenced method body was inspected.
