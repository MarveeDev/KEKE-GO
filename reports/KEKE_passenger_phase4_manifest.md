# BOLT Passenger — Phase 4: Manifest & Component Analysis

**Target:** `C:\REA-BOLT\artifacts\passenger\base.apk`
**SHA-256:** `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`
**Tooling:** REA MCP + JADX headless 0.7.1 (`jadx-headless-mcp-0.7.1-all.jar`), OpenJDK 25.0.1
**Scope:** Read-only. No APK modification. No deep decompilation of method bodies.

Confidence labels used throughout:
- **VERIFIED** — directly read from decoded `AndroidManifest.xml` or JADX class metadata.
- **INFERRED** — deduced from naming/convention/dependency types; not proven by runtime or bytecode.
- **UNKNOWN** — not resolvable from the available static evidence.

---

## 1. Application-level configuration (VERIFIED)

| Attribute | Value |
|---|---|
| Package | `ee.mtakso.client` |
| versionCode | `4400` |
| versionName | `CA.231.0` |
| compileSdkVersion | `36` |
| minSdkVersion | `24` |
| targetSdkVersion | `36` |
| Application class | `ee.mtakso.client.BoltApplication` |
| Theme / label / icon | `@style/BoltTheme` / `@string/app_name` / `@mipmap/ic_launcher` |
| appComponentFactory | `androidx.core.app.CoreComponentFactory` |
| Flags | `hardwareAccelerated=true`, `largeHeap=true`, `supportsRtl=true`, `extractNativeLibs=false`, `allowNativeHeapPointerTagging=false` |
| Backup / data extraction | `@xml/backup_rules`, `@xml/data_extraction_rules` |
| Split types required | `base__abi`, `base__density` |

Key `<meta-data>` entries (VERIFIED):
- `AF_STORE` = `googleplay` (attribution/AppsFlyer store flag)
- `com.google.android.geo.API_KEY` = `@string/google_maps_key` (Google Maps API key)
- `com.google.android.gms.wallet.api.enabled` = `true` (Google Wallet/Pay)
- `com.facebook.sdk.ApplicationId` / `com.facebook.sdk.ClientToken`
- `BRAZE_API_KEY`, `BRAZE_CUSTOM_ENDPOINT` (Braze push/analytics)
- `firebase_analytics_collection_enabled` = `false`
- `asset_statements` = `@string/asset_statements` (App Links verification)
- `io.sentry.auto-init` = `false`; `io.sentry.gradle-plugin-integrations` = AppStart/Compose/Database/FileIO/Logcat/OkHttp
- `com.google.android.gms.version` = Google Play services version

### Application class linkage (VERIFIED)
`ee.mtakso.client.BoltApplication` exists in DEX. JADX metadata shows it extends the framework `Application` and owns DI/infra fields: `ee.mtakso.client.appinit.AppStartupInitializationDelegate`, `ee.mtakso.internal.di.components.a` (DI component), `androidx.work.m0` (WorkManager), `ee.mtakso.client.sentry.e` (Sentry), `eu.bolt.performance.tracing.PerformanceTrace`. Methods include `onCreate`, `attachBaseContext`, `onTrimMemory`, `onConfigurationChanged`. This confirms the app uses a Dagger-style DI graph, Sentry, and WorkManager from the application entry point.

---

## 2. Permissions (VERIFIED — names read from manifest)

### Runtime / dangerous permissions
`INTERNET`, `CAMERA`, `RECORD_AUDIO`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `READ_CALENDAR`, `WRITE_CALENDAR`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_ADVERTISE`, `BLUETOOTH` (≤SDK30), `BLUETOOTH_ADMIN` (≤SDK30), `NFC`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`.

### Foreground-service permissions
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_PHONE_CALL`, `USE_FULL_SCREEN_INTENT`, `MANAGE_OWN_CALLS`, `MODIFY_AUDIO_SETTINGS`.

### Other notable permissions
`RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `VIBRATE`, `GET_PACKAGE_SIZE`, `com.android.vending.CHECK_LICENSE`, `com.google.android.c2dm.permission.RECEIVE` (FCM), `BIND_GET_INSTALL_REFERRER_SERVICE`, `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE`, `com.google.android.providers.gsf.permission.READ_GSERVICES`, `com.google.android.gms.permission.AD_ID` (advertising ID).

### Custom permission (VERIFIED)
```xml
<permission android:name="ee.mtakso.client.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
            android:protectionLevel="signature"/>
```
Declared `signature` protection and also requested by the app itself (`<uses-permission>`). This is a self-defined permission for internal dynamic receivers.

