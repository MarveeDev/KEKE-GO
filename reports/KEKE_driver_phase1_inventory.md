# BOLT Driver — Phase 1: APK Inventory & Architecture

**Target directory:** `C:\REA-BOLT\artifacts\driver\`
**Tooling:** REA MCP + JADX headless 0.7.1 (package/manifest summary + decoded manifest), plus read-only ZIP enumeration (System.IO.Compression).
**Scope:** Read-only inspection. No APK modification, no runtime, no signature verification (`signature_verification: not_performed`).

Confidence labels:
- **VERIFIED** — directly observed in the decoded manifest, APK archive contents, or JADX metadata.
- **INFERRED** — deduced from naming/contents; not proven by runtime.
- **UNKNOWN** — not resolvable from static evidence.

Comparison baseline: Passenger app (`ee.mtakso.client`, Phase 1–7 of the previous investigation). Only *shared* implementations are treated as confirmed; no assumption that Driver and Passenger share code.

---

## 1. Files inspected

| File | Size (bytes) | SHA-256 |
|---|---|---|
| `base.apk` | 190,018,619 | `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0` |
| `split_config.arm64_v8a.apk` | 24,892,972 | (not digested this phase — see §9) |
| `split_config.xxhdpi.apk` | 4,206,139 | (not digested this phase — see §9) |

---

## 2. Package identity & version (VERIFIED)

| Attribute | Value |
|---|---|
| Package name | `ee.mtakso.driver` |
| versionName | `DA.155.1` |
| versionCode | `941` |
| minSdkVersion | `26` (Android 8.0) |
| targetSdkVersion | `36` |
| compileSdkVersion | `36` |
| Application class | `ee.mtakso.App` |
| Theme / icon | `@style/Theme.Dark` / `@mipmap/ic_launcher` |

Notable application attributes (VERIFIED): `allowBackup="false"`, `extractNativeLibs="true"`, `networkSecurityConfig="@xml/network_security_config"`, `appComponentFactory="androidx.core.app.CoreComponentFactory"`, `fullBackupContent`/`dataExtractionRules="@xml/data_extraction_rules"`.

---

## 3. DEX / classes / resources / native libraries (VERIFIED)

- **DEX files:** 14 (`classes.dex` … `classes14.dex`) in `base.apk`.
- **Classes:** 65,765 (JADX parsed top-level class count).
- **Resources:** 4,605.
- **base.apk total entries:** 4,672.
- **split_config.arm64_v8a.apk** (ABI split): 20 entries, **15 native `.so` files**, 0 DEX.
- **split_config.xxhdpi.apk** (density split): 451 entries, 0 DEX, 0 native libs (density resources only).

### Native libraries (VERIFIED — from `split_config.arm64_v8a.apk`, `lib/arm64-v8a/`)
| Library | Interpretation (INFERRED) |
|---|---|
| `libmapbox-common.so`, `libmapbox-maps.so` | Mapbox Maps SDK |
| `libferrostar.so` | Ferrostar turn-by-turn navigation library |
| `libface_detector_v2_jni.so`, `libimage_processing_util_jni.so`, `libsurface_util_jni.so`, `libmlkit_google_ocr_pipeline.so` | ML Kit vision (face detection, OCR) |
| `libtensorflowlite_jni.so` | TensorFlow Lite |
| `libsinch-android-rtc.so` | Sinch VOIP/RTC |
| `libsentry.so`, `libsentry-android.so` | Sentry crash reporting |
| `libjnidispatch.so` | JNA (native bindings) |
| `libandroidx.graphics.path.so` | AndroidX graphics path (Compose) |
| `libdatastore_shared_counter.so` | DataStore native counter |
| `libc++_shared.so` | C++ runtime |

---

## 4. Language / runtime indicators

- **Kotlin — VERIFIED.** `kotlin/` directory, `kotlin-tooling-metadata.json`, `DebugProbesKt.bin` (kotlinx.coroutines debug probes), and kotlinx.coroutines classes in DEX.
- **Java — VERIFIED** (Android platform + third-party SDK bytecode).
- **Flutter — ABSENT (VERIFIED).** No `libflutter.so`/`libapp.so`, no `flutter_assets`, no Dart snapshot. The app is **not** Flutter.
- **React Native — ABSENT (VERIFIED).** No `libreactnative.so`/`libhermes.so`, no `index.android.bundle`/`assets/` JS bundle.
- **Compose / declarative UI — INFERRED** (`androidx.compose`, `libandroidx.graphics.path.so`).

---

## 5. Major modules & namespaces (VERIFIED from manifest/class names)

- **`ee.mtakso.driver.*`** — primary app namespace:
  - `ee.mtakso.driver.ui.screens.*` — `launch.LauncherActivity`, `order.incoming.v2.IncomingOrderActivity`, `destination.rib.activity.DestinationRibActivity`, `order.v2.ActiveRideActivity`, `NavigationActivity`, `login.LoginActivity`, `ribs.activity.RootRibActivity`, `SimpleActivity`, `contact_methods.voip.VoipFloatingActivity`, `ui.base.CloseActivity`.
  - `ee.mtakso.driver.service.*` — `AwakeService` (location FGS), `integration.braze.*`, `integration.whatsapp.WhatsAppOtpCodeBroadcastReceiver`.
  - `ee.mtakso.driver.platform.google.push.FirebasePushService`, `platform.google.autofill.GmsSmsListener`.
  - `ee.mtakso.driver.module.feature.audio_recording.service.AudioRecordingForegroundService`.
  - `ee.mtakso.driver.startup.*` — `AssertionInitializer`, `AnalyticsInitializer`, `BoltMoneyInitializer`, `CrashlyticsInitializer`, `DaggerInitializer`, `GooglePlayServicesInitializer`, `LogManagerInitializer`, `WorkManagerInitializer`, `StrictModeInitializer`, `UiNotificationManagerInitializer`, `EmojiInitializer`.
- **`eu.bolt.driver.*`** — shared driver core: `chat.ui.screen.conversation.ConversationActivity`, `chat.ui.notification.DeleteNotificationReceiver`, `core.ui.common.activity.SimpleAuthorisedActivity`.
- **`eu.bolt.verification.sdk.*`** — `VerificationSDKActivity` (driver identity/document verification).
- Application class: `ee.mtakso.App`.

### Application architecture (VERIFIED)
- **RIBs (Router-Interactor-Builder/View)** architecture — evidenced by `RootRibActivity`, `DestinationRibActivity`, and `…rib…` naming (consistent with the Passenger app).
- **Dagger dependency injection** — `DaggerInitializer` (explicit startup).
- **Multi-layer package layout**: UI screens (`ui.screens.*`), platform integrations (`platform.google.*`), feature modules (`module.feature.*`), services (`service.*`), startup initializers (`startup.*`).
- **Foreground services** (VERIFIED): `AwakeService` (`foregroundServiceType="location"`), `VoipIntentService` (`microphone`), `AudioRecordingForegroundService` (`microphone`).

---

## 6. Third-party SDKs & integrations

### Maps & navigation (VERIFIED)
- **Mapbox Maps** — `libmapbox-maps.so`/`libmapbox-common.so`, `sdk_versions/com.mapbox.maps*`, `vector_tile.proto`, `com.mapbox.common.location.LocationUpdatesReceiver` (manifest).
- **Ferrostar** — `libferrostar.so` (turn-by-turn navigation).
- **Google Maps (Play Services)** — `play-services-maps.properties`, `com.google.android.geo.API_KEY` meta-data.

### ML / computer vision (VERIFIED)
- **ML Kit** — barcode, face detection, text recognition (`play-services-mlkit-*`, `libmlkit_google_ocr_pipeline.so`, `libface_detector_v2_jni.so`).
- **Bundled models** — `mlkit-google-ocr-models/` (OCR), `models_bundled/` (BlazeFace + FSSD face/liveness models, eye-closed detectors), `veritas_document_detector_v1.tflite` (document detector).
- **TensorFlow Lite** — `libtensorflowlite_jni.so`.
- **Veritas** — `veritas_document_detector_v1.tflite` + `eu.bolt.verification.sdk.VerificationSDKActivity` (INFERRED: identity/document verification for driver onboarding).

### Analytics / crash (VERIFIED)
- **Firebase** — Analytics, Crashlytics, Messaging, Remote Config, Sessions, Installations, Performance (`.properties` + `ComponentDiscoveryService` registrars).
- **Braze** — push + in-app (`BrazePushReceiver`, `BrazeNotificationBroadcastReceiver`, `braze-html-bridge.js`, HTML in-app bridges).
- **Mixpanel** — `com.mixpanel.android.mpmetrics.*`, `MixpanelNotificationRouteActivity`, manifest `com.mixpanel.android.MPConfig.*`.
- **Sentry** — `libsentry*.so`, `SentryPerformanceProvider`, `io.sentry.*` instrumentation.
- **AppsFlyer / Singular** — `com.singular.preinstall.READ_PERMISSION_SINGULAR` query (Singular attribution; INFERRED). `com.android.vending.CHECK_LICENSE`, install-referrer binding.

### Auth / identity / comms (VERIFIED)
- **Google Play Services Auth** — `SignInHubActivity`, `play-services-auth*`, `auth-api-phone` (SMS retrieval — `GmsSmsListener`), `fido` + `identity-credentials` (passkeys), `integrity` (Play Integrity).
- **Facebook SDK** — `FacebookActivity`, `FacebookInitProvider`, token receivers, `fbconnect://cct.ee.mtakso.driver`.
- **Sinch** — `libsinch-android-rtc.so`, `InstanceIDTokenService` (VOIP).
- **WhatsApp OTP** — `WhatsAppOtpCodeBroadcastReceiver` (`com.whatsapp.otp.OTP_RETRIEVED`).

