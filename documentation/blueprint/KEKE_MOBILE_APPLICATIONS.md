# KEKE — Mobile Applications

**Status:** Engineering blueprint. Two apps (Passenger, Driver) from one React
Native + TypeScript codebase.

**Boundary note:** Bolt ships two **native Kotlin** apps with distinct feature
sets (passenger `ee.mtakso.client`, driver `ee.mtakso.driver` — VERIFIED). KEKE
chooses React Native for delivery speed (see Architecture §4.1). Feature lists
below are **KEKE scope decisions** informed by — but not copied from — the
observed Bolt capabilities. No Bolt code, assets, or branding is reused.

---

## 1. Shared foundation (monorepo)

```
apps/passenger/          # passenger app
apps/driver/             # driver app
packages/api-client/     # generated typed API client (shared)
packages/ui/             # shared design system / components
packages/geo/            # shared location/geofence utilities
packages/realtime/       # WebSocket client + resync logic
packages/native/         # native modules (background location, FGS, nav)
```

Both apps consume the same generated API client and realtime client, ensuring the
contract in `KEKE_API_SPECIFICATION.md` is enforced in code.

---

## 2. Passenger app — feature set

| Feature | Notes |
|---|---|
| Phone OTP sign-up/sign-in | SMS (WhatsApp optional); JWT + rotating refresh |
| Home map | Current location, nearby drivers (optional), zones |
| Pickup / destination entry | In-app address search (server geocoding), saved places |
| Fare estimate | Server-computed (zone + distance), surge indicator |
| Ride request | `POST /rides` with pickup/dropoff/category/payment |
| Driver matching | "Searching" → assigned driver + vehicle + ETA |
| Live trip tracking | Driver position via WebSocket; ETA updates |
| Pickup code display | 4-digit code shown after `ACCEPTED` |
| Payment | Cash or Mobile Money (MoMo prompt) |
| Cancellation | Reason selection + fee confirmation |
| Rating & feedback | Post-trip rating + comment |
| Ride history | Completed/cancelled list + receipts |
| Support | In-app tickets, help center, emergency SOS contact |
| Profile | Name/email/phone, saved places, app settings |

## 3. Driver app — feature set

