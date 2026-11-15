# KEKE — Bolt Passenger Application Architecture

Observed architecture of the Bolt passenger Android application
(`base.apk`, SHA-256 `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`).
Derived from static artifact evidence only (Kotlin module metadata, DEX layout,
native-library ABI split, third-party SDK markers). No DEX decompilation has yet
been performed.

## 1. Build / delivery model

- Android App Bundle delivered as splits (`base.apk` + `split_config.*`).
  Split signature is `BNDLTOOL.RSA/SF` (bundletool).
- Native libraries are delivered via the ABI split
  (`split_config.arm64_v8a.apk`), not base.apk.
- Language/density split: `split_config.en.apk`, `split_config.xxhdpi.apk`.
- Observed build variant marker: `app-CA.231.0_liveGooglePlayBoltRelease`
  (Google Play live release of the Bolt app).

## 2. Module topology (from `META-INF/*.kotlin_module`)

Three namespace tiers:

```
android-app-client:*                     # core / shared (flat)
  ├── ride-hailing, ride-hailing-core
  ├── location-core, map, map-google
  ├── chat, network, core-base, targeting
  ├── verification-core, ribs-shared, rh-search-address, utils-*
android-app-client.modules.<feature>:*   # feature modules
  ├── payments (payments-core, creditcard)
  ├── scheduledrides (scheduledrides-core)
  ├── carsharing, micromobility, parcel, voip, camera
  ├── analytics, data-gathering, design, home, info-blocks
  ├── startup, user, platform
android-app-client.modules:*             # feature-root modules
  ├── geofencing, activity/activity-core, user-tab-bar
android-app-common:*  /  .bdui:*         # shared UI / commons
  ├── uikit, uikit-compose/theme, ribs, coroutines, engine-html
android-sdk-base / android-sdk-ui        # SDK layer
```

## 3. Code & native layout

- 11 DEX files (`classes.dex` … `classes11.dex`), ~93.7 MB.
- Native (arm64-v8a split): Firebase Crashlytics, Sentry, ML Kit OCR pipeline
  (11 MB), ML Kit image/surface util JNI, AndroidX graphics path, DataStore.

## 4. Key SDK integrations (marker-observed)

- **Map/Location:** Google Maps (`play-services-maps`), Fused Location
  (`play-services-location`) → map-google / location-core.
- **ML:** ML Kit barcode / face / text recognition / OCR.
- **Payments/identity:** Google Wallet, Play FIDO (passkeys), Play auth, Block Store.
- **Analytics/attribution:** Firebase Analytics + Performance, Singular, Braze.
- **Crash/observability:** Firebase Crashlytics, Sentry.
- **Network:** okhttp3; protobuf descriptors bundled (google/firebase `.proto`).
- **Telephony:** libphonenumber (hundreds of metadata proto assets).

## 5. Relationship confidence

- VERIFIED: module existence, grouping tiers, DEX/native split layout, SDK markers.
- INFERRED: `ride-hailing`→`ride-hailing-core`, `map-google`→`map`,
  `geofencing`→`location-core`, `payments-core`/`scheduledrides-core` base roles,
  `chat` shared-capability role.
- UNKNOWN: code-level dependency edges, manifest→module mapping, DI graph,
  static-vs-dynamic feature loading.

## 6. Tooling status

- apktool: not configured (`REA_APKTOOL_COMMAND`).
- jadx-headless-mcp 0.7.1: JAR acquired and SHA-256 verified; `REA_JADX_MCP_JAR`
  set at user level (requires REA server restart to take effect).
- Java: JDK 25 (Temurin) on PATH. NOTE: `JAVA_HOME` is misconfigured and points
  to `C:\Users\HP\Downloads\jre-8u471-windows-x64.exe` (a JRE 8 installer, not a
  JDK directory) — a potential JADX blocker if REA resolves Java via `JAVA_HOME`.
