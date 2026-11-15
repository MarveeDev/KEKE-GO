# BOLT Passenger — Phase 6: Location, Maps & Geospatial Analysis

**Target:** `C:\REA-BOLT\artifacts\passenger\base.apk`
**SHA-256:** `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`
**Package:** `ee.mtakso.client` (Bolt passenger), versionName `CA.231.0`
**Tooling:** REA MCP + JADX headless 0.7.1 (class inventory + method-body decompilation)
**Scope:** Read-only static analysis. No APK modification, no runtime/network capture.

Confidence labels:
- **VERIFIED** — directly observed in decompiled JADX class/method metadata or manifest.
- **INFERRED** — deduced from naming/dependency types; not proven by bytecode or runtime.
- **UNKNOWN** — not resolvable from static evidence.

The app is ProGuard/R8-obfuscated: use-case internals are single-letter (`Order.a`, `locationcore.domain.interactor.a`–`s`, `h.a(Order)`), but higher-level UseCase/Repository/Delegate/RIB class names are readable. Backend behaviour is **not** observable from this APK and is never claimed.

---

## 1. Location Permissions

### 1.1 Declared permissions (VERIFIED — from Phase 4 manifest)
- `android.permission.ACCESS_COARSE_LOCATION`
- `android.permission.ACCESS_FINE_LOCATION`
- `<uses-permission-sdk-23>` variants of both coarse and fine (legacy runtime grant on API ≥23).
- **`ACCESS_BACKGROUND_LOCATION` is NOT declared** — the app has **no background location permission** (VERIFIED by its absence in the extracted manifest). Any location use is foreground/while-in-use only.

### 1.2 Runtime permission handling (VERIFIED)
- `eu.bolt.client.locationcore.domain.interactor.RequestLocationPermissionUseCase` (`requestPermissions`) — central runtime request.
- `eu.bolt.client.locationcore.util.LocationPermissionProvider` — wraps the permission state/query.
- `ee.mtakso.client.monitors.LocationPermissionMonitor` (`doStart`) — a monitor that observes permission state changes.
- `eu.bolt.ridehailing.ui.ribs.activerideflow.activeride.livelocation.interactor.ShouldTurnLiveLocationOnAutomaticallyUseCase` (`preciseLocationPermissionsGranted`) — decides whether to auto-enable live location when precise permission is granted.
- `eu.bolt.client.login.domain.interactor.AskLocationPermissionAndLoginSavedUserUseCase` — asks location permission during saved-user login.

### 1.3 Denial / recovery flows (VERIFIED)
- `eu.bolt.client.locationcore.domain.interactor.EnableLocationUseCase` — prompt user to enable location.
- `eu.bolt.client.locationcore.util.EnableLocationInAppHelper` / `EnableLocationInAppDelegate` (`requestEnableLocationInApp`) — in-app "enable location" prompt.
- `eu.bolt.client.locationcore.domain.interactor.RequestLocationServicesUseCase` — request system location services.
- `eu.bolt.client.locationcore.domain.interactor.GetLocationServicesStatusUseCase`, `GetLocationActiveStatusUseCase` — check services/active status.
- `eu.bolt.client.locationcore.domain.model.LocationErrorStatus`; `eu.bolt.client.locationcore.data.storage.GpsApiException`, `GpsResolvableApiException` — resolvable GPS errors (e.g. settings resolution).
- `eu.bolt.client.locationcore.domain.interactor.GetOverviewMapPointsUseCase.getLocationWithoutPermissionGranted` — map still operates (with last-known/default points) when permission is denied.

Interpretation (INFERRED): the recovery flow is (1) request permission → (2) if denied, show in-app rationale + request location-services/settings resolution → (3) degrade gracefully to last-known location. Exact UX copy/ordering is not asserted.

---

## 2. GPS and Location Updates

### 2.1 Provider & acquisition (VERIFIED)
- `eu.bolt.client.locationcore.data.location.GoogleGpsLocationStorage` — the concrete location provider (Google Fused Location / GPS). Methods: `observeLocationUpdates`, `getLastLocation`, `getLocationSettingStatus`, `checkLocationSettingStatus`.
- `eu.bolt.client.locationcore.data.location.ReserveLocationProvider` — alternate/reserve provider abstraction.
- `eu.bolt.client.locationcore.data.mock.MockLocation` — mock location (test/debug).

