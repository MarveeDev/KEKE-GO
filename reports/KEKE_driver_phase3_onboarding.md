# BOLT Driver — Phase 3: Onboarding & Identity Verification

**Target:** `C:\REA-BOLT\artifacts\driver\base.apk`
**SHA-256:** `3d0513c2a394566826980389fe44db799949506f5512b34384c59cf82ac1cdf0`
**Package:** `ee.mtakso.driver`, versionName `DA.155.1`, versionCode `941`
**Tooling:** REA MCP + JADX headless 0.7.1 (class inventory + `get_class_summary`).
**Scope:** Read-only static analysis. No APK modification, no runtime, **no extraction of credentials/tokens/personal data**.

Confidence labels:
- **VERIFIED** — directly observed in JADX class/metadata or the Phase 1/2 manifest/assets.
- **INFERRED** — deduced from naming/dependencies; not proven by bytecode.
- **UNKNOWN** — not resolvable from static evidence (heavy obfuscation).

**Overarching note:** The Driver app is ProGuard/R8-obfuscated more aggressively than Passenger. The onboarding subsystem exists as a **step machine** whose 16 steps and the go-online result states are obfuscated (`OnBoardingStep` subclasses `steps.a`–`p`, `GoOnlineFlowResult` subclasses `a`–`g`). Readable anchors survive only at module/enum level. Backend approval rules are **not** observable and are **not** claimed.

---

## 1. Driver Registration

### 1.1 Entry points (VERIFIED)
- `ee.mtakso.driver.ui.screens.login.LoginActivity` (manifest) — login screen.
- `ee.mtakso.driver.ui.screens.launch.LauncherActivity` — launcher; routes to login/onboarding.
- Deep links `boltdriverapp://`, `taxifydriverapp://` (Phase 2) — registration/deep-link entry.

### 1.2 Phone registration & OTP (VERIFIED)
- `ee.mtakso.driver.platform.google.autofill.GmsSmsListener` (manifest receiver; `com.google.android.gms.auth.api.phone.SMS_RETRIEVED`) — Google SMS Retriever auto-reads the OTP.
- `ee.mtakso.driver.service.integration.whatsapp.WhatsAppOtpCodeBroadcastReceiver` (manifest; `com.whatsapp.otp.OTP_RETRIEVED`) — WhatsApp OTP auto-retrieve.
- These confirm phone-number OTP flows (VERIFIED at receiver level); the exact `requestCode`/`verifyCode` use-case classes are **UNKNOWN** (obfuscated).

### 1.3 Email & account information (INFERRED)
- The onboarding step machine includes steps beyond phone (see §1.5); email/profile capture is **INFERRED** but specific email-signup classes were not surfaced by readable name.

### 1.4 External authentication (VERIFIED)
- Google Sign-In (`SignInHubActivity`, `RevocationBoundService`), Facebook SDK (`FacebookActivity`, `CustomTabActivity`), androidx Credential Manager + FIDO/identity-credentials (`play-services-fido`, `identity-credentials.properties` — Phase 1) and passkey assets.
- OTP auto-retrieve is the primary sign-up path (WhatsApp + SMS), consistent with driver onboarding.

### 1.5 Account-creation workflow (VERIFIED — mechanism; UNKNOWN — specifics)
`ee.mtakso.driver.onboarding.steps.OnBoardingStep` (VERIFIED):
- A sealed/abstract step model with inner enums `OnBoardingStep.Type` and `OnBoardingStep.Severity`, fields for progress/order (`c`, `d`), optional integers (`e`, `f`), and a `Severity` (blocking vs optional).
- `g(ActivityResultLauncher<Intent>, ActivityResultLauncher<String>)` → `routing.command.h<Fragment>` — each step maps to a navigable Fragment screen.
- `h(): boolean`.
- **16 concrete steps** exist: `ee.mtakso.driver.onboarding.steps.a` … `p` (VERIFIED, names obfuscated). Their individual semantics (phone, email, profile, vehicle, document) are **UNKNOWN**.

---

## 2. Identity Verification