### `uses-permission-sdk-23` (VERIFIED)
`ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` (legacy location grant on API ≥23).

### Package-visibility `<queries>` (VERIFIED)
Declares visibility into: `com.google.android.apps.maps`, `com.huawei.maps.app`, `com.waze`, `com.whatsapp`, `com.whatsapp.w4b`, `com.bolt.deliveryclient`, `ee.hopp.client`, `com.google.android.calendar`, `com.sec.android.app.samsungapps`, `com.facebook.katana`, `com.instagram.android`; queried providers `com.facebook.katana.provider.PlatformProvider`, `com.facebook.orca.provider.PlatformProvider`; `VIEW`/`BROWSABLE` `https`+`http`; and `com.singular.preinstall.READ_PERMISSION_SINGULAR` (Singular attribution).

---

## 3. Activities (VERIFIED — manifest declarations)

| Class | Exported | Notes |
|---|---|---|
| `ee.mtakso.client.newbase.RideHailingMapActivity` | **true** | Main map/ride-hailing activity; `singleTop`, portrait |
| `ee.mtakso.client.activity.SplashHomeActivity` (activity-alias → `RideHailingMapActivity`) | **true** | Launcher entry (`MAIN`/`LAUNCHER`), app shortcuts, MLKit barcode |
| `ee.mtakso.client.newbase.voip.VoipTrampolineActivity` | **true** | `singleTask`, `noHistory` |
| `ee.mtakso.client.newbase.deeplink.DeeplinkActivity` | **true** | `singleTask`, `noHistory`; deep-link handler |
| `ee.mtakso.client.newbase.deeplink.attribution.AttributionDeeplinkActivity` | **true** | `bolt.sng.link` attribution links |
| `ee.mtakso.client.activity.ThreeDSActivity` | **false** (default) | 3-D Secure payment flow |
| `com.facebook.CustomTabActivity` | **true** | `fbconnect://cct.ee.mtakso.client` (FB SDK) |
| `com.facebook.FacebookActivity` | false (default) | FB login UI |
| `com.facebook.CustomTabMainActivity` | false (default) | FB SDK |
| `com.braze.ui.BrazeWebViewActivity` | false | Braze |
| `com.braze.ui.activities.BrazeFeedActivity` | false | Braze |
| `com.braze.ui.activities.ContentCardsActivity` | false | Braze |
| `com.braze.push.NotificationTrampolineActivity` | false | Push trampoline |
| `androidx.credentials.playservices.HiddenActivity` | false | Credential Manager |
| `com.google.android.gms.auth.api.signin.internal.SignInHubActivity` | false | Google Sign-In |
| `com.google.android.gms.common.api.GoogleApiActivity` | false | GMS resolution |
| `com.google.android.play.core.common.PlayCoreDialogWrapperActivity` | false | Play Core |

First-party class existence confirmed via JADX: `ee.mtakso.client.newbase.RideHailingMapActivity`, `ee.mtakso.client.newbase.deeplink.DeeplinkActivity`, `ee.mtakso.client.newbase.deeplink.attribution.AttributionDeeplinkActivity`, `ee.mtakso.client.activity.ThreeDSActivity` (VERIFIED).

---

## 4. Services (VERIFIED — manifest declarations)

| Class | Exported | Foreground type | Notes |
|---|---|---|---|
| `eu.bolt.service.CrossAppLoginService` | **true** | — | Action `ee.mtakso.client.action.BIND_AUTH_TOKEN_SERVICE` (auth token binding) |
| `ee.mtakso.client.ribs.root.ridehailing.safetytoolkit.sosintegration.service.IncidentReportingService` | false | **location** | Safety/SOS incident reporting |
| `ee.mtakso.client.ribs.root.ridehailing.safetytoolkit.audiorecording.service.TripAudioRecordingService` | false | **microphone** | Trip audio recording |
| `eu.bolt.voip.service.VoipService` | false (default) | **phoneCall** | VOIP calls (see §8) |
| `ee.mtakso.client.fcm.FcmListenerService` | false | — | FCM `MESSAGING_EVENT` + `INSTANCE_ID_EVENT` |
| `com.sinch.android.rtc.internal.client.fcm.InstanceIDTokenService` | **true** | — | Sinch VOIP token refresh |
| `androidx.work.impl.background.systemjob.SystemJobService` | **true** | — | `BIND_JOB_SERVICE` permission |
| `androidx.work.impl.background.systemalarm.SystemAlarmService` | false | — | WorkManager |
| `androidx.work.impl.foreground.SystemForegroundService` | false | — | WorkManager FGS |
| `com.google.android.gms.auth.api.signin.RevocationBoundService` | **true** | — | `REVOCATION_NOTIFICATION` permission |
| `com.google.firebase.messaging.FirebaseMessagingService` | false | — | FCM |
| `com.google.mlkit.common.internal.MlKitComponentDiscoveryService` | false | — | ML Kit (barcode/face/text) |
| `com.google.firebase.components.ComponentDiscoveryService` | false | — | Firebase |
| `androidx.room.MultiInstanceInvalidationService` | false | — | Room DB |
| `androidx.camera.core.impl.MetadataHolderService` | false | — | CameraX |
| `com.google.android.gms.measurement.AppMeasurementService` / `AppMeasurementJobService` | false | — | Firebase Analytics |
| `com.google.firebase.sessions.SessionLifecycleService` | false | — | Firebase Sessions |
| `com.google.android.datatransport.runtime.backends.TransportBackendDiscovery` | false | — | DataTransport |
| `com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService` | false | — | `BIND_JOB_SERVICE` |