| Feature | Notes |
|---|---|
| Onboarding | Step machine (phone → profile → documents → vehicle), server-driven |
| Document upload | Camera capture → object storage → admin review |
| Vehicle registration | Keke details + plate/registration + capacity |
| Go online/offline | Server-gated; blockers surfaced as a dialog (Bolt's `GoOnlineIssueDialogDelegate` pattern — VERIFIED) |
| Availability presence | Foreground service + background location while online |
| Offer reception | Server-driven offer payload (pickup/dropoff, fare, ETA, countdown) |
| Accept / reject | With reason; idempotent |
| Navigation to pickup | Turn-by-turn (MapLibre Navigation / Ferrostar) |
| Arrive / pickup code | Enter passenger's 4-digit code to start trip |
| Active trip | Route progress, passenger contact (call/chat), GPS transmission |
| Destination change | With fare re-estimate |
| Trip completion | Finalize → earnings summary |
| Earnings dashboard | Server-rendered summary (gross/net/commission/bonuses) |
| Wallet | Balance (available/pending), transactions |
| Payouts | Request + history (PENDING/PROCESSING/COMPLETED/REJECTED) |
| Ratings | Rate passenger |

---

## 4. Maps and navigation

| Concern | MVP choice | Notes |
|---|---|---|
| Map tiles | MapLibre GL Native (OSM) | Cost-effective; Google Maps SDK as premium option |
| Markers/clustering | MapLibre + clustering lib | |
| Address search | Server geocoding (OSM Nominatim/Photon) | No client-side Places SDK |
| Driver turn-by-turn | MapLibre Navigation **or** Ferrostar wrapper | Ferrostar = open-source Rust nav (Bolt uses it — VERIFIED); spike to decide |

**Navigation abstraction:** wrap the chosen engine behind a `NavigationEngine`
interface so the engine is swappable without rewriting the trip UI.

---

## 5. Location permissions (Android focus)

| Permission | Passenger | Driver | Purpose |
|---|---|---|---|
| `ACCESS_FINE_LOCATION` / `COARSE` | ✅ | ✅ | pickup location, driver position |
| `ACCESS_BACKGROUND_LOCATION` | ❌ | ✅ | driver presence while app backgrounded |

This mirrors the **VERIFIED** Bolt distinction: the passenger app declares no
background location; the driver app does (`ACCESS_BACKGROUND_LOCATION` +
`AwakeService` location foreground service — VERIFIED). KEKE adopts the same
separation.

**Driver background location is the top technical risk** (see Architecture §9,
Roadmap). It is implemented with a **first-party native module** (Android
foreground service + fused location), not a JS-only solution:

- `react-native-foreground-service` (or a custom native service) keeps a
  persistent notification while the driver is online.
- The native module streams GPS fixes to the JS layer, which forwards them to
  the Location service (WebSocket `location.update` or REST fallback).
- Battery-optimization exemption prompt (Bolt queries OEM power managers — VERIFIED
  pattern) is surfaced during onboarding to keep the service alive.

---

## 6. Notifications

| Channel | Tech | Use |
|---|---|---|
| Background push | FCM (react-native-firebase) | new offer, ride accepted, trip completed, verification status |
| In-app realtime | WebSocket (shared `packages/realtime`) | live ride state, driver position, payment status |
| Local notifications | OS local | offer countdown, arrival reminders |

**Offer delivery uses both:** a high-priority FCM push (to wake the app) **plus**
a WebSocket `offer.new` (when foregrounded). The offer screen renders the
server payload; the countdown is display-only (server TTL is authoritative).

---

## 7. Authentication

- Phone OTP sign-up/sign-in (SMS, WhatsApp optional — Bolt uses both, VERIFIED).
- JWT access (short-lived) + rotating refresh token, stored in secure storage
  (Keychain / EncryptedSharedPreferences / Keystore).
- Refresh-token rotation on every refresh; single active device token.
- OTP auto-retrieval via SMS Retriever (Bolt uses `GmsSmsListener` + WhatsApp —
  VERIFIED).
- No device-side money/commission logic; the token only scopes role.

---

## 8. Offline & poor-network behaviour (Kumasi-specific)

Kumasi has variable connectivity; the apps must degrade gracefully.

| Situation | Behavior |
|---|---|
| No network at request time | Queue the request locally; retry with backoff; show "trying to connect" |
| Socket drop mid-ride | Reconnect + resync from `GET /rides/:id`; last-known driver position retained |
| Location fix lost | Hold last-known position; re-acquire; indicate stale position |
| Offer received but app lagging | Countdown is server-authoritative; late accept may return `OFFER_EXPIRED` |
| Low bandwidth maps | Tile cache (pre-cache Kumasi region); vector tiles are smaller |
| OTP SMS delayed | Resend after cooldown; WhatsApp fallback channel |

**Rule:** the client never invents state. When offline, it degrades to
"last known + retry"; on reconnect it converges to server state (see
`KEKE_RIDE_LIFECYCLE.md` §7).

---

## 9. Cross-cutting concerns

- **Crash reporting:** Sentry (Bolt uses Sentry + Crashlytics — VERIFIED).
- **Analytics:** product events (ride funnel, accept rate); privacy-minimal.
- **Security:** secure credential storage, TLS pinning (post-MVP), no secrets in
  the bundle, token scoping by role.
- **Accessibility & localization:** English + Twi (Kumasi) localization;
  large-tap targets for in-vehicle use.
- **Driver in-vehicle UX:** landscape-safe screens, one-hand controls, high-contrast
  day/night map.

---

## 10. Acceptance criteria (mobile)

1. Driver going online starts a foreground service that survives backgrounding and
   continues reporting location (verified on a low-end Android 8+ device).
2. Offer appears via FCM + WebSocket within 2s while the app is backgrounded.
3. Pickup-code entry gates trip start; wrong code rejected.
4. Ride status UI converges to server state after kill/reopen and after airplane-mode
   toggle.
5. Passenger live position updates render from WebSocket with no missed status
   transitions (verified via resync).

---

## 11. Open questions

1. **Navigation engine** — MapLibre Navigation vs Ferrostar (spike pending).
2. **SMS provider + WhatsApp fallback** for OTP in Ghana.
3. **Bluetooth pickup code** — deferred to post-MVP; confirm no MVP requirement.
4. **Map tile provider** licensing/cost for OSM vs Mapbox/Google.