### 2.1 Verification SDK (VERIFIED)
- `eu.bolt.verification.sdk.VerificationSDKActivity` (manifest activity).
- `eu.bolt.verification.sdk.VerificationSDKConfiguration` — SDK configuration.
- `eu.bolt.driver.verification.identity.*` — identity verification module (`DataBinderMapperImpl`, `config.a–d`, and obfuscated `a–l`).

### 2.2 Verification result handling (VERIFIED)
`eu.bolt.driver.verification.identity.InternalVerificationStatus` (enum, readable):
- `FAILED`
- `IN_PROGRESS`
- `PENDING`
- `VERIFIED`

This is the client-side verification-state model — four states (VERIFIED) that drive onboarding UI and (INFERRED) are mirrored from a backend approval status.

### 2.3 Document scanning & camera (VERIFIED)
- `CAMERA` permission + `uses-feature android.hardware.camera` (Phase 2).
- `androidx.core.content.FileProvider` (`ee.mtakso.driver.fileprovider`, `@xml/documents_scanner_paths`) — document scanning storage.
- CameraX (`MetadataHolderService` + Camera2 default provider, Phase 2).
- On-device document detector: `veritas_document_detector_v1.tflite` (Phase 1 asset) — "Veritas" document detection.

### 2.4 ML Kit & TensorFlow Lite (VERIFIED — libraries & models present)
- Native: `libface_detector_v2_jni.so`, `libimage_processing_util_jni.so`, `libmlkit_google_ocr_pipeline.so`, `libsurface_util_jni.so`, `libtensorflowlite_jni.so`.
- Assets: `mlkit-google-ocr-models/` (OCR), `models_bundled/` (face/liveness models).

### 2.5 Face verification & liveness (INFERRED)
- `models_bundled/` contains face/liveness models: `blazeface.tfl`, `fssd_*.tflite`, `BCLjoy_200.emd`, `BCLlefteyeclosed_200.emd`, `BCLrighteyeclosed_200.emd` (eye-closed detectors), `LMprec_600.emd` (landmark precision), `contours.tfl`.
- **INFERRED**: the app performs on-device face detection + liveness (blink/eye-open) checks during identity verification. No behavioral proof; the presence of these models is VERIFIED but their exact role is INFERRED.

---

## 3. Vehicle Registration

- **UNKNOWN (specifics).** No readable namespace found for vehicle registration:
  - `VehicleRegistration` → 0 matches.
  - `driver.vehicle` → 0 matches.
  - `driver.car` → not present.
- **INFERRED**: vehicle information/category/attribute forms and vehicle-document (registration certificate, insurance, roadworthiness) workflows are **embedded in the obfuscated onboarding step machine** (`OnBoardingStep` `steps.a–p`) and/or the `ee.mtakso.driver.verification.*` module. The `OnBoardingStep.Type` enum (obfuscated) would enumerate these step kinds.
- **UNKNOWN**: vehicle approval states (a distinct "vehicle approved/pending/rejected" enum was **not** surfaced; only the identity `InternalVerificationStatus` enum is readable).

---

## 4. Driver Eligibility

### 4.1 Go-online gating (VERIFIED)
- `ee.mtakso.driver.service.modules.status.GoOnlineFlowResult` — a **sealed class with 7 subclasses** (`a`–`g`), representing the distinct go-online outcomes (VERIFIED structure; outcome names obfuscated → UNKNOWN).
- `ee.mtakso.driver.ui.screens.work.GoOnlineButton` — the go-online control.
- `ee.mtakso.driver.ui.screens.work.GoOnlineIssueDialogDelegate` — "go online issue" dialog that surfaces blockers preventing the driver from going online.

### 4.2 Onboarding completion / activation (INFERRED)
- `OnBoardingStep.Severity` (enum) distinguishes blocking vs non-blocking steps; incomplete **mandatory** steps are INFERRED to gate go-online.
- Activation/approval is **backend-driven**; the client only renders `GoOnlineFlowResult` and the issue dialog. No approval rule is invented here.