### 2.2 Location update use cases (VERIFIED)
- `FetchLocationUpdatesUseCase` (`locationUpdateAvailable`)
- `FetchLocationWithLastLocationUseCase`
- `FetchLocationOrErrorUpdatesFlowUseCase` (`resultUpdates`)
- `ObserveLocationUpdatesUseCase`, `ObserveLocationUpdatesOptionalUseCase`
- `GetOptionalLocationUseCase`
- `GetLocationActiveStatusUseCase`, `GetLocationServicesStatusUseCase`
- `GetInitialZoomingPointsUseCase` (`getUserLocation`) — initial map camera points.
- `GetOverviewMapPointsUseCase` (`locationsByState`, `getLocationWithoutPermissionGranted`) — map points for the overview.
- `GetCountryByLatLngUseCase` — country lookup from coordinates (reverse geocode, remote).

### 2.3 Caching & repository (VERIFIED)
- `eu.bolt.client.locationcore.domain.repo.LocationRepository` — location repository abstraction.
- `GoogleGpsLocationStorage.getLastLocation` — last-known location caching (device-side).
- Models: `LatLngModel` (+ `LatLngModel.Detailed`, `LatLngModelAdapter` serializer), `LocationSource`, `PlaceSource` (+ adapters), `LocationCapability`, `LocationAddressDetails`, `PickupLocation` / `EmptyPickupLocation` / `ExistingPickupLocation`, `InteractionMethod`.

### 2.4 Intervals & accuracy (UNKNOWN / INFERRED)
- No explicit location-update interval or accuracy constant was observed by name. Accuracy handling is only **indirectly** evidenced by `RibMapDelegate.calculateZoomForAccuracyBounds` (camera zoom derived from location accuracy) and `setApproximateLocationEnabled` / `subscribeApproximateLocationCircle` (approx-location circle UI) → **INFERRED** accuracy-driven UX; the actual accuracy/interval configuration is **UNKNOWN** (likely inside `GoogleGpsLocationStorage`, obfuscated).

---

## 3. Map Implementation

### 3.1 Google Maps integration (VERIFIED)
- `com.google.android.gms.maps.GoogleMap`, `com.google.android.gms.maps.GoogleMapOptions`, `com.google.android.gms.maps.model.Polyline`/`PolylineOptions` (Google Maps SDK, bundled).
- `ee.mtakso.map.google.marker.manager.GoogleMapSdkMarkerManagerImpl` — marker add/remove/icon handling.
- `ee.mtakso.map.google.marker.manager.GoogleMapSdkMarkerManagerWithClustering` — marker clustering.
- Manifest meta-data `com.google.android.geo.API_KEY` = `@string/google_maps_key` (Phase 4).

### 3.2 Huawei Maps (VERIFIED: not integrated)
- Search for "Huawei" returns only `com.braze.push.BrazeHuaweiPushHandler` (Huawei **push** via Braze, not maps).
- No Huawei Maps SDK classes present. The `<queries>` entry `com.huawei.maps.app` (Phase 4) is **package-visibility only** (for potential external navigation handoff), not SDK integration.

### 3.3 Map init & lifecycle (VERIFIED)
`eu.bolt.client.ribsshared.map.RibMapDelegate` is the central map delegate. Methods:
- `init(...)`, `initMapFlow(...)`, `initWithCurrentLocationsModel(...)`
- `enableMyLocationOnFirstUpdate(...)`, `disableMyLocationWhenMapReady(...)`
- `applyCloudMapId(...)` (cloud-based map styling), `setAlternativeMapStyle(...)`, `cleanupAlternativeMapStyle(...)`
- `observeFinishedMapEvent(...)`, `observeMapActions(...)`

### 3.4 Markers & camera positioning (VERIFIED)
- Camera: `animateToLocation(...)`, `animateToLocations(...)`, `animateToLocationOnMapReadyCompletable(...)`, `calculateZoomForBoundsAround(...)`, `calculateZoomForAccuracyBounds(...)`, `getCurrentZoomLevel(...)`, `getCurrentMapLocation(...)`, `getTargetMapLocation(...)`.
- My-location layer: `onMyLocationClicked(...)`, `locationClickListener(...)`, `enableMyLocationOnFirstUpdate`, `subscribeApproximateLocationCircle`.
- Markers: `GoogleMapSdkMarkerManagerImpl`, `GoogleMapSdkMarkerManagerWithClustering`.