### Other libraries (VERIFIED)
- **OkHttp** (okhttp3), **WorkManager**, **Room**, **CameraX**, **DataStore**, **Compose**, **androidx.credentials** (Credential Manager), **Play Core**, **russhwolf multiplatform-settings** (`SettingsInitializer`), **kotlinx.coroutines**, **Mapbox vector tiles** (`vector_tile.proto`).

---

## 7. Architecture summary (VERIFIED / INFERRED)

The Driver app is a **native Kotlin/Android application** using:
1. **RIBs** navigation/architecture (root + per-screen RIBs), same paradigm as Passenger.
2. **Dagger** DI with explicit `startup.InitializationProvider` initializers.
3. **Mapbox Maps + Ferrostar** as the primary mapping/navigation stack (native `.so`), with **Google Maps Play Services** also bundled (geo API key + maps + likely geocoding/directions fallback).
4. **On-device ML** for driver onboarding verification (document detection via Veritas, face liveness via BlazeFace/FSSD, OCR via ML Kit/TFLite).
5. **Foreground services** for driver online/offline presence (`AwakeService` location FGS) and safety (`AudioRecordingForegroundService` microphone).
6. Heavy **analytics/monitoring** (Firebase + Braze + Mixpanel + Sentry + Singular) — more analytics SDKs than Passenger.
7. **VOIP** via Sinch with a floating VOIP activity and dedicated foreground service.

