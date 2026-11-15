# KEKE Passenger — Phase 3B (Application Graph)

**Target:** `C:\REA-BOLT\artifacts\passenger\base.apk`
**SHA-256:** `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`

## Method note

`rea_project_android_application_graph` requires the full `inventory_artifact`
Evidence inline (~10.5 MB), which exceeds the MCP stdio transport budget
(`resource_constraint`). The projection could not be invoked over MCP. The
equivalent structural projection was performed by paging the retained inventory
Evidence (`ev_3cfbda0…`) directly. apktool and jadx-headless-mcp were not
configured, so binary `AndroidManifest.xml` and DEX were not decoded.

## VERIFIED

The Kotlin compiler emits one `.kotlin_module` file per Gradle module. All nine
named modules are directly observed:

| Module | `.kotlin_module` entry | bytes |
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

**Structural facts:**
- **Grouping tiers** (from path prefixes): top-level core/shared
  (`android-app-client:*`), feature modules (`android-app-client.modules.<feature>:*`
  and `android-app-client.modules:*`), shared UI/commons (`android-app-common:*`,
  `android-app-common.bdui:*`), SDK (`android-sdk-*`).
- **Co-location**: all nine modules are merged into `base.apk` DEX (not
  feature-delivery splits).
- **DEX**: 11 files, ~93.7 MB.
- **Native libraries**: absent from base.apk; present in the ABI split
  (`libcrashlytics*`, `libsentry*`, `libmlkit_google_ocr_pipeline.so`,
  `libimage_processing_util_jni.so`, `libsurface_util_jni.so`,
  `libandroidx.graphics.path.so`, `libdatastore_shared_counter.so`).
- **Delivery**: Android App Bundle split (`BNDLTOOL.RSA/SF`).
- **SDK markers**: `play-services-maps`, `play-services-location`, ML Kit
  (barcode/face/text/OCR), `play-services-wallet/fido/auth*`, Firebase
  (analytics/perf/crashlytics), Sentry, Singular, Braze, recaptcha, integrity,
  okhttp3, libphonenumber.

## INFERRED

1. `ride-hailing` → depends on `ride-hailing-core` ("-core" naming).
2. `map-google` → implements `map` abstraction (corroborated by
   `play-services-maps.properties`).
3. `geofencing` → depends on `location-core`; location-core binds Google Fused
   Location (`play-services-location.properties`).
4. `payments-core` → base for `creditcard`.
5. `scheduledrides-core` → base for the scheduled-rides feature.
6. `chat` → cross-cutting shared capability.

## UNKNOWN (requires JADX)

1. Code-level dependency edges between modules.
2. Per-module class/package membership.
3. Manifest components → module mapping.
4. App package name / versionName.
5. DI wiring (RIBs).
6. Static vs on-demand feature loading.

## Recommended JADX targets

1. Decode `AndroidManifest.xml` → map components to modules.
2. `ride-hailing-core` ⇄ `ride-hailing` import direction.
3. `map` ⇄ `map-google` abstraction/impl binding.
4. `location-core` ⇄ `geofencing` import edges.
5. `payments-core` ⇄ `creditcard` / `scheduledrides-core` edges.
6. `chat` consumer surface.
7. ML Kit OCR native boundary (`libmlkit_google_ocr_pipeline.so`).

## Evidence references

- inventory: `ev_3cfbda03960325630de610426bf38f9cae2f9c0197f543bfc2f563a0940a62f2`
- inspect_artifact: `ev_5f26dcf3b808873c08c5be4a861b8d30f37cbbea0cd411baac91726cccb9d191`
- split inventory: `ev_86204b51ffd034296a0e26d76495b997aa1b17865d84b7a3a7a90219513a661f`