### 3.5 Pickup & destination markers (VERIFIED)
- `eu.bolt.ridehailing.ui.ribs.preorder.addresssearch.ui.AddressSearchItemsProvider` — manages route-point items (current location, pickup, destinations) incl. `addEmptyDestination`, `swapFields`, `resetRouteStop`, `observeMaxStopCountChanges`, `observeRouteChanges`.
- `eu.bolt.ridehailing.ui.ribs.pickupdirections.map.PreOrderDirectionsMapRibInteractor` — `observePickupPinContent`, `observeStartPointData`, `observePickupDirectionPath`, `observeRouteToolTipData`.
- Pickup models: `PickupLocation`, `EmptyPickupLocation`, `ExistingPickupLocation`.

### 3.6 Route rendering / polylines (VERIFIED)
- `ee.mtakso.map.polyline.ExtendedPolyline`, `ee.mtakso.map.polyline.PolylineCreator` — polyline construction.
- `eu.bolt.ridehailing.ui.util.MaintainPolylinesDelegate` — maintains route polylines on the map.
- `eu.bolt.ridehailing.ui.ribs.pickupdirections.map.delegate.PickupDirectionsPathDelegate` — pickup-direction path.
- `GetSelectedCategoryRouteUseCase` (`collectRoutes`, `getStartAndFinishPoints`) — route data feeding the polyline.

---

## 4. Address and Geocoding

### 4.1 Reverse geocoding (VERIFIED — remote)
- `ee.mtakso.client.core.services.location.search.geo.GeoRequestHandler` (`reverseGeocode`, `reverseGeocodeAndSnap`)
- `ee.mtakso.client.core.services.location.search.geo.GeocodeApiCaller` (`reverseGeocode`)
- `ee.mtakso.client.core.services.location.search.geo.RidesGeocodeApiCaller` (`reverseGeocodeAndSnap`)
- `ee.mtakso.client.core.data.models.ReverseGeocodeAndSnapRequest`
- `eu.bolt.ridehailing.core.data.network.model.preorder.ReverseGeocodeAndSnapUseCase`
- `ReverseGeocodeReason`, `ReverseGeocodedModel`
- `GetCountryByLatLngUseCase` — country from coordinates.

### 4.2 Forward geocoding (VERIFIED — remote)
- `GeocodeApiCaller.forwardGeocode`
- `ee.mtakso.client.core.interactors.geocode.GeocodeLocationUseCase`
- `CreateOrderUseCase.applyGeocoder` (Phase 5) — geocodes pickup before submission.
- `ee.mtakso.client.core.services.location.search.BoltGeocoder` (`fixMissingPlaceFields`)
- `eu.bolt.searchaddress.core.data.RideHailingGeocoder` (`geocodeByPlaceId`)

### 4.3 Remote API endpoints (VERIFIED — remote)
- `ee.mtakso.client.core.data.network.endpoints.GeocodeApi`
- `ee.mtakso.client.core.data.network.endpoints.RidesGeocodeApi`
These are Retrofit-style network endpoints → **geocoding is a remote (backend) operation**, not local.

### 4.4 Place search / autocomplete (VERIFIED — custom, no Google Autocomplete)
- **No Google Places Autocomplete SDK** is present (`Autocomplete` search returns 0 matches). Place search is implemented in-app as "address search" with its own suggestion handling:
  - `eu.bolt.client.ribs.addresssearch.*` (RIB, `AddressSearchFieldDelegate`, `AddressSearchFieldsDelegate`, `BaseAddressSearchDelegate` with `searchAddresses`, `ProxyAddressSearchDelegate`)
  - `eu.bolt.ridehailing.ui.ribs.preorder.addresssearch.*` (`AddressSearchRibInteractor`, `AddressSearchOrderState`, `AddressSearchItemsProvider`)
  - `ObserveAddressSearchDestinationUseCase`, `GetNextAddressSearchStateUseCase`, `AddressSearchState`, `AddressSearchOrderRouteRepository`
- Suggestions are observed via `observeSuggestions` / `searchAddresses` → **INFERRED** to be sourced from the Bolt backend (address search is a remote capability), consistent with `GeocodeApi`/`RidesGeocodeApi`.

### 4.5 Address selection & confirmation (VERIFIED)
- `AddressSearchFieldsDelegate.selectAddress`, `handleSuccessfulSetLocation`, `handleCurrentLocationClick`, `resetRouteStop`.
- `eu.bolt.ridehailing.ui.ribs.preorder.addresssearch.ui.AddressSearchFieldsDelegate.handlePickupSelected`, `handleDestinationSelected`, `onSkipDestinationClick`.
- `ConfirmPickupChooseOnMapDelegate`, `ConfirmPickupCreateRideDelegate` (Phase 5) — pickup confirmation.