### 4.3 Restrictions preventing online (VERIFIED — mechanism; UNKNOWN — specifics)
- The 7 `GoOnlineFlowResult` states + `GoOnlineIssueDialogDelegate` prove a restrictions/blockers concept exists. The specific blocker categories (documents, vehicle, verification, background check) are **UNKNOWN** (obfuscated).

---

## 5. Driver Profile

- **VERIFIED** anchors: `LoginActivity`, `VerificationSDKActivity`, onboarding steps, `eu.bolt.driver.chat.ui.screen.conversation.ConversationActivity` (chat), `ee.mtakso.driver.service.modules.status.*` (status).
- **UNKNOWN** specifics: driver profile-edit, document-list, account preferences, and driver rating classes were **not** identified by readable name (they are obfuscated within `ee.mtakso.driver.*`). Passenger's `eu.bolt.client.profile.*` is **not** assumed to be shared.

---

## 6. Onboarding Communication

### 6.1 Backend API interfaces (UNKNOWN)
- Specific Retrofit-style endpoints for registration/verification/vehicle upload were **not** surfaced by readable name (obfuscated). Phase 1 shows standard networking (OkHttp; Ktor/Retrofit INFERRED).

### 6.2 Document upload mechanism (INFERRED)
- `FileProvider` + `documents_scanner_paths` (VERIFIED) produce scannable document files; upload to a backend is **INFERRED** (no endpoint observed). Veritas/TFLite processing is **local**.

### 6.3 Error handling & status updates (VERIFIED — model level)
- `InternalVerificationStatus` (FAILED/IN_PROGRESS/PENDING/VERIFIED) is the client-side verification status model.
- `GoOnlineFlowResult` (7 states) is the go-online result model.
- `GoOnlineIssueDialogDelegate` renders blockers.

### 6.4 Notification mechanisms (VERIFIED)
- FCM `FirebasePushService`/`FirebaseMessagingService`, Braze, Mixpanel push (Phase 2) — used for verification/onboarding status notifications (INFERRED linkage).

---

## 7. Local vs Backend Boundary (explicit)

- **Local (VERIFIED/INFERRED):** OTP entry/auto-retrieve UI, onboarding step navigation (`OnBoardingStep.g()` → Fragment), document scanning via camera + FileProvider, on-device document detection (Veritas/TFLite), face/liveness model inference (ML Kit/TFLite), verification-status rendering, go-online button + issue dialog.
- **Backend (UNKNOWN, not claimed):** OTP generation/delivery, identity/background approval, document authenticity review, vehicle approval, eligibility decision, go-online authorization. The client consumes `InternalVerificationStatus` and `GoOnlineFlowResult` from the backend; the backend rules are not observable and are not described.

---

## 8. Unresolved Questions (for subsequent investigation)

1. **Onboarding step semantics:** what do `OnBoardingStep` `steps.a`–`p` and the `OnBoardingStep.Type`/`Severity` enums concretely represent (phone, email, profile, vehicle, document, etc.)? Requires decompiling each step class or the enum `<clinit>`.
2. **Go-online blockers:** what are the 7 `GoOnlineFlowResult` states (`a`–`g`)? Requires decompiling the subclasses.
3. **Registration use cases:** where are the driver's phone/email sign-up, OTP confirm, and external-login use cases (not under `driver.login`/`driver.auth`; not `eu.bolt.client.login.SignupUseCase`)?
4. **Vehicle registration & approval:** no readable vehicle namespace or approval enum surfaced — is vehicle approval folded into `InternalVerificationStatus` or a separate obfuscated enum?
5. **Backend endpoints:** exact registration/verification/document-upload API interfaces are unresolved.
6. **Face/liveness role:** confirm which model runs for "selfie/liveness" vs. document detection.
7. **Play Integrity** usage path (Phase 2 INFERRED) is not yet linked to a specific onboarding step.

---

## 9. Limitations

1. Heavy obfuscation limits name-level discovery; most onboarding internals are single-letter.
2. No runtime/network observation; conclusions are static.
3. No credentials/tokens/personal data were extracted.
4. Split APKs (native libs/density) were not decompiled this phase (native libs identified by filename in Phase 1).
5. Backend approval/eligibility logic is explicitly out of scope (not observable, not claimed).