First-party class existence confirmed via JADX (VERIFIED): `eu.bolt.service.CrossAppLoginService`, `ee.mtakso.client.ribs.root.ridehailing.safetytoolkit.sosintegration.service.IncidentReportingService`, `ee.mtakso.client.ribs.root.ridehailing.safetytoolkit.audiorecording.service.TripAudioRecordingService`, `ee.mtakso.client.fcm.FcmListenerService`.

---

## 5. Broadcast receivers (VERIFIED — manifest declarations)

| Class | Exported | Intent filter |
|---|---|---|
| `ee.mtakso.client.notifications.SignupNotificationUpdateReceiver` | **true** | `BOOT_COMPLETED` |
| `eu.bolt.client.otp.receiver.OtpCodeReceiver` | **true** | `com.whatsapp.otp.OTP_RETRIEVED` |
| `com.google.firebase.iid.FirebaseInstanceIdReceiver` | **true** | `com.google.android.c2dm.intent.RECEIVE` (permission `com.google.android.c2dm.permission.SEND`) |
| `androidx.work.impl.diagnostics.DiagnosticsReceiver` | **true** | `androidx.work.diagnostics.REQUEST_DIAGNOSTICS` (permission `DUMP`) |
| `androidx.profileinstaller.ProfileInstallReceiver` | **true** | Profile install actions (permission `DUMP`) |
| `eu.bolt.client.geofencing.GeofencingBroadcastReceiver` | false (default) | (geofence) |
| `eu.bolt.ridehailing.domain.liveactivity.receiver.DismissedLiveActivityReceiver` | false | Live Activity |
| `eu.bolt.ridehailing.domain.liveactivity.receiver.LiveActivitySkipTipsReceiver` | false | Live Activity |
| `eu.bolt.client.chat.notifications.NotificationDeleteIntentReceiver` | false | Chat notifications |
| `eu.bolt.client.carsharing.receiver.DismissedOrderLiveActivityReceiver` | false | Car-sharing Live Activity |
| `eu.bolt.client.micromobility.liveactivity.receiver.DismissedOrderLiveActivityReceiver` | false | Micromobility Live Activity |
| `com.braze.push.BrazePushReceiver` | false | Braze push |
| `com.facebook.CurrentAccessTokenExpirationBroadcastReceiver` | false | FB access token |
| `com.facebook.AuthenticationTokenManager.CurrentAuthenticationTokenChangedBroadcastReceiver` | false | FB auth token |
| `com.google.android.gms.measurement.AppMeasurementReceiver` | false | Firebase Analytics |
| WorkManager constraint proxies (5 receivers) | false | Power/battery/storage/network/reschedule |
| `com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver` | false | DataTransport |

First-party class existence confirmed via JADX (VERIFIED): `eu.bolt.client.otp.receiver.OtpCodeReceiver`.

---

## 6. Content providers (VERIFIED — manifest declarations)

| Class | Exported | Authorities |
|---|---|---|
| `com.facebook.FacebookContentProvider` | **true** | `com.facebook.app.FacebookContentProvideree.mtakso.client` |
| `androidx.startup.InitializationProvider` | false | `ee.mtakso.client.androidx-startup` |
| `androidx.core.content.FileProvider` | false | `ee.mtakso.client.images.fileprovider` (`grantUriPermissions=true`) |
| `com.facebook.internal.FacebookInitProvider` | false | `ee.mtakso.client.FacebookInitProvider` |
| `com.google.mlkit.common.internal.MlKitInitProvider` | false | `ee.mtakso.client.mlkitinitprovider` |
| `com.google.firebase.provider.FirebaseInitProvider` | false | `ee.mtakso.client.firebaseinitprovider` |
| `io.sentry.android.core.SentryPerformanceProvider` | false | `ee.mtakso.client.SentryPerformanceProvider` |

