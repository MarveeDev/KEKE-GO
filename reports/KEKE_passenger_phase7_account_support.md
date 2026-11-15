# BOLT Passenger — Phase 7: Account, Authentication & Support Analysis

**Target:** `C:\REA-BOLT\artifacts\passenger\base.apk`
**SHA-256:** `b534f4d5bb5d653ee733f58df9eb74a9cbe96c2e30df39c982b6ff31b6d865db`
**Package:** `ee.mtakso.client` (Bolt passenger), versionName `CA.231.0`
**Tooling:** REA MCP + JADX headless 0.7.1 (class inventory; method names read from DEX metadata)
**Scope:** Read-only static analysis. No APK modification, no runtime/network capture, **no extraction of tokens, credentials or personal data values**.

Confidence labels:
- **VERIFIED** — directly observed in decompiled class/method metadata or the Phase 4 manifest.
- **INFERRED** — deduced from naming/dependency types; not proven by bytecode/runtime.
- **UNKNOWN** — not resolvable from static evidence.

The app is ProGuard/R8-obfuscated: use-case internals are single-letter, but UseCase/Repository/RIB/Delegate names are largely readable. Backend behaviour is **not** observable from this APK and is never claimed.

---

## 1. Authentication

### 1.1 Phone-number registration & login (VERIFIED)
- `eu.bolt.client.login.data.LoginRepository` — `signupRegistration`, `loginExternal`, `externalLoginOrRegister`, `verifyExternal`, `completeProfile`.
- `eu.bolt.client.login.domain.interactor.SignupUseCase` (`signup`), `AuthPhoneInputSubmitUseCase` (submit phone), `LoginSavedUserUseCase` (saved-user login).
- `eu.bolt.client.login.data.PhoneCountryProvider` — country-code handling.
- `eu.bolt.client.login.domain.model.AuthPhoneNumber`, `SignupBundle`, `SignupResult`, `LoginAuthBundle`.
- UI: `eu.bolt.client.login.rib.signin.SignInRibInteractor` (`loginWithPhone`), `LoginFlowRibInteractor` (`attemptToLogin`, `signup`, `attachPhoneVerification`), `ContinueWithRibInteractor` (`signup`), `AuthOptionsRib*`.
- Email-based auth also exists: `EmailSignupUseCase`, `EmailLoginOrRegisterUseCase`, `EmailCompleteProfileUseCase`, `EmailUpdateProfileUseCase` (package `…login.domain.interactor.signupemail.*`).

### 1.2 OTP verification (VERIFIED)
- `eu.bolt.client.login.domain.interactor.ConfirmPhoneVerificationUseCase`, `ConfirmLoginVerificationUseCase`, `ConfirmMatchAccountVerificationUseCase`.
- `eu.bolt.client.otp.rib.EnterOtpRibInteractor` (`submitPhoneNumber`), `ResendOtpRib*`, `ResendOtpTimerDelegate` (`start`).
- `eu.bolt.client.otp.receiver.OtpCodeReceiver` (manifest; `com.whatsapp.otp.OTP_RETRIEVED`) — WhatsApp OTP auto-retrieval.
- `eu.bolt.client.otp.data.ResendOtpPreferenceController`, `ResendOtpOption`.
- `eu.bolt.client.verifyprofile.domain.interactor.ConfirmOtpUseCase` + `ConfirmOtpResult`, `IncorrectOtpException`.
- Email OTP: `SendEmailOtpRib*`, `verifyemail.EmailVerificationRibInteractor` (`verifyCode`, `onResendEmail`, `startResendCodeTimer`).
- Phone-change OTP: `eu.bolt.client.core.profile.domain.interactor.ConfirmPhoneChangeOtpUseCase`.

### 1.3 Google & Facebook sign-in (VERIFIED)
- `eu.bolt.client.login.rib.auth.AuthRibInteractor` (`handleGoogleSignIn`, `handleFacebookSignIn`).
- `SignInRibInteractor` (`loginWithGoogle`, `loginWithFacebook`, `handleFacebookLoginResult`, `handleInvalidExternalJWT`).
- `MfaVerificationRibInteractor` (`loginWithGoogle`, `loginWithFacebook`, `startVerifyWithEmail`).
- `ExternalSignInDelegate`, `TypedSocialSignInEvent`.
- Use cases: `LoginExternalUseCase`, `VerifyExternalUseCase`, `ExternalLoginOrRegisterUseCase`, `GoogleSignInWithoutLastAccountUseCase`, `ExternalProviderBindUseCase` (`updateGoogleTokenAndRetry`, `updateFacebookAccessToken`), `ExternalProviderUnbindUseCase`, `UpdateExternalProviderLoginUseCase`.
- Manifest SDK wiring (Phase 4): Facebook `FacebookActivity`/`FacebookContentProvider`, Google `SignInHubActivity`.
- Error: `FacebookAuthException`.