### 4.6 Pickup pin adjustment (VERIFIED)
- `UpdatePickupAddressUseCase` (Phase 5), `ResetPickupUseCase`, `RestoreFromGPSPickupUseCase`.
- `DestinationChooseOnMapDelegate.pushPreOrderState`, `BoltGeocoder` (reverse-geocode on pin move) — moving the pickup pin triggers reverse geocoding/snapping (INFERRED mechanism, VERIFIED class presence).

---

## 5. Routing and ETA

### 5.1 Route retrieval & display (VERIFIED)
- `GetSelectedCategoryRouteUseCase` (`collectRoutes`, `getStartAndFinishPoints`, `observeDestinations`) — routes for a selected ride category.
- `AddressSearchOrderRouteRepository`, `eu.bolt.client.adddestination.shared.domain.repository.MicromobilityUserRouteRepositoryImpl` — route repositories.
- Route rendering: `ExtendedPolyline` + `PolylineCreator` + `MaintainPolylinesDelegate` (local rendering of backend-provided geometry).

### 5.2 Distance & duration (INFERRED / UNKNOWN)
- `ee.mtakso.client.core.data.network.mappers.order.OrderEtaSecondsToMinutesMapper` — converts ETA seconds → minutes for display (VERIFIED). This is the closest observable "duration" handling; no dedicated distance/duration model surfaced by name → distance/duration values are **INFERRED** to come from backend route/ETA responses; exact fields UNKNOWN.

### 5.3 Driver arrival ETA (VERIFIED)
- `ee.mtakso.client.core.data.models.ArriveDriverEta` (Phase 5).
- `GetPreOrderEtaUseCase`; `eu.bolt.ridehailing.core.domain.interactor.preorder.pickup.GetScheduledRideEtaUseCase` (+ `GetScheduledRideEtaRequest`, remote).
- Pickup ETA: `eu.bolt.client.rhrequestingridemap.delegate.RequestingPickupDelegate.observePickupEta`, `ConfirmOrderChangePickupDelegate.observePickupEta`.
- ETA sharing: `eu.bolt.client.inappcomm.rib.eta.ShareEta*`, `GetShareEtaUrlUseCase` (remote share-ETA URL).

### 5.4 Pickup directions (VERIFIED)
- `GetPickupDirectionsRequest` / `GetPickupDirectionsResponse` (remote network models).
- `eu.bolt.ridehailing.core.domain.model.pickupdirection.PickupDirections`.
- `GetActiveOrderPickupDirectionsUseCase`, `ObservePreOrderPickupDirectionsUseCase` (`startPickupDirectionsPolling` — polls backend for directions).
- UI: `eu.bolt.ridehailing.ui.ribs.pickupdirections.*` (map/list/footer/modal/bottomsheet) + `PickupDirectionsDeeplink`.

### 5.5 Navigation handoff to external apps (INFERRED / UNKNOWN)
- Package-visibility `<queries>` includes `com.google.android.apps.maps`, `com.waze`, `com.huawei.maps.app` (Phase 4) and a `geo://` deep-link scheme is declared — consistent with external-navigation capability.
- No dedicated **ride-hailing** "open external navigation" class was identified by name. Related patterns exist only in other verticals: `eu.bolt.client.rentals.domain.interactor.GetAddressNavigationOptionsUseCase` (`NavigationMode`, `NavigationOption`), `eu.bolt.client.carsharing.domain.interactor.route.ObserveAlternativeNavigationOptionsUseCase`, `eu.bolt.client.micromobility.navigation.domain.interactor.PerformNavigationActionUseCase`.
- Conclusion: external navigation handoff is **INFERRED** (via `geo:`/maps/waze queries) but the concrete ride-hailing handoff class is **UNKNOWN** from static evidence.

---

## 6. Geofencing

### 6.1 Creation & monitoring (VERIFIED)
- Google Play Services geofencing SDK: `com.google.android.gms.location.GeofencingClient`, `GeofencingRequest`, `Geofence`, `GeofencingEvent`, `GeofenceStatusCodes`.
- `eu.bolt.client.geofencing.GeofencingDelegate` (`addGeofences`, `clearGeofences`).
- `eu.bolt.client.geofencing.GeofencingRepository` — `getFromRemote`, `getGeofencingItems`, `getGeofencingItemById`, `refreshGeofencingItems`, `removeGeofencingItem`, `clearGeofencingItems`, `isGeoPushEnabled`, `notificationTriggerCallback`.
- `eu.bolt.client.geofencing.GeofencingWorker` (`observeLocationPermissionsAllowed`) — background worker that (re)registers geofences when permission is granted.