---

## 7. Exported components & protection levels (VERIFIED)

**Exported = `true` (implicitly or explicitly):**

| Component | Type | Protection |
|---|---|---|
| `ee.mtakso.client.newbase.RideHailingMapActivity` | Activity | none |
| `ee.mtakso.client.activity.SplashHomeActivity` | Activity-alias | none |
| `ee.mtakso.client.newbase.voip.VoipTrampolineActivity` | Activity | none |
| `ee.mtakso.client.newbase.deeplink.DeeplinkActivity` | Activity | none |
| `ee.mtakso.client.newbase.deeplink.attribution.AttributionDeeplinkActivity` | Activity | none |
| `com.facebook.CustomTabActivity` | Activity | none |
| `eu.bolt.service.CrossAppLoginService` | Service | none (action-scoped binding) |
| `androidx.work.impl.background.systemjob.SystemJobService` | Service | `android.permission.BIND_JOB_SERVICE` |
| `com.sinch.android.rtc.internal.client.fcm.InstanceIDTokenService` | Service | none |
| `com.google.android.gms.auth.api.signin.RevocationBoundService` | Service | `…REVOCATION_NOTIFICATION` |
| `ee.mtakso.client.notifications.SignupNotificationUpdateReceiver` | Receiver | none |
| `eu.bolt.client.otp.receiver.OtpCodeReceiver` | Receiver | none |
| `com.google.firebase.iid.FirebaseInstanceIdReceiver` | Receiver | `com.google.android.c2dm.permission.SEND` |
| `androidx.work.impl.diagnostics.DiagnosticsReceiver` | Receiver | `android.permission.DUMP` |
| `androidx.profileinstaller.ProfileInstallReceiver` | Receiver | `android.permission.DUMP` |
| `com.facebook.FacebookContentProvider` | Provider | none |

**Note:** The app's only custom permission is `ee.mtakso.client.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (`signature`). No first-party component is protected by a custom permission; exported first-party activities/services/receivers rely on intent-filter scoping or the Android platform's exported-component rules rather than a custom signature permission.

---

## 8. Foreground services & location declarations

### Foreground services (VERIFIED)
- `IncidentReportingService` — `foregroundServiceType="location"` (exported=false)
- `TripAudioRecordingService` — `foregroundServiceType="microphone"` (exported=false)
- `eu.bolt.voip.service.VoipService` — `foregroundServiceType="phoneCall"` (no `exported` → false)
- `androidx.work.impl.foreground.SystemForegroundService` — WorkManager (no explicit type)

### Location-related (VERIFIED)
- Permissions: `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` (+ `uses-permission-sdk-23`).
- `BLUETOOTH_SCAN` with `neverForLocation`.
- `eu.bolt.client.geofencing.GeofencingBroadcastReceiver` (geofencing).
- `IncidentReportingService` location FGS; its class references `ObserveLocationUpdatesUseCase`, `LatLngModel`, `LocationPermissionProvider` (VERIFIED via JADX).
- Deep-link `geo:` scheme on `DeeplinkActivity`.
- Google Maps API key meta-data + map activity (`RideHailingMapActivity`).

### Safety/SOS linkage (VERIFIED via JADX)
`IncidentReportingService` fields confirm the safety-toolkit wiring: `eu.bolt.rhsafety.core.domain.interactor.ObserveIncidentUseCase`, `UpdateIncidentUseCase`, `ObserveLocationUpdatesUseCase`, `LocationPermissionProvider`, `LatLngModel`, plus `onStartCommand`/`onCreate`/`onDestroy` lifecycle and a `PendingIntent` provider. This is the SOS/incident-reporting location foreground service.

`TripAudioRecordingService` fields confirm trip audio recording: `eu.bolt.ridehailing.core.domain.interactor.order.ObserveOrderStateUseCase`, `eu.bolt.rhsafety.domain.interactor.UpdateAudioRecordingStateUseCase`, `kotlinx.coroutines.CoroutineScope`, with `onBind`/`onCreate`/`onDestroy`.