### 1.4 Biometric authentication (VERIFIED — limited)
- `eu.bolt.biometry.utils.BiometricPromptDelegate` + `android.hardware.biometrics.BiometricPrompt$AuthenticationCallback`.
- Manifest permissions `USE_BIOMETRIC` / `USE_FINGERPRINT` (Phase 4).
- Related: `SaveCustomPinDataUseCase` (`preloadPin`) — a custom PIN alongside biometrics. **INFERRED**: biometric/PIN is used for an app-lock / re-authentication gate; the exact surface (login vs. in-app lock) is not identified → UNKNOWN exact purpose.

### 1.5 Session & authentication state (VERIFIED)
- `eu.bolt.client.login.data.AuthPreferenceController` — auth state/preferences (session persistence).
- `eu.bolt.client.login.data.JwtTokenRepositoryImpl` — `fetchJwtTokens`, `fetchAccessToken`, `fetchAccessTokenLocked`, `rotateRefreshToken`. **JWT tokens are handled client-side** (access + refresh token rotation). Token *values* were intentionally **not** extracted.
- `FetchJwtTokensUseCase`, `GetAccessJwtTokenUseCase`, `RotateRefreshTokenUseCase`, `SaveAuthorizationUseCase`, `ValidateAuthHeaderUseCase` (`setAuthHeader`), `AuthTokenRetrieverDelegate` (`tryToRetrieveAuthToken`).
- `eu.bolt.service.CrossAppLoginService` (Phase 4) + `CrossAppLoginDelegate`, `FindCrossAppCredentialsUseCase`, `SaveCrossAppCredentialsUseCase` — cross-app (Bolt family) shared login.
- Passkeys: `PasskeysActionDelegate` (`handleAddPasskey`, `handleDeletePasskey`), `LoginFlowRibInteractor.discoverPasskeyWhenNoCountryCode`.
- MFA: `MfaVerificationRib*`, `RibMfaVerificationBinding`.
- Account reactivation: `ReactivateAccountRib*` (`startEmailVerification`).
- Account matching: `AccountMatchRib*`, `ConfirmAccountMatchRib*`.
- `StartOverAuthUseCase`, `CleanUserEventUseCase`, `ClearPhoneUuidUseCase`.
- Models: `AuthStateModel`, `AuthOption`, `ExternalLoginBundle`, `PendingExternalLoginBundle`, `PendingProfileInfo`, `PostAuthAction`, `FieldValidationError`.
- Captcha: `CaptchaChallengeDelegate`.

---

## 2. Passenger Profile

### 2.1 Profile creation & editing (VERIFIED)
- `eu.bolt.client.login.domain.interactor.CompleteProfileUseCase`, `CompleteProfileWithNameInteractor` (`submitName`), `EmailCompleteProfileUseCase`.
- `eu.bolt.client.login.rib.signupname.SignupNameRibInteractor` (`updateProfileNamesAndCloseKeyboard`).
- `eu.bolt.client.profile.rib.profileedit.ProfileEditRibInteractor` (`observeEmailVerifiedStatus`).
- `eu.bolt.client.profile.rib.account.AccountRibInteractor` (`handleChangeAppearanceMode`, `handleChangeReportState`, `handlePostRequest`).
- `eu.bolt.client.profile.rib.accountflow.AccountFlowRibInteractor` (`onEditUserPhone`).
- Profile photo verification: `eu.bolt.client.profile.rib.delegate.ProfilePhotoVerificationDelegate` (`executePostRequest`).

### 2.2 Name, phone & email handling (VERIFIED)
- Name: `SignupNameRib*`, `CompleteProfileWithNameInteractor.submitName`.
- Phone: `onEditUserPhone`, `ConfirmPhoneChangeOtpUseCase`, `ChangeNumberDeeplinkMapper`, `PhoneCountryProvider`.
- Email: `EmailEditRibInteractor` (verify email, `observeSendAgainButtonClicks`), `EmailVerificationRib*`.
- `EditSanadRib*` — edits a "Sanad" field (a localised name/identifier field; exact semantic UNKNOWN).