### 6.2 Events & receivers (VERIFIED)
- `eu.bolt.client.geofencing.GeofencingBroadcastReceiver` (manifest receiver) — `handleGeofenceEvent`, `sendGeofenceTriggeredEvent`, `showPushIfEnabled`.
- Analytics: `Analytics$GeofencingNotificaitons$UserGeoFenceNotificationShown`.

### 6.3 Domain models (VERIFIED)
- `eu.bolt.ridehailing.core.domain.model.geofencing.*`: `GeofencingItem`, `GeofencingLocation`, `GeofencingRegion`, `GeofencingRegionCenter`, `GeofencingPayload`, `GeofencingCallback`.

### 6.4 Service-area / restricted-zone logic (INFERRED / UNKNOWN)
- Geofences are **fetched from the backend** (`GeofencingRepository.getFromRemote` / `refreshGeofencingItems`) and trigger **geo-targeted push notifications** (`notificationTriggerCallback`, `showPushIfEnabled`, `isGeoPushEnabled`).
- This is **marketing/notification-oriented** geofencing (Braze `BrazeGeofenceManager` is also present). Whether the same geofence infrastructure enforces ride **service-area restrictions** was **not** observable from class names alone → **UNKNOWN**. No "restricted zone"/"service area" ride-logic class was identified; I do not claim service-area enforcement from this evidence.

---

## 7. Network Boundaries (local vs remote)

### 7.1 Local (device-side, VERIFIED)
- GPS/fused location: `GoogleGpsLocationStorage` (`getLastLocation`, `observeLocationUpdates`) — device location, no network.
- Last-known location caching: `getLastLocation`.
- Map rendering & markers: Google Maps SDK, `GoogleMapSdkMarkerManagerImpl`, `GoogleMapSdkMarkerManagerWithClustering` — local.
- Polyline drawing: `ExtendedPolyline`, `PolylineCreator`, `MaintainPolylinesDelegate` — local rendering of backend-provided geometry.
- ETA formatting: `OrderEtaSecondsToMinutesMapper` — local unit conversion.
- Camera/map interaction: `RibMapDelegate` (animate, zoom, my-location layer, map clicks) — local.

### 7.2 Remote (VERIFIED)
- Geocoding: `GeocodeApi`, `RidesGeocodeApi`, `GeocodeApiCaller.forwardGeocode/reverseGeocode`, `RidesGeocodeApiCaller.reverseGeocodeAndSnap`, `ReverseGeocodeAndSnapUseCase`, `GetCountryByLatLngUseCase` → backend API.
- Address search suggestions: `BaseAddressSearchDelegate.searchAddresses` / `observeSuggestions` → INFERRED backend (no local autocomplete SDK present).
- Route/ETA data: `GetSelectedCategoryRouteUseCase` (backend routes), `GetScheduledRideEtaRequest`, `ArriveDriverEta` (backend-provided).
- Pickup directions: `GetPickupDirectionsRequest/Response`, `ObservePreOrderPickupDirectionsUseCase.startPickupDirectionsPolling` (polling backend).
- Geofence definitions: `GeofencingRepository.getFromRemote` / `refreshGeofencingItems` → backend.
- Share ETA URL: `GetShareEtaUrlUseCase` → backend.

### 7.3 Not claimed
- Backend routing/distance/duration/ETA **algorithms** are not observable and are not described. Only the client's use of their **responses** is documented.

---

## 8. Limitations

1. **Obfuscation:** `locationcore.domain.interactor.a`–`s`, `locationcore.data.location.g/h/i/n`, and many use-case internals are single-letter. Specific algorithm parameters (accuracy, interval, provider selection) could not be read.
2. **No runtime/network capture:** conclusions are static; no permission dialogs, location streams, or HTTP calls were observed live.
3. **No background-location permission:** verified by absence; does not preclude foreground-service location (e.g. SOS `IncidentReportingService` from Phase 4) which is while-in-use.
4. **APK split:** analysis limited to `base.apk`; map/geofence-related code in split/feature modules would not be present here.
5. **Huawei Maps absent:** only Huawei push (Braze) present; Huawei map integration is not in this artifact.
6. **External-navigation handoff** and **service-area geofencing** are marked INFERRED/UNKNOWN because no dedicated class was identified; they are not asserted.