### VOIP linkage (UNKNOWN)
The manifest declares `eu.bolt.voip.service.VoipService` with `foregroundServiceType="phoneCall"`, but JADX finds **no class** in package `eu.bolt.voip` (search `eu.bolt.voip` returned 0 matches). This suggests the VOIP service class is either provided by a dynamic-feature module not present in `base.apk`, obfuscated, or resolved at runtime. The Sinch SDK is present (`com.sinch.android.rtc.internal.client.fcm.InstanceIDTokenService`, VERIFIED), so VOIP capability is clearly wired, but the concrete `VoipService` class could not be resolved in this artifact.

---

## 9. Notification / authentication / mapping / payment components

### Notification (VERIFIED manifest; INFERRED purpose)
- `ee.mtakso.client.notifications.SignupNotificationUpdateReceiver` (BOOT_COMPLETED)
- `eu.bolt.client.chat.notifications.NotificationDeleteIntentReceiver`
- Live-Activity receivers: `DismissedLiveActivityReceiver`, `LiveActivitySkipTipsReceiver`, car-sharing & micromobility `DismissedOrderLiveActivityReceiver`
- Push: `ee.mtakso.client.fcm.FcmListenerService`, `FirebaseMessagingService`, `FirebaseInstanceIdReceiver`, `com.braze.push.BrazePushReceiver`, `NotificationTrampolineActivity`
- Permissions: `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`

### Authentication (VERIFIED manifest; INFERRED purpose)
- `eu.bolt.service.CrossAppLoginService` — auth token binding; class fields `eu.bolt.client.login.data.AuthPreferenceController`, `eu.bolt.client.crossapplogin.c` (VERIFIED via JADX) → cross-app/shared login.
- `eu.bolt.client.otp.receiver.OtpCodeReceiver` — WhatsApp OTP retrieval (`com.whatsapp.otp.OTP_RETRIEVED`).
- `ee.mtakso.client.activity.ThreeDSActivity` — 3-D Secure (payment/authentication challenge).
- Facebook SDK: `FacebookActivity`, `FacebookContentProvider`, `FacebookInitProvider`, token receivers.
- Google Sign-In: `SignInHubActivity`, `RevocationBoundService`.
- Credential Manager: `androidx.credentials.playservices.CredentialProviderMetadataHolder`, `HiddenActivity`.
- Biometrics: `USE_BIOMETRIC`, `USE_FINGERPRINT`.

### Mapping (VERIFIED manifest; INFERRED purpose)
- `ee.mtakso.client.newbase.RideHailingMapActivity` (map screen).
- `com.google.android.geo.API_KEY` meta-data (Google Maps).
- `<queries>` into Google Maps, Huawei Maps, Waze.
- `geo:` deep-link scheme.

### Payment (VERIFIED manifest; INFERRED purpose)
- `ee.mtakso.client.activity.ThreeDSActivity` (3-D Secure).
- `com.google.android.gms.wallet.api.enabled` = `true` (Google Wallet/Pay).
- `com.android.vending.CHECK_LICENSE`.
- `AF_STORE` = `googleplay`.

---

## 10. Deep links & intent filters (VERIFIED)

`DeeplinkActivity` handles:
- `taxify://action`, `bolt://action` (App Links, `autoVerify`)
- `https://scooters.taxify.eu` (`autoVerify`)
- NFC `NDEF_DISCOVERED`: `boltprelive://action`, `bolt://action`, `taxify://action`, `https://scooters.taxify.eu/qr`
- `VIEW`/`BROWSABLE` with schemes `taxify`, `bolt`, `geo`
- `http(s)://maps.google.com` (`autoVerify`)

`AttributionDeeplinkActivity` handles `http(s)://bolt.sng.link` with path prefixes `/A`, `/B`, `/E`, `/F`.

`CustomTabActivity` handles `fbconnect://cct.ee.mtakso.client`.

---

## 11. Limitations

- Static-only analysis: no runtime behaviour, no network, no signature verification (`signature_verification: not_performed`).
- `eu.bolt.voip.service.VoipService` declared in manifest but not found in `base.apk` DEX (UNKNOWN).
- Component purposes marked INFERRED are based on package/class naming and dependency types, not decompiled method bodies.
- APK is a **split** (`base__abi`, `base__density`); sibling splits (`split_config.*.apk`) and any dynamic-feature modules were **not** analyzed. Some manifest-declared components may resolve from other split/feature modules.
- JADX "parsed_members" metadata scope does not guarantee complete method-body coverage; method signatures shown are display types.
- No decompilation of receiver/service business logic was performed in this phase.