### 2.3 Saved places & favourite locations (VERIFIED)
- `eu.bolt.client.profile.domain.mapper.AccountFavoriteAddressMapper`.
- `ee.mtakso.client.newbase.deeplink.dispatcher.FavoriteAddressDispatcher` (Phase 4/5) — favourite-address deep link.
- (Address search/save is in Phase 6's `AddressSearch*` scope; favourite addresses surface in profile via `AccountFavoriteAddressMapper`.)

### 2.4 Account preferences (VERIFIED)
- `eu.bolt.client.profile.rib.language.LanguageSelect*` — language preference.
- `AccountRibInteractor.handleChangeAppearanceMode` — appearance/theme.
- `ProfileSectionRibInteractor` (`linkFacebookAccount`, `linkGoogleAccount`) — linked external accounts.
- `com.russhwolf.settings.SettingsInitializer` (Phase 4 manifest startup provider) — multiplatform key-value settings store backing these preferences.

---

## 3. Cancellation

### 3.1 Entry points (VERIFIED)
- `ee.mtakso.client.core.interactors.BaseCancelRideUseCase`, `ee.mtakso.client.core.interactors.CancelRideV2UseCase` — ride-hailing cancellation use cases.
- `eu.bolt.client.cancelride.BaseCancelRideDelegate` (`onCancellationConfirmed`) — cancellation UI delegate.
- `eu.bolt.ridehailing.core.domain.model.CancelRideNavigationScreen`, `CancelRideNotification`.
- Deep-link: `Analytics$RideHistoryCancelOrderBottomSheet` (ride history cancellation).

### 3.2 Reason selection (VERIFIED)
- `eu.bolt.client.scheduledrides.core.domain.model.CancelRideReason` — cancellation-reason model.
- (Carsharing/micromobility equivalents from Phase 5: `CarsharingCancelOrderUseCase`, `CancelOrderConfirmationsFlowRib*` with `selectedReasonsFlow`.)

### 3.3 Cancellation fee / penalty UI (VERIFIED — presence; semantics INFERRED)
- `CancelRideException` with nested types `Error.ConfirmationRequired` (`BottomSheetActions`, `CancellationConfirmationImage`, `Normal`) — the client renders a **confirmation-required** flow (consistent with a cancellation-fee warning/confirmation). The monetary fee computation is backend-only; only the confirmation-required UI contract is observable.

### 3.4 Confirmation & error handling (VERIFIED)
- `BaseCancelRideDelegate.onCancellationConfirmed`.
- `CancelRideResponse` / `CancelRideErrorResponse` (network).
- `CancelRideException` (typed error/confirmation handling).

---

## 4. Ratings and Feedback

### 4.1 Driver rating (VERIFIED)
- `ee.mtakso.client.core.interactors.order.SubmitFinishedOrderRatingUseCase`.
- `eu.bolt.ridehailing.core.data.repo.OrderRepository.submitFinishedOrderRating`.
- `SubmitOrderRatingRequest` / `SubmitOrderRatingResponse` / `RatingAutoSubmissionRequest` (network).
- `SubmitOrderRatingEntity`.
- `eu.bolt.ridehailing.ui.ribs.activerideflow.finishedrideflow.finishedride.RideFinishedRibInteractor.submitFinishedOrderRating`, `interactor.SubmitAutoRatingUseCase`.

### 4.2 Trip feedback & comments (VERIFIED — partial)
- Feedback is submitted through the same `SubmitOrderRating*` pipeline (rating + optional comment carried in the request entity `SubmitOrderRatingEntity`).
- Micromobility: `RideFinishedFeedbackRating`, `FinishRideFeedbackRatingNetworkModel`.
- No dedicated ride-hailing "comment" class surfaced by name → free-text comment is **INFERRED** to be a field of `SubmitOrderRatingEntity`/request.

### 4.3 Favourite driver (UNKNOWN / INFERRED)
- `DriverDetails.isFavorite()` exists (Phase 5) — the driver object carries a favourite flag.
- No dedicated "favourite driver" management class was found (`FavoriteDriver` → 0 matches). Favourite-driver toggling is **INFERRED** to be part of the rating/feedback flow; a standalone feature was **not** confirmed → UNKNOWN.

### 4.4 App rating (Google Play) (VERIFIED)
- `eu.bolt.client.apprating.domain.*`: `ShowGoogleInAppRatingUseCase`, `ShowInAppRatingUseCase`, `ShouldShowDefaultInAppRatingUseCase`, `SaveRatingPromptActionUseCase`, `DefaultAppRatingRib*`.
- `RefreshHomeAfterRatingUseCase`, `AppRatingPreferenceController`, `AppRatingAction`.

---

## 5. Notifications

### 5.1 FCM registration & handlers (VERIFIED)
- `ee.mtakso.client.fcm.FcmListenerService` (manifest), `FirebaseMessagingService`, `FirebaseInstanceIdReceiver`.
- Push handlers `ee.mtakso.client.fcm.handlers.*`: `CarsharingPushHandler`, `LiveActivityDispatcherPushHandler`, `VoipPushHandler`, plus obfuscated `c,d,e,f,h,i,j,k,l,n` and `liveactivity.a–d` (Phase 5). The ride-hailing push handlers are obfuscated → UNKNOWN specifics.
- Braze: `BrazePushReceiver`, `BrazeHuaweiPushHandler`, `NotificationTrampolineActivity`.

### 5.2 Notification permission (VERIFIED)
- `eu.bolt.client.login.ui.NotificationPermissionModalProvider`, `ShouldAskForNotificationPermissionUseCase`, `SetUserResolvedPushPermissionRequestUseCase` — notification-permission request flow.
- Manifest `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS`, `USE_FULL_SCREEN_INTENT` (Phase 4).

### 5.3 Notification categories (INFERRED)
- No explicit "notification category" enum surfaced. Category separation is **INFERRED** from handler/consumer classes: FCM order/driver updates, VOIP (`VoipPushHandler`), carsharing (`CarsharingPushHandler`), live activity (`LiveActivityDispatcherPushHandler` + `liveactivity.*`), chat (`NotificationDeleteIntentReceiver`), signup (`SignupNotificationUpdateReceiver`, BOOT_COMPLETED), Braze marketing. Exact channel definitions UNKNOWN.

### 5.4 Deep-link navigation from notifications (VERIFIED — mechanism; INFERRED — specifics)
- Notifications route through deep-link dispatchers (`ee.mtakso.client.newbase.deeplink.dispatcher.*`, e.g. `SupportDispatcher`, `PaymentsDispatcher`, `OpenRideHailingDispatcher`) and `ResolveInitialNavigationStateUseCase` (Phase 5). `NotificationTrampolineActivity` (Braze) is a trampoline. Concrete per-notification navigation maps are obfuscated → UNKNOWN specifics.

### 5.5 In-app notification handling (VERIFIED)
- Live-Activity receivers (Phase 4): `DismissedLiveActivityReceiver`, `LiveActivitySkipTipsReceiver`, carsharing/micromobility `DismissedOrderLiveActivityReceiver`.
- `NotificationDeleteIntentReceiver` (chat notification delete).

---

## 6. Customer Support

### 6.1 Help & support entry points (VERIFIED)
- `ee.mtakso.client.newbase.deeplink.dispatcher.SupportDispatcher` — support deep-link entry.
- `eu.bolt.client.core.support.domain.usecase.GetSupportServiceUseCase`, `GetSupportWebViewServiceInfoUseCase`.
- `eu.bolt.client.core.support.domain.model.SupportAction`, `…network.model.SupportActionPayloadResponse`.
- `eu.bolt.client.support.web.SupportWebRibInteractor` (`startPhoneCall`) — phone support; `SupportWebRib*` — web-view support; `SupportFlowRib*`.

### 6.2 Ride-related complaints (INFERRED)
- No dedicated "complaint" class exists (`Complaint` → 0 matches). Complaints are **INFERRED** to be raised via the generic service-desk flow: `eu.bolt.servicedesk.report.usecase.SendServiceDeskReportUseCase` (`createSupportTicket`) and `eu.bolt.client.bugreport.domain.model.SupportTicketLabel`.

### 6.3 Contact & chat (VERIFIED)
- `SupportWebRibInteractor.startPhoneCall` (contact by phone).
- `eu.bolt.client.chat.*` (Phase 5) — in-app chat module (`eu.bolt.chat.*`, `NotificationDeleteIntentReceiver`).
- `ContactOption` list on `Order` (Phase 5) — call/chat the driver.

### 6.4 Incident reporting & SOS (VERIFIED)
- `ee.mtakso.client.ribs.root.ridehailing.safetytoolkit.sosintegration.service.IncidentReportingService` (Phase 4, `foregroundServiceType=location`) — `observeIncidentId`, `startObservingLocation`, `startSubmittingUpdates`, `startObservingLocationPermission`.
- `IncidentMonitor` (`doStart`).
- `eu.bolt.rhsafety.core.data.repo.IncidentReportingRepository` (`createIncident`, `updateIncident`); `CreateIncidentUseCase`, `ObserveIncidentUseCase`, `UpdateIncidentUseCase`; `IncidentUpdateException`.
- Related safety: `TripAudioRecordingService` (Phase 4), `EstimatedLocationRib*` (Phase 6), analytics `SafetyToolkit$List$CancelRideTap`, `SafetyToolkitMessageBoltSupportTap`.

---

## 7. Data and Privacy

### 7.1 Locally stored preferences & configuration (VERIFIED — names only)
- `eu.bolt.client.login.data.AuthPreferenceController` — auth/session state.
- `eu.bolt.client.otp.data.ResendOtpPreferenceController` — OTP resend state.
- `eu.bolt.client.apprating.domain.*` + `AppRatingPreferenceController` — rating prompt state.
- `eu.bolt.ridehailing.ui.ribs.activerideflow.activeride.screenshoteta.ShareEtaScreenshotPreferenceController` (Phase 5).
- `com.russhwolf.settings.SettingsInitializer` (Phase 4) — shared key-value settings.
- **No credential/token values were read.** JWT handling is confined to `JwtTokenRepositoryImpl`; token contents were not extracted.

### 7.2 Account deletion (VERIFIED)
- `eu.bolt.client.profile.rib.deletionflow.AccountDeletionFlowRib*`, `AccountDeletionFlowState`, `AccountDeletionFlowController`, `ChangeNumberDeeplinkMapper`.
- `eu.bolt.client.core.profile.domain.interactor.GetCheckUserDeleteAccountUseCase`, `…ProfileNetworkRepository.checkDeleteAccount` — deletion eligibility/check (remote).
- Data export (related): `ee.mtakso.client.newbase.deeplink.dispatcher.OpenPersonalDataExportDispatcher` (Phase 4/5).

### 7.3 Logout (VERIFIED)
- `ee.mtakso.client.ribs.root.loggedin.LoggedInDeeplinkHandler.handleLogoutDeeplink`.
- `eu.bolt.client.logoutcleanable.LogoutCleanableRepositoriesHolder` (`cleanAllRepositories`, `notifyLogoutStarted`, `notifyLogoutEnded`) — repository/state cleanup on logout.
- `eu.bolt.ridehailing.core.monitor.SessionEndMonitor.revokeSessionOnLogout` — session revocation on logout.
- `LoginFlowRibInteractor.logoutAndAttachSignInScreen`.

### 7.4 Terms / privacy consent (VERIFIED)
- `AgreeToTermsUseCase`, `AgreeToTermsRib*` (`handleAgreeButtonClick`).

---

## 8. Client vs Backend Boundary

- **Client (VERIFIED/INFERRED):** phone/email sign-up and sign-in UI, OTP code entry/resend/auto-retrieve, Google/Facebook sign-in, MFA and passkey UI, biometric/PIN prompt, profile edit (name/phone/email/language/appearance), favourite-address mapping, cancellation reason/confirmation UI, rating/feedback UI, app-rating prompts, FCM push handling, notification-permission flow, support web/phone entry, incident/SOS foreground service and monitoring, account-deletion flow, logout cleanup.
- **Backend (UNKNOWN, not claimed):** OTP generation/delivery, JWT issuance and rotation policy, external (Google/Facebook) token verification, account matching logic, cancellation-fee computation, rating aggregation, support ticketing, incident dispatch to emergency services. None is observable here.

---

## 9. Limitations & Unresolved Questions

1. **Obfuscation:** ride-hailing push handlers, cancellation fee logic, and rating request fields are partially/fully obfuscated (`fcm.handlers.c–n`, `SubmitOrderRatingEntity` internals). Specifics are UNKNOWN.
2. **No runtime/network:** no live auth flows, token values, or API calls were observed; token contents intentionally not extracted.
3. **Favourite driver:** `DriverDetails.isFavorite` exists but no dedicated feature class found — UNKNOWN whether a standalone favourite-driver flow exists.
4. **Biometric purpose:** `BiometricPromptDelegate` exists but its exact gate (app lock vs. login re-auth vs. payment) is UNKNOWN.
5. **Notification categories:** no enum surfaced; category structure is INFERRED from handler/consumer classes.
6. **Complaint flow:** no "complaint" class; routed via service-desk (`SendServiceDeskReportUseCase`) — INFERRED.
7. **APK split:** analysis limited to `base.apk`.
