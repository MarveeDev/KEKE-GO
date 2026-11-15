# KEKE Passenger Findings

Consolidated finding ledger for the Bolt **passenger** application.
Findings are partitioned into VERIFIED, INFERRED, and UNKNOWN, and carry
evidence references (Evidence IDs), SHA-256 digests, tool limitations, and
outstanding questions.

## Target identity

| Field | Value |
|---|---|
| Artifact | `C:\REA-BOLT\artifacts\passenger\base.apk` |
| Format | APK (ZIP) |
| SHA-256 (base.apk) | `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db` |
| Size (base.apk) | 101,130,206 bytes |
| Sibling splits | `split_config.arm64_v8a.apk` (13,321,469 bytes), `split_config.en.apk`, `split_config.xxhdpi.apk` |
| SHA-256 (arm64_v8a split) | `184f7f6cbcb2f6810811edaa4b15ef160bd8ca021f52b0ae9773998d8a260122` |
| Delivery | Android App Bundle (bundletool, `BNDLTOOL.RSA/SF` signature) |
| Version marker (observed) | `app-CA.231.0_liveGooglePlayBoltRelease` (from `.kotlin_module` variant name) |

Evidence references (inventory):
- inventory Evidence: `ev_3cfbda03960325630de610426bf38f9cae2f9c0197f543bfc2f563a0940a62f2`
- inspect_artifact Evidence: `ev_5f26dcf3b808873c08c5be4a861b8d30f37cbbea0cd411baac91726cccb9d191`
- graph manifest id: `agm_c5365ff466ed43dbb3a7c76fc80802faa0c506580767ada9644a9dcd257ce867`
- graph SHA-256: `7e604b87372ef76c47e66afd4c6260c7a76d407d1f3a8f8b4b8652f0ffd2a291`
- split inventory Evidence: `ev_86204b51ffd034296a0e26d76495b997aa1b17865d84b7a3a7a90219513a661f`

---

## VERIFIED

1. Nine named modules are each directly observed as a compiled Kotlin module via
   its `META-INF/<name>.kotlin_module` file (Kotlin compiler per-module metadata):

   | Module | `.kotlin_module` entry | declared bytes |
   |---|---|---|
   | ride-hailing | `android-app-client:ride-hailing_liveGooglePlayBoltRelease.kotlin_module` | 480 |
   | ride-hailing-core | `android-app-client:ride-hailing-core_release.kotlin_module` | 431 |
   | location-core | `android-app-client:location-core_release.kotlin_module` | 121 |
   | geofencing | `android-app-client.modules:geofencing_release.kotlin_module` | 59 |
   | map | `android-app-client:map_release.kotlin_module` | 61 |
   | map-google | `android-app-client:map-google_release.kotlin_module` | 47 |
   | payments-core | `android-app-client.modules.payments:payments-core_release.kotlin_module` | 50 |
   | scheduledrides | `android-app-client.modules.scheduledrides:scheduledrides-core_release.kotlin_module` | 68 |
   | chat | `android-app-client:chat_liveGooglePlayBoltRelease.kotlin_module` | 142 |

2. Module namespace tiers (from `.kotlin_module` path prefixes):
   - `android-app-client:*` (core/shared, flat): ride-hailing, ride-hailing-core,
     location-core, map, map-google, chat, network, core-base, targeting,
     verification-core, ribs-shared, rh-search-address, utils-android/jvm.
   - `android-app-client.modules.<feature>:*`: payments (`payments-core`,
     `creditcard`), scheduledrides (`scheduledrides-core`), carsharing,
     micromobility, parcel, voip, camera, analytics, data-gathering, design,
     home, info-blocks, startup, user, platform.
   - `android-app-client.modules:*`: geofencing, activity/activity-core,
     user-tab-bar/…-core.
   - Shared UI/commons: `android-app-common:*`, `android-app-common.bdui:*`
     (uikit, ribs, coroutines, engine-html, uikit-compose/theme).
   - SDK: `android-sdk-base`, `android-sdk-ui`.

