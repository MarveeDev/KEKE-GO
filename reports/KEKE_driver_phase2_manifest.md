# BOLT Driver — Phase 2: Manifest & Component Analysis

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`, minSdk 26, targetSdk 36
**Tooling:** REA MCP + JADX headless 0.7.1 (full decoded `AndroidManifest.xml`, 40,588 UTF-16 code units), Phase 1 archive inventory.
**Scope:** Read-only. No APK modification, no runtime, no signature verification (`signature_verification: not_performed`).

Confidence labels:
- **VERIFIED** — read directly from the decoded manifest.
- **INFERRED** — deduced from naming/contents; not proven by runtime.
- **UNKNOWN** — not resolvable from static evidence.

Backend behaviour is never claimed; this is a manifest/static-component analysis only.

---

## 1. Android Components

### 1.1 Activities (VERIFIED)
| Class | Exported | Notes |
|---|---|---|
| `ee.mtakso.driver.ui.screens.launch.LauncherActivity` | **true** | Launcher (`MAIN`/`LAUNCHER`); deep links `boltdriverapp://`, `taxifydriverapp://`, `https://boltdriver.sng.link` (autoVerify), `https://bolt.eu` |
| `ee.mtakso.driver.ui.screens.order.incoming.v2.IncomingOrderActivity` | false (default) | Incoming ride offer |
| `ee.mtakso.driver.ui.screens.destination.rib.activity.DestinationRibActivity` | false | Destination (RIB) |
| `ee.mtakso.driver.ui.screens.contact_methods.voip.VoipFloatingActivity` | false | Floating VOIP overlay (`Theme.Transparent.Floating`) |
| `ee.mtakso.driver.ui.base.CloseActivity` | false | Transparent close |
| `ee.mtakso.driver.ui.screens.order.v2.ActiveRideActivity` | false | Active ride |
| `ee.mtakso.driver.ui.screens.SimpleActivity` | false | — |
| `ee.mtakso.driver.ui.screens.NavigationActivity` | false | Turn-by-turn navigation |
| `ee.mtakso.driver.ui.screens.login.LoginActivity` | false | Login |
| `ee.mtakso.driver.ui.screens.ribs.activity.RootRibActivity` | false | RIBs root |
| `eu.bolt.driver.chat.ui.screen.conversation.ConversationActivity` | false | In-app chat |
| `eu.bolt.driver.core.ui.common.activity.SimpleAuthorisedActivity` | false | Authorised shell |
| `eu.bolt.verification.sdk.VerificationSDKActivity` | false | Identity/document verification |
| `com.facebook.CustomTabActivity` | **true** | `fbconnect://cct.ee.mtakso.driver` |
| `com.facebook.FacebookActivity`, `com.facebook.CustomTabMainActivity` | false | Facebook SDK |
| `com.google.android.gms.auth.api.signin.internal.SignInHubActivity` | false | Google Sign-In |
| `com.google.android.gms.common.api.GoogleApiActivity` | false | GMS resolution |
| `com.google.android.play.core.common.PlayCoreDialogWrapperActivity` | false | Play Core |
| `com.braze.ui.BrazeWebViewActivity`, `BrazeFeedActivity`, `ContentCardsActivity`, `com.braze.push.NotificationTrampolineActivity` | false | Braze |
| `androidx.credentials.playservices.HiddenActivity`, `IdentityCredentialApiHiddenActivity` | false | Credential Manager |
| `com.mixpanel.android.mpmetrics.MixpanelNotificationRouteActivity` | false | Mixpanel |

