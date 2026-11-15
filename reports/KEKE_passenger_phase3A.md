# KEKE Passenger — Phase 3A (Initial Artifact Inspection)

**Status:** Complete (reconstructed in this session — see provenance note)

## Provenance note

The prior session's Phase 3A evidence was not retained into the current
session (0 retained Evidence records on entry). The inventory was therefore
re-derived deterministically by re-running `inspect_artifact` on the same
artifact. All figures below are re-verified from that run and carry current
Evidence references.

## Artifact identity

| Field | Value |
|---|---|
| Path | `C:\REA-BOLT\artifacts\passenger\base.apk` |
| Format | APK |
| SHA-256 | `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db` |
| Size | 101,130,206 bytes |

Evidence:
- `inspect_artifact` (complete): `ev_5f26dcf3b808873c08c5be4a861b8d30f37cbbea0cd411baac91726cccb9d191`
- inventory: `ev_3cfbda03960325630de610426bf38f9cae2f9c0197f543bfc2f563a0940a62f2`

## Inventory

- Graph nodes: 3,904
- Occurrences (files): 4,127
- Edges: 4,126
- Entry kinds: file 4,127 (no directories/symlinks/slices)
- Integrity contradictions: 0
- graph SHA-256: `7e604b87372ef76c47e66afd4c6260c7a76d407d1f3a8f8b4b8652f0ffd2a291`

Top-level structure (alphabetical, sampled):
- `AndroidManifest.xml` (55,648 bytes)
- `META-INF/` — `*.kotlin_module` (module metadata), `*.version`, `.SF/.RSA`,
  `NOTICE.md`
- `app-update*.properties`, `*.properties` (third-party SDK markers)
- `assets/` — libphonenumber data (hundreds of `PhoneNumber*Proto`), ML Kit OCR
  models (`mlkit-google-ocr-models/`), fonts, shaders, `sentry-*`,
  `passkey_config.json`, `braze-*.js`
- `classes.dex` … `classes11.dex` (11 DEX, ~93.7 MB total)
- `kotlin/*.kotlin_builtins` (Kotlin stdlib metadata)
- `google/`, `firebase/` — bundled `.proto` descriptors
- `res/` (anim, color, drawable, layout, mipmap, values, xml …)

## Module enumeration

The `.kotlin_module` files enumerate the Gradle/Kotlin module structure.
Full list is captured in `KEKE_findings_passenger.md`; the nine named modules
(ride-hailing, ride-hailing-core, location-core, geofencing, map, map-google,
payments-core, scheduledrides, chat) are all present.

## Tool limitations

- Full inventory exceeded MCP transport budget; paged via `inspect_analysis_view`.
- `apktool` and `jadx-headless-mcp` not configured → manifest and DEX not decoded
  in this phase.

## Next step

Phase 3B — application graph / module relationship analysis (see
`KEKE_passenger_phase3B.md`).