---

## 8. Driver vs Passenger comparison

| Dimension | Passenger (`ee.mtakso.client`) | Driver (`ee.mtakso.driver`) | Classification |
|---|---|---|---|
| versionName / code | `CA.231.0` / `4400` | `DA.155.1` / `941` | VERIFIED |
| minSdk | 24 | **26** | VERIFIED |
| targetSdk | 36 | 36 | VERIFIED |
| class count | 52,618 | **65,765** | VERIFIED |
| Application class | `BoltApplication` | `ee.mtakso.App` | VERIFIED |
| Map stack | Google Maps SDK (marker mgr) | **Mapbox Maps + Ferrostar** + Google Maps | VERIFIED |
| Background location | **not declared** | **declared** (`ACCESS_BACKGROUND_LOCATION`) | VERIFIED |
| `SYSTEM_ALERT_WINDOW` / `PACKAGE_USAGE_STATS` / `GET_ACCOUNTS` | absent | **present** | VERIFIED |
| Custom permission | `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | same + **`MAPS_RECEIVE`** (signature) | VERIFIED |
| Onboarding ML (face/doc/OCR) | ML Kit barcode only | **ML Kit + TFLite + Veritas doc/face verification** | VERIFIED |
| Analytics | Firebase, Braze, Sentry, Singular/AppsFlyer | Firebase, Braze, **Mixpanel**, Sentry, Singular | VERIFIED |
| VOIP | Sinch (VoipService) | Sinch + `VoipFloatingActivity` + `VoipIntentService` | VERIFIED |
| Launcher | `RideHailingMapActivity` (+ alias) | `LauncherActivity` | VERIFIED |
| Deep-link schemes | `bolt://`, `taxify://`, `geo://` | `boltdriverapp://`, `taxifydriverapp://`, `https://boltdriver.sng.link` | VERIFIED |
| extractNativeLibs | false | **true** | VERIFIED |
| Shared paradigms | RIBs, Dagger, WorkManager, Room, OkHttp, multiplatform-settings, kotlinx.coroutines | same | VERIFIED (shared) |

**Key conclusion (VERIFIED/INFERRED):** Driver and Passenger are **separate apps** sharing the Bolt architectural paradigm (RIBs + Dagger + Kotlin + common `eu.bolt.*`/`ee.mtakso.*` conventions), but with materially different feature sets: the Driver app adds Mapbox/Ferrostar navigation, background-location presence tracking, driver onboarding ML (document/face verification), Mixpanel, and floating-overlay VOIP. Implementations are **not assumed identical**.

---

## 9. Limitations

1. **Signature verification not performed** (`signature_verification: not_performed`); APK authenticity not asserted.
2. **Split APKs** `split_config.arm64_v8a.apk` and `split_config.xxhdpi.apk` were enumerated via ZIP listing but **not** independently SHA-256-digested nor opened in JADX (they contain native libs and density resources respectively; the manifest/package identity lives in `base.apk`).
3. **Native `.so`** files were identified by filename only; their internal symbols were not analyzed.
4. **Hardcoded keys** observed in manifest meta-data (VERIFIED presence): `com.google.android.funnel.API_KEY` (a UUID), `com.crashlytics.ApiKey`, `com.google.android.geo.API_KEY` (@string, value in resources). These are client-side public keys, not user credentials; their presence is noted, not their misuse.
5. **No runtime/network observation**; conclusions are static.
6. SDK versions/detailed module boundaries are INFERRED from `.properties`, `.so` names and class names; not every SDK version was resolved.
7. "Veritas" is INFERRED to be an identity/document-verification SDK based on `veritas_document_detector_v1.tflite` + `VerificationSDKActivity`; no behavioral verification performed.