3. DEX footprint: 11 DEX files (`classes.dex` … `classes11.dex`), total
   ~93.7 MB. `classes2.dex` is 280,800 bytes (multidex metadata). Largest:
   classes6.dex 10,708,080; classes10.dex 10,644,600; classes5.dex 10,239,300.

4. Native libraries are NOT in base.apk; they ship in the ABI split
   `split_config.arm64_v8a.apk` (17 entries). Observed `.so`:
   `libcrashlytics*.so` (Firebase Crashlytics), `libsentry.so` + `libsentry-android.so`,
   `libmlkit_google_ocr_pipeline.so` (11 MB, ML Kit OCR), `libimage_processing_util_jni.so`,
   `libsurface_util_jni.so`, `libandroidx.graphics.path.so`, `libdatastore_shared_counter.so`.

5. Third-party SDK markers (`.properties` marker files + assets):
   `play-services-maps`, `play-services-location`, `play-services-mlkit-barcode-scanning`,
   `play-services-mlkit-face-detection`, `play-services-mlkit-text-recognition`,
   `play-services-wallet`, `play-services-fido` (+ `assets/passkey_config.json`),
   `play-services-auth*`, `play-services-cloud-messaging`, `play-services-ads-identifier`,
   `firebase-analytics`, `firebase-perf`, `firebase-encoders`, `sentry-*`,
   `Singular` (attribution), `Braze`, `recaptcha`, `integrity`, `googleid`,
   `okhttp3`, `libphonenumber` (hundreds of `PhoneNumber*Proto` / `ShortNumber*Proto`).

---

## INFERRED

1. `ride-hailing` depends on `ride-hailing-core` ("-core" naming).
2. `map-google` implements the `map` abstraction (map-google → map); corroborated
   by `play-services-maps.properties`.
3. `geofencing` depends on `location-core`; `location-core` binds to Google Play
   Fused Location (`play-services-location.properties`).
4. `payments-core` is the base for `creditcard` (same `modules.payments` group).
5. `scheduledrides-core` is the base for the scheduled-rides feature.
6. `chat` is a cross-cutting shared capability (direct child of
   `android-app-client`, not under `modules.*`).

These are naming/grouping hypotheses; dependency directions are NOT observed.

---

## UNKNOWN

1. Code-level dependency edges between the nine modules (requires DEX analysis).
2. Per-module class/package membership (`.kotlin_module` contents unreadable on
   Windows: `:` in filenames = ADS syntax; extraction failed).
3. `AndroidManifest.xml` components and their module mapping (binary AXML;
   apktool/JADX unavailable at capture time).
4. App package name and versionName (manifest unread).
5. Dependency-injection wiring (RIBs architecture indicated by `ribs`/`ribs-shared`).
6. Static vs on-demand (feature-delivery) loading of `ride-hailing`/`chat`/etc.

---

## Tool limitations (recorded)

- Full inventory Evidence is >10 MB and could not be returned inline over MCP
  (`resource_constraint`, transport). Analysis proceeded by paging the retained
  inventory (`inspect_analysis_view`).
- `apktool` not configured (`REA_APKTOOL_COMMAND` unset) — manifest not decoded.
- `jadx-headless-mcp` not configured at capture time (`REA_JADX_MCP_JAR` unset) —
  no DEX class/method analysis.
- `extract_artifact` failed on Windows (ADS `:` filename collision).

## Outstanding questions

1. Which classes belong to each of the nine modules?
2. What is the exact dependency direction between `ride-hailing` and
   `ride-hailing-core`, and between `map` and `map-google`?
3. Which Android components (activities/services/receivers/providers) does each
   module register in the manifest?
4. Which module drives the ML Kit OCR native pipeline (`libmlkit_google_ocr_pipeline.so`)?