### 1.2 Services (VERIFIED)
| Class | Exported | Foreground type / permission |
|---|---|---|
| `ee.mtakso.driver.service.AwakeService` | false | `location` (online/offline presence) |
| `ee.mtakso.driver.ui.screens.contact_methods.voip.service.VoipIntentService` | false | `microphone` |
| `ee.mtakso.driver.module.feature.audio_recording.service.AudioRecordingForegroundService` | false | `microphone` |
| `ee.mtakso.driver.platform.google.push.FirebasePushService` | false | FCM `MESSAGING_EVENT` |
| `com.sinch.android.rtc.internal.client.fcm.InstanceIDTokenService` | **true** | `INSTANCE_ID_EVENT` |
| `com.google.android.gms.auth.api.signin.RevocationBoundService` | **true** | `…REVOCATION_NOTIFICATION` |
| `androidx.work.impl.background.systemjob.SystemJobService` | **true** | `BIND_JOB_SERVICE` |
| `androidx.work.impl.background.systemalarm.SystemAlarmService` | false | WorkManager |
| `androidx.work.impl.foreground.SystemForegroundService` | false | WorkManager |
| `com.google.firebase.messaging.FirebaseMessagingService` | false | FCM |
| `com.google.firebase.components.ComponentDiscoveryService` | false | Firebase |
| `com.google.firebase.sessions.SessionLifecycleService` | false | Firebase Sessions |
| `com.google.mlkit.common.internal.MlKitComponentDiscoveryService` | false | ML Kit |
| `androidx.camera.core.impl.MetadataHolderService` | false | CameraX |
| `androidx.credentials.playservices.CredentialProviderMetadataHolder` | false | Credential Manager |
| `com.google.android.gms.measurement.AppMeasurementService` / `AppMeasurementJobService` | false | Firebase Analytics |
| `androidx.room.MultiInstanceInvalidationService` | false | Room |
| `com.google.android.datatransport.runtime.backends.TransportBackendDiscovery` | false | DataTransport |
| `com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService` | false | `BIND_JOB_SERVICE` |

### 1.3 Broadcast receivers (VERIFIED)
| Class | Exported | Intent filter |
|---|---|---|
| `ee.mtakso.driver.service.integration.whatsapp.WhatsAppOtpCodeBroadcastReceiver` | **true** | `com.whatsapp.otp.OTP_RETRIEVED` |
| `ee.mtakso.driver.platform.google.autofill.GmsSmsListener` | **true** | `com.google.android.gms.auth.api.phone.SMS_RETRIEVED` (permission `…phone.permission.SEND`) |
| `com.google.firebase.iid.FirebaseInstanceIdReceiver` | **true** | `com.google.android.c2dm.intent.RECEIVE` (permission `c2dm.SEND`) |
| `androidx.work.impl.diagnostics.DiagnosticsReceiver` | **true** | `REQUEST_DIAGNOSTICS` (permission `DUMP`) |
| `androidx.profileinstaller.ProfileInstallReceiver` | **true** | profile install (permission `DUMP`) |
| `ee.mtakso.driver.service.integration.braze.BrazeNotificationBroadcastReceiver` | false | Braze `NOTIFICATION_OPENED/RECEIVED/DELETED` |
| `eu.bolt.driver.chat.ui.notification.DeleteNotificationReceiver` | false | chat notification delete |
| `com.mapbox.common.location.LocationUpdatesReceiver` | false | Mapbox location updates |
| `com.facebook.CurrentAccessTokenExpirationBroadcastReceiver` | false | FB token |
| `com.facebook.AuthenticationTokenManager.CurrentAuthenticationTokenChangedBroadcastReceiver` | false | FB auth token |
| `com.braze.push.BrazePushReceiver` | false | Braze push |
| `com.braze.BrazeFlushPushDeliveryReceiver` | false | `FLUSH_EVENTS` |
| `com.google.android.gms.measurement.AppMeasurementReceiver` | false | Firebase Analytics |
| `com.mixpanel.android.mpmetrics.MixpanelPushNotificationDismissedReceiver` | false (default) | Mixpanel |
| WorkManager receivers (ForceStop, 4× ConstraintProxy, Reschedule, ConstraintProxyUpdate) | false | power/battery/storage/network |
| `com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver` | false | DataTransport |

### 1.4 Content providers (VERIFIED)
| Class | Exported | Authorities |
|---|---|---|
| `androidx.core.content.FileProvider` | false | `ee.mtakso.driver.fileprovider` (`grantUriPermissions=true`, `@xml/documents_scanner_paths`) |
| `androidx.startup.InitializationProvider` | false | `ee.mtakso.driver.androidx-startup` |
| `com.google.firebase.provider.FirebaseInitProvider` | false | `ee.mtakso.driver.firebaseinitprovider` |
| `com.google.mlkit.common.internal.MlKitInitProvider` | false | `ee.mtakso.driver.mlkitinitprovider` |
| `com.facebook.internal.FacebookInitProvider` | false | `ee.mtakso.driver.FacebookInitProvider` |
| `io.sentry.android.core.SentryPerformanceProvider` | false | `ee.mtakso.driver.SentryPerformanceProvider` |

