# BOLT Driver — Phase 7: Earnings, Wallet & Payments

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`
**Tooling:** REA MCP + JADX headless 0.7.1 (class search + `get_class_summary`).
**Scope:** Read-only static analysis. No APK modification, no runtime, **no extraction of personal data, credentials, or financial account details**.

Confidence labels:
- **VERIFIED** — directly observed in JADX metadata (class/field/method/enum names).
- **INFERRED** — deduced from dependency types/naming; not proven by method bodies.
- **UNKNOWN** — not resolvable (obfuscation / backend-only).

**Central finding:** All financial values (earnings, balance, payouts, bonuses, fares) are **backend-supplied** — the driver app renders server-provided JSON models (kotlinx.serialization) and submits payout/withdrawal requests. No commission formula, settlement rule, or local monetary calculation was observed. None is claimed.

---

## 1. Driver Earnings

### 1.1 Earnings dashboard (VERIFIED)
- `ee.mtakso.driver.ui.screens.earnings.v3.navigation.*`: `EarningsLandingRoute`, `EarningsBalanceRoute`, `EarningsBreakdownRoute`, `EarningsNetBreakdownRoute`, `EarningsBreakdownExplanationRoute`, `EarningsGoalRoute`.
- `ee.mtakso.driver.ui.screens.earnings.v3.breakdown.EarningsBreakdownListSectionAction`.

### 1.2 Backend-driven "earnings island" (VERIFIED)
- `eu.bolt.driver.earnings.island.data.network.*`: `EarningsIslandBlock`, `EarningsIslandBlockLayout`, `EarningsIslandBlockTopLabelState`, `EarningsIslandDetails`, `EarningsIslandDetailsV2`, `EarningsIslandHeader`, `EarningsIslandItem`, `EarningsIslandPill` — the earnings summary "island" is rendered from server models.

### 1.3 Daily / weekly / period earnings (VERIFIED — model presence)
- `eu.bolt.driver.earnings.network.EarningsGoalPeriod`, `EarningsActivityTile`, `EarningsBalanceStateType`; `ee.mtakso.driver.network.client.driver.DriverEarningsData`, `Earnings`.
- `PastOrderEarnings` (`orderhistory.data.details`) — completed-trip earnings in history.
- Specific day/week bucketing is **UNKNOWN** (server-provided; not local).

### 1.4 Fare breakdown (VERIFIED — model presence)
- `ee.mtakso.driver.network.client.order.Price`, `PriceReviewInfo`, `PriceCalculationItem`, `PriceCalculationForRouteChangeConfirmationRequest/Response`, `PriceReviewState` (Phase 5/6).
- `EarningsBreakdownRoute` / `EarningsNetBreakdownRoute` / `EarningsBreakdownExplanationRoute` — breakdown UI routes.

### 1.5 Commission & deductions (UNKNOWN)
- No commission/deduction field was identified by readable name. Commission is server-computed and not observable from the APK.

### 1.6 Bonuses & incentives (VERIFIED — see §5).

### 1.7 Earnings history (VERIFIED — model presence)
- `PastOrderEarnings`, `ee.mtakso.driver.orderhistory.data.details.*` (order/earnings history).

---

## 2. Driver Wallet

### 2.1 Wallet architecture (VERIFIED — naming)
- No first-party class named "Wallet" exists (the only "Wallet" matches are the Google Pay SDK `com.google.android.gms.wallet.*`, used for *passenger* card payments, not a driver wallet).
- The driver's "wallet/balance" is implemented under the **earnings** and **bolt-money** modules.

### 2.2 Balance (VERIFIED — presence)
- `EarningsBalanceRoute` (UI), `EarningsBalanceStateType` (network model) — balance state (e.g. available vs pending; exact enum values **UNKNOWN**).

### 2.3 Available vs pending balances (INFERRED)
- `EarningsBalanceStateType` implies multiple balance states; exact values obfuscated → **UNKNOWN**.

### 2.4 Transactions / credits / debits / history (UNKNOWN)
- No dedicated transaction/ledger class surfaced by readable name. Payout history (`PayoutHistoryItem`) is the closest observable history. Transaction detail models are **UNKNOWN**.

### 2.5 Bolt Money (VERIFIED — module presence)
- `eu.bolt.driver.boltmoney.*`: `BoltMoneyRoute` (navigation route), `di.a`/`di.b` (Dagger DI), obfuscated `a`–`e`, `DataBinderMapperImpl`.
- `ee.mtakso.driver.startup.BoltMoneyInitializer` (see §8).

---

## 3. Payouts

### 3.1 Payout requests & models (VERIFIED)
- `ee.mtakso.driver.network.client.earnings.CreatePayoutRequest`, `CreatePayoutResponse`, `PayoutConfirmationResponse`, `PayoutHistoryItem`, `PayoutHistoryResponce` (sic), `PayoutResponce` (sic).

### 3.2 Payout status (VERIFIED — readable enum)
- `ee.mtakso.driver.network.client.earnings.PayoutState` (kotlinx.serialization enum):
  - `COMPLETE`
  - `PENDING`
  - `REJECTED`

### 3.3 Payout UI (VERIFIED)
- `ee.mtakso.driver.ui.screens.earnings.v2.payout.*`: `PayoutDetailsRoute`/`PayoutDetailsViewModel`, `PayoutHistoryRoute`, `PayoutRequestRoute`/`PayoutRequestViewModel`.

### 3.4 Bank / mobile-money integrations (UNKNOWN)
- No bank-account or mobile-money (e.g. M-Pesa) class surfaced by readable name. Withdrawal method is server-side; the client only submits `CreatePayoutRequest` and renders status.

### 3.5 Withdrawal confirmation & failure handling (VERIFIED — model presence; INFERRED — semantics)
- `PayoutConfirmationResponse` (confirmation), `PayoutState.REJECTED` (failed). Retry/error UI specifics **UNKNOWN**.

---

## 4. Payment Methods

### 4.1 Cash rides & in-app payments (VERIFIED — model presence)
- `ee.mtakso.driver.network.client.order.DriverOrderPaymentDetails`, `PastOrderPaymentDetails`, `PaymentType`, `PaymentMethodChangeConfig`, `CreationOrderSectionPaymentMethod`, `CreationOrderSectionPaymentMethodType` (Phase 5) — payment method / cash-vs-card type models.
- `ee.mtakso.driver.network.client.payments.EarningsPayment`.

### 4.2 Payment collection indicators (INFERRED)
- `PaymentType` + `DriverOrderPaymentDetails` imply cash vs card handling; whether the driver actively collects cash is **INFERRED** (not proven).

### 4.3 Payment confirmation & outstanding balances (UNKNOWN)
- No explicit "outstanding balance" class surfaced; any balance owed is server-computed.

### 4.4 Payment notifications (INFERRED)
- FCM/Braze/Mixpanel push (Phase 2) + `EarningsPayment`/`PaymentsDispatcher`-style notifications (INFERRED linkage).

---

## 5. Bonuses & Incentives

### 5.1 Driver promotions / campaigns (VERIFIED — comprehensive)
`eu.bolt.driver.campaign.*`:
- Network models: `Bonus`, `BonusTrips`, `CampaignV2Details`/`CampaignV3Details`, `CampaignV2Group`/`CampaignV3Group`, `Condition`, `ConditionType`, `ProgressCondition`, `SplitProgressCondition`, `ThresholdCondition`, `ThresholdData`, `Periods`, `CampaignDisplayPrice`, `Badge`/`BadgeType`, `DriverCampaignBadge`, `DriverCampaignV2`, `OptInChoiceV2`/`OptInChoicesV2`/`OptInGroupV2`/`OptInGroupSummary`, `ActiveAndPendingCampaignInfo`/`ActiveAndPendingCampaignsV2`/`V3`, `PastCampaignsV2`/`V3`, `InviteCampaign`, `InviteCampaignSummary`.
- Domain: `DriverReferralCampaignManager`, `GetInviteCampaignSummaryUseCase`, `ReferralCampaignsAnalytics`.
- Referral: `DriverReferralCampaignInvitation`/`Status`/`InvitesDetails`, `GetReferralTieredCampaignScreenResponse`, `ReferralListRequest/Response`, `ReferralProfileRequest/Response`, `ReferralProgressDetails`, `GetShareReferralCodeResponse`.
- UI: `CampaignDetailsV3Route`, `ReferralCampaignDetailsRib*`, `CampaignBannerTileDelegate`, `ActiveCampaignTileViewDelegate`, `PastCampaignsFilter`, Circle-K loyalty (`circlk.*`, `CircleKLoyaltySignUpMagicLink`), QR share-code.

### 5.2 Target-based incentives (VERIFIED — model presence)
- `BonusTrips` (trip-count bonus), `ThresholdCondition`/`ThresholdData`, `ProgressCondition`/`SplitProgressCondition`, `Periods` — threshold/progress-based campaign targets.

### 5.3 Bonus eligibility & progress (VERIFIED — model presence)
- `ProgressCondition`, `ThresholdCondition`, `EarningsGoal` + `EarningsGoalPeriod`/`EarningsGoalExpenseCategory`, `GetEarningsGoalResponse`/`SetEarningsGoalRequest` — goals + progress.

### 5.4 Rewards / loyalty (VERIFIED — comprehensive)
`eu.bolt.driver.rewards.*`:
- `DriverOffer`, `DriverOffersGroup`, `GetOfferListByTierRequest/Response`, `RewardInfoResponse`, `SetBonusRewardsPointsRequest`.
- Loyalty: `GetLoyaltyExplanationResponse`, `GetLoyaltyLevelDetailsResponse`, `LoyaltyLevelBenefit`/`Item`/`Details`/`DetailsItem`/`DetailsProgress`, `LoyaltyExplanationBlock`/`TableItem`/`BottomSection`.
- Peak hours: `PeakHourBottomSheet`, `PeakHourDetails`, `RewardsPeakHoursPayload`.
- Requirements: `GetRewardsRequirementsScreenResponse`, `RewardsRequirementsRequest/Section`, `RewardsRequirementsRoute`.
- UI: `RewardsLandingRoute`, `RewardsExplanationRoute`, `SetBonusRewardsPointsActionFragment`.

---

## 6. Financial Models (VERIFIED — names)

- Earnings: `Earnings`, `DriverEarningsData`, `EarningsPayment`, `EarningsBalanceStateType`, `PastOrderEarnings`.
- Payout: `CreatePayoutRequest/Response`, `PayoutConfirmationResponse`, `PayoutHistoryItem`, `PayoutHistoryResponce`, `PayoutResponce`, `PayoutState` (COMPLETE/PENDING/REJECTED).
- Order/payment: `Price`, `PriceReviewInfo`, `PriceCalculationItem`, `DriverOrderPaymentDetails`, `PastOrderPaymentDetails`, `PaymentType`, `PaymentMethodChangeConfig`.
- Incentives: `Bonus`, `BonusTrips`, `ThresholdData`, `Periods`, `CampaignDisplayPrice`, `EarningsGoal`.
- Currency/amount representation: `Price`, `CampaignDisplayPrice`, `PriceCalculationItem` (amount fields); exact currency fields **UNKNOWN** (obfuscated internals; kotlinx.serialization used throughout).

---

## 7. Backend Boundary (explicit)

### 7.1 Backend-supplied values (VERIFIED — all financial data is server-provided)
- Earnings (`Earnings`, `DriverEarningsData`, `EarningsIsland*`), balance (`EarningsBalanceStateType`), payouts (`PayoutState`, `PayoutHistoryItem`), bonuses/campaigns (`Bonus`, `ThresholdData`, `ProgressCondition`), fares (`Price`, `PriceCalculationItem`) — all are network models deserialized via kotlinx.serialization.

### 7.2 Local calculations (UNKNOWN — none identified)
- No local commission/earnings/settlement computation was observed. The client renders server values. Any local arithmetic (e.g. summing line items for display) is INFERRED but not verified.

### 7.3 Network interfaces & use cases (VERIFIED — presence)
- `ee.mtakso.driver.network.client.earnings.*`, `network.client.driver.*`, `network.client.payments.*`, `eu.bolt.driver.earnings.network.*`, `eu.bolt.driver.campaign.network.*`, `eu.bolt.driver.rewards.network.*`.
- Use cases: `GetInviteCampaignSummaryUseCase`, `SetEarningsGoalRequest`/`GetEarningsGoalResponse`, `GetOfferListByTierRequest/Response`.

### 7.4 Not assumed (explicit)
- Bolt's commission formula, settlement/fee rules, payout scheduling, and bonus eligibility logic are **not** observable and are **not** assumed.

---

## 8. Bolt Money

### 8.1 `BoltMoneyInitializer` (VERIFIED — structure)
`ee.mtakso.driver.startup.BoltMoneyInitializer`:
- `create(Context): kotlin.Unit` — androidx.startup `Initializer`.
- `dependencies(): List<Class<? extends androidx.startup.b>>` — declares startup dependencies.
- `a(Context): void` — obfuscated init body.

### 8.2 Callers & dependencies (VERIFIED — manifest wiring)
- Registered in `androidx.startup.InitializationProvider` (Phase 2 manifest) — runs at app startup.
- The `eu.bolt.driver.boltmoney.*` module (`BoltMoneyRoute`, `di.a`/`di.b`) is its corresponding feature module (VERIFIED presence).

### 8.3 Connection to wallet/payment (INFERRED)
- `BoltMoney` is a navigable feature module (`BoltMoneyRoute`) initialised at startup, sharing the earnings/money domain. Its exact behaviour is obfuscated; it is **INFERRED** to be the driver money/earnings hub. **Not assumed** beyond being a startup-initialised money feature (its name alone is not treated as proof of scope).

---

## 9. Unresolved Questions & KEKE Blueprint Recommendations

### 9.1 Unresolved questions
1. **Balance states:** enumerate `EarningsBalanceStateType` (available/pending/payout-in-progress?).
2. **Transaction/ledger model:** is there a per-trip transaction/debit/credit model (none surfaced; likely server-only)?
3. **Payout destination:** where is bank/mobile-money account info configured (no class surfaced — likely a web flow or server-side)?
4. **Commission/deductions:** confirm no client-side commission rendering (expected: `Price`/`PriceCalculationItem` are server strings).
5. **Currency:** exact currency/amount fields inside `Price`/`CampaignDisplayPrice`.
6. **Bolt Money internals:** what `BoltMoneyInitializer.a(Context)` actually initialises (obfuscated).
7. **Bonus eligibility:** is `BonusTrips`/`ThresholdData` progress computed server-side only (expected yes)?

### 9.2 KEKE engineering blueprint recommendations
1. **Treat finance as server-authoritative:** model the KEKE driver client as a *renderer* of server-provided `Earnings`/`Payout`/`Campaign`/`Rewards` DTOs; do not compute money locally.
2. **Reuse the "backend-driven UI" pattern** (as in `IncomingOrderResponse` and `EarningsIsland*`): drive the earnings/dashboard UI from server blocks to keep layout flexible without app releases.
3. **Payout state machine** (client): mirror `PayoutState` = `PENDING → COMPLETE | REJECTED`; keep withdrawal initiation (`CreatePayoutRequest`) simple and server-validated.
4. **Incentives**: model campaigns as `Condition`/`ProgressCondition`/`ThresholdCondition` + `Bonus/BonusTrips` + `OptIn*`, and rewards as loyalty tiers + peak-hour offers — all server-evaluated, client-rendered.
5. **Modular feature init**: follow the `BoltMoneyInitializer` + feature-module (`boltmoney`) + `Route` pattern for the KEKE earnings feature.
6. **Serialization**: use kotlinx.serialization for all financial DTOs (as Bolt does) with versioned models.
7. **Boundary discipline**: keep financial rules (commission, settlement, eligibility) server-side; never ship them in the client.

---

## 10. Limitations

1. Heavy obfuscation — `BoltMoneyInitializer.a`, `EarningsBalanceStateType`, and amount fields are unreadable.
2. No runtime/network capture; all financial values are inferred to be server-supplied from model shape, not observed live.
3. No personal data, credentials, or financial account details extracted.
4. Split APKs not decompiled this phase.
5. Commission/settlement/bonus-eligibility rules are explicitly out of scope (backend, not observable, not claimed).