### 1.5 Exported components (VERIFIED — `android:exported="true"`)
| Component | Type | Protection |
|---|---|---|
| `LauncherActivity` | Activity | none (launcher + deep links) |
| `com.facebook.CustomTabActivity` | Activity | none |
| `WhatsAppOtpCodeBroadcastReceiver` | Receiver | none (WhatsApp OTP action) |
| `GmsSmsListener` | Receiver | `com.google.android.gms.auth.api.phone.permission.SEND` |
| `FirebaseInstanceIdReceiver` | Receiver | `com.google.android.c2dm.permission.SEND` |
| `RevocationBoundService` | Service | `…signin.permission.REVOCATION_NOTIFICATION` |
| `SystemJobService` | Service | `android.permission.BIND_JOB_SERVICE` |
| `sinch InstanceIDTokenService` | Service | none |
| WorkManager `DiagnosticsReceiver` | Receiver | `android.permission.DUMP` |
| `ProfileInstallReceiver` | Receiver | `android.permission.DUMP` |

No first-party activity/service/receiver is protected by the app's custom permissions; the exported first-party `LauncherActivity` and `WhatsAppOtpCodeBroadcastReceiver` rely on intent-action/scheme scoping and platform rules.

### 1.6 Intent filters & deep links (VERIFIED)
- Launcher: `MAIN` + `LAUNCHER` + `DEFAULT`.
- Custom schemes: `boltdriverapp://`, `taxifydriverapp://` (`VIEW`/`BROWSABLE`).
- App Links (autoVerify): `http(s)://boltdriver.sng.link`; also `http(s)://bolt.eu` (no autoVerify).
- Facebook: `fbconnect://cct.ee.mtakso.driver`.

---

## 2. Location & Background Execution

### 2.1 Location permissions (VERIFIED)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (+ `uses-permission-sdk-23` variants).
- **`ACCESS_BACKGROUND_LOCATION` — declared** (VERIFIED). This distinguishes the Driver app from Passenger (which did **not** declare it). The driver requires background location (e.g. online/offline presence while app is backgrounded).

### 2.2 Foreground services (VERIFIED)
- `AwakeService` — `foregroundServiceType="location"`.
- `VoipIntentService` — `foregroundServiceType="microphone"`.
- `AudioRecordingForegroundService` — `foregroundServiceType="microphone"`.
- `androidx.work.impl.foreground.SystemForegroundService` — WorkManager FGS.
- Supporting permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_MICROPHONE`.

### 2.3 Background execution mechanisms (VERIFIED)
- **WorkManager** — `SystemAlarmService`, `SystemJobService`, `SystemForegroundService`, plus `WorkManagerInitializer` startup initializer and constraint-proxy receivers.
- **Boot receiver** — `RECEIVE_BOOT_COMPLETED` permission is declared; WorkManager `RescheduleReceiver` handles `BOOT_COMPLETED`/`TIME_SET`/`TIMEZONE_CHANGED`.
- **Mapbox location** — `com.mapbox.common.location.LocationUpdatesReceiver` (location updates processing).
- **AlarmManager** (DataTransport) — `AlarmManagerSchedulerBroadcastReceiver`, `JobInfoSchedulerService`.
- **Wake locks** — `WAKE_LOCK` permission.

Note (UNKNOWN): the specific scheduling cadence/foreground-service keep-alive logic for driver presence is not determinable from the manifest alone.

---

## 3. Driver Communication

### 3.1 VoIP (VERIFIED)
- `VoipFloatingActivity` (`Theme.Transparent.Floating` — overlay call UI).
- `VoipIntentService` (`foregroundServiceType="microphone"`).
- Sinch SDK: `com.sinch.android.rtc.internal.client.fcm.InstanceIDTokenService` + native `libsinch-android-rtc.so` (Phase 1).
- `MODIFY_AUDIO_SETTINGS` permission.

### 3.2 Microphone / audio (VERIFIED)
- `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`.
- `AudioRecordingForegroundService` (`microphone` FGS) — trip audio recording.
- `FOREGROUND_SERVICE_MICROPHONE`.

### 3.3 Notifications (VERIFIED)
- `POST_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT`, `ACCESS_NOTIFICATION_POLICY`.
- Firebase push: `FirebasePushService`, `FirebaseMessagingService`, `FirebaseInstanceIdReceiver`, meta-data `com.google.firebase.messaging.default_notification_icon`.
- Braze: `BrazePushReceiver`, `BrazeNotificationBroadcastReceiver`, `BrazeFlushPushDeliveryReceiver`, `NotificationTrampolineActivity`.
- Mixpanel push: `MixpanelPushNotificationDismissedReceiver`, `MixpanelNotificationRouteActivity`.
- Chat: `DeleteNotificationReceiver`.
- In-app notification manager: `UiNotificationManagerInitializer` (startup).

---

## 4. Driver Onboarding & Security

### 4.1 Camera & document verification (VERIFIED)
- `CAMERA` permission; `uses-feature android.hardware.camera` (required=false).
- `eu.bolt.verification.sdk.VerificationSDKActivity`.
- `androidx.core.content.FileProvider` with `@xml/documents_scanner_paths` — document scanning.
- Phase 1 assets confirm on-device verification models: `veritas_document_detector_v1.tflite` (document detector), `models_bundled/` (BlazeFace/FSSD face + eye-closed liveness), `mlkit-google-ocr-models/` (OCR).
- CameraX: `MetadataHolderService` + Camera2 default config.
- **INFERRED**: onboarding flow captures identity documents (camera + document scanner) and performs face/liveness + OCR verification on-device, supported by the `eu.bolt.verification.sdk`.

### 4.2 Biometric & authentication (VERIFIED)
- `USE_BIOMETRIC`, `USE_FINGERPRINT`.
- Google Sign-In (`SignInHubActivity`, `RevocationBoundService`), Facebook SDK, androidx Credential Manager (`CredentialProviderMetadataHolder`, `HiddenActivity`, `IdentityCredentialApiHiddenActivity`), FIDO/identity-credentials (`play-services-fido`, `identity-credentials.properties`, Phase 1).
- OTP auto-retrieve: `GmsSmsListener` (SMS) + `WhatsAppOtpCodeBroadcastReceiver` (WhatsApp).

### 4.3 Play Integrity (VERIFIED presence; INFERRED usage)
- `integrity.properties` (Phase 1 assets) indicates the Play Integrity API is bundled. No explicit manifest meta-data for integrity; runtime use is **INFERRED** (e.g. device attestation during onboarding/login).

### 4.4 Overlay & package visibility (VERIFIED)
- `SYSTEM_ALERT_WINDOW` (overlay) — supports `VoipFloatingActivity` / incoming-order overlay.
- `PACKAGE_USAGE_STATS` (usage access).
- `<queries>` package visibility (VERIFIED) targets: `ee.mtakso.client` (Passenger app), `ee.hopp.client`, OEM power/battery managers (miui, letv, asus, huawei, coloros, iqoo, evenwell, meizu, oppo), `cityguide.probki.net`, navigation apps (`com.google.android.apps.maps`, `com.mapswithme.maps.pro`, `ru.dublgis.dgismobile`, `com.waze`, `ru.yandex.yandexmaps`, `ru.yandex.yandexnavi`), WhatsApp, Facebook, Instagram; intents `MAIN`, `SEND` (email/text), `CustomTabsService`, `PICK` (phone), `TTS_SERVICE`, `VIEW http/https`, speech `RecognitionService`, Singular preinstall.
- **INFERRED**: the OEM-manager queries indicate a battery-optimisation whitelisting flow (keeps the driver online); navigation-app queries support external-navigation handoff.

---

## 5. Application Configuration

### 5.1 Application class (VERIFIED)
- `android:name="ee.mtakso.App"`, `allowBackup="false"`, `extractNativeLibs="true"`, `largeHeap="true"`, `supportsRtl="true"`, `hardwareAccelerated="true"`.
- `networkSecurityConfig="@xml/network_security_config"`.
- `appComponentFactory="androidx.core.app.CoreComponentFactory"`.

### 5.2 Dependency initialization (VERIFIED)
`androidx.startup.InitializationProvider` registers custom initializers:
`AssertionInitializer`, `AnalyticsInitializer`, `BoltMoneyInitializer`, `CrashlyticsInitializer`, `DaggerInitializer` (DI graph), `GooglePlayServicesInitializer`, `LogManagerInitializer`, `WorkManagerInitializer`, `StrictModeInitializer`, `UiNotificationManagerInitializer`, `EmojiInitializer`, plus `ProcessLifecycleInitializer`, `ProfileInstallerInitializer`, `SettingsInitializer` (russhwolf multiplatform-settings), `okhttp3.internal.platform.PlatformInitializer`.

### 5.3 Firebase configuration (VERIFIED)
- Meta-data flags: `firebase_performance_logcat_enabled=false`, `firebase_crashlytics_collection_enabled=false`, `firebase_analytics_collection_enabled=false`.
- `com.crashlytics.ApiKey` (hardcoded value).
- `com.google.firebase.messaging.default_notification_icon` = `@drawable/ic_notification_24`.
- Firebase registrars in `ComponentDiscoveryService`: Perf, Messaging, IID, Analytics connector, Crashlytics, Remote Config, Sessions, Installations, DataTransport, Abt, FirebaseCommon.
- **UNKNOWN**: `google-services.json` resources are not present as a manifest string; Firebase project config is resolved at build/runtime (client API keys in resources, not enumerated here).

### 5.4 Mapbox & navigation configuration (VERIFIED)
- Mapbox Maps + Common (native libs, `com.mapbox.common.location.LocationUpdatesReceiver`, `sdk_versions/com.mapbox.*` assets, `vector_tile.proto`).
- Ferrostar (`libferrostar.so`, Phase 1) for navigation.
- `com.google.android.geo.API_KEY` = `@string/google_maps_key` (Google Maps key present in addition to Mapbox).
- **UNKNOWN**: Mapbox access-token string is not surfaced in the manifest (injected at runtime or via resources/build config).

### 5.5 Other config (VERIFIED)
- `com.google.android.funnel.API_KEY` (hardcoded UUID) — Google Funnel analytics key.
- Mixpanel config: `com.mixpanel.android.MPConfig.EnableDebugLogging=false`, `MPConfig.ResourcePackageName=ee.mtakso.driver`.
- Facebook `com.facebook.sdk.ApplicationId`.
- Sentry `io.sentry.auto-init=false` + gradle integrations.
- Splits: `com.android.vending.splits.required=true`, `stamp.source` (play store), `stamp.type` (distribution APK), `com.android.vending.derived.apk.id=3`.

---

## 6. Security Review (static; no exploitation)

- **Exported component protection:** 10 exported components identified (§1.5). First-party exported components (`LauncherActivity`, `WhatsAppOtpCodeBroadcastReceiver`) have no custom-permission guard; their attack surface is limited by deep-link scheme/host and the WhatsApp OTP action, respectively. Third-party exported components are protected by their documented permissions (`c2dm.SEND`, `REVOCATION_NOTIFICATION`, `BIND_JOB_SERVICE`, `DUMP`, `…phone.permission.SEND`).
- **Custom permissions (VERIFIED):** `ee.mtakso.driver.MAPS_RECEIVE` (signature) and `ee.mtakso.driver.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (signature). `MAPS_RECEIVE` is declared and requested by the app itself (map push receive).
- **Sensitive exposure (VERIFIED, benign):** `allowBackup="false"` and `dataExtractionRules` reduce data exposure; `FileProvider` is non-exported with `grantUriPermissions` + scoped `documents_scanner_paths`.
- **Hardcoded keys (VERIFIED presence):** `com.google.android.funnel.API_KEY`, `com.crashlytics.ApiKey`, `com.google.android.geo.API_KEY` (@string). These are client-side public SDK keys, not user secrets; presence noted, not exploited.
- **No exploitation or bypass attempted**, per instruction.

---

## 7. Limitations & Unresolved Questions

1. **Signature verification not performed**; APK authenticity not asserted.
2. **Background-location use** (specific keep-alive/geofence schedule) and **foreground-service cadence** are UNKNOWN from the manifest.
3. **Mapbox access token** and **Firebase project config** values are not in the manifest (resources/runtime) — UNKNOWN.
4. **Play Integrity** usage is INFERRED from `integrity.properties`; no runtime path verified.
5. **Verification SDK** (`eu.bolt.verification.sdk`) purpose is INFERRED (document/identity verification) from activity name + camera + bundled model assets; no behavioral verification.
6. Deep-link handling logic (which dispatcher consumes `boltdriverapp://`) is not in the manifest — requires class analysis (later phases).
7. This is a base-APK-only manifest review; split APKs (native libs/density) were covered in Phase 1 inventory.
