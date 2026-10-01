# Changelog

All notable changes to LorisLabsKit are documented here.

## [0.9.0] — 2026-10-01

### Added — secure Feedback v2

- `FeedbackCenter`, consent review, private conversation and operator status UI.
- Versioned report envelopes with category-level consent and a fail-closed
  redaction pipeline.
- HTTPS-only transport that refuses redirects, preserves idempotency and keeps a
  bounded seven-day outbox after uncertain delivery.
- Device-only Keychain capabilities, a bounded opt-in diagnostic journal and
  closed diagnostic adapters for Velya, Lumen and Éclair.
- Privacy manifests for `LorisReports` and the shared package resources.

### Changed — review prompts

- Review eligibility now uses meaningful completions, distinct active days and a
  120-day attempt cooldown with an injectable clock.
- Paid status, satisfaction answers and error history never gate eligibility.
  Apps must keep Help and a manual review action independently reachable.

### Verification

- 114 package tests executed with three iCloud-Keychain-only referral tests
  skipped; privacy manifests, `git diff --check` and Gitleaks passed.
- A dedicated signed iPhone harness passed Keychain accessibility, complete file
  protection, offline/retry preservation and uninstall/reinstall persistence.
  The harness and its synthetic marker were removed after qualification.
- Public Help is live separately at `https://help.lorislab.fr`; publishing this
  package version does not deploy or mutate that service.

## [0.8.0] — 2026-08-05

### Added — `LorisPaywall`, the StoreKit engine the kit never had
The kit shipped `LorisLabsPaywallView` (231 lines of UI) with **no engine**, so
~14 apps each wrote their own StoreKit manager with product identifiers compiled
in. Seeded per the 2026-07-29 rule — from the richest implementations (Clasp's
offline tolerance, Lumen's trial), not the most elegant.

- `PaywallConfiguration` — product identifiers injected, plus lifetime,
  consumable and tier declarations. The hardcoding is what caused the forks.
- `EntitlementState` — `none` / `trial` / `subscribed` / `lifetime`, with
  `isPro` (unlock features) distinct from `isPaid` (stop nudging).
- `LorisTrialService` — trial in the **keychain**, not `UserDefaults`, where
  deleting the app's data handed out a fresh trial. `migrateLegacyStart`
  adopts an existing `UserDefaults` trial so nobody restarts or loses days.
- `LorisPaywallStore` — `@Observable` engine: purchase, restore, transaction
  listener, offline tolerance, offer codes.

### Added — four capabilities no app in the portfolio had
Each was found while migrating a real app, not designed up front.

- **`RenewalStatus`** from `subscriptionGroupStatus` + `renewalInfo`. Nothing
  read these: a subscription in billing retry looked exactly like a healthy one
  until it vanished.
- **`entitlementsLoaded`** — UI gates must not show a paywall before entitlements
  are read. Lumen shipped without it and paying subscribers hit the paywall on
  every cold launch (reported 2026-05-22).
- **`isRestoring` / `restoreFoundNothing`** — a restore that failed was logged and
  nothing else, so the button read as dead (reported by a paying subscriber,
  2026-07-25). "Sync worked but this Apple ID owns nothing" is now distinct from
  a failure.
- **Consumables** — tips never reach `Transaction.currentEntitlements`, so an
  entitlement-only engine completes the purchase and never thanks the buyer.
  `onConsumablePurchase` fires from both the purchase call and the listener.

### Added — platform and robustness
- `purchase(confirmIn:)` on tvOS/visionOS, which reject the plain call. Without
  it LumenTV purchases would have broken outright.
- `loadProducts` retries with exponential backoff. One dropped packet used to
  leave an empty paywall and no way to pay.
- `productTierRanks` — access in levels (404's free/pro/aiPlus, Clasp's
  pro/proPlus) instead of a boolean.

### Adopted by
Lumen (iOS ✅ build), TypeMetrics (macOS ✅ build), 404 (committed, unverified).

### Known gaps
- The package still does not compile for **watchOS**: `Review/` guards tvOS but
  not watchOS (`d728fb2`), untouched by this work.
- 55 tests pass; builds verified on macOS, tvOS and visionOS.

## [0.7.0] — 2026-07-29

### Changed — `SyncRecord` carries typed fields, not one opaque blob
**This is what makes `LorisSync` adoptable at all.** Records modelled a payload as
a single JSON `blob`, which fits the one app the engine was extracted from and *no
other*: every app in the portfolio stores typed CloudKit fields — Éclair 168 of
them, Clasp 23, 404 and Fleck 15, Aura 11, Aegis and ProofCheck 8-10. Adopting the
engine would have meant rewriting each app's CloudKit schema and migrating live
user data, and for a shared record, breaking participants still on the old version.

- `SyncValue` — string, int, double, bool, date, data, stringList, intList.
  `Codable`, so records can be cached offline.
- `SyncRecord.fields: [String: SyncValue]`, plus typed accessors (`record.int("hour")`)
  that return `nil` on a type mismatch rather than guessing.
- `blob` survives as a **computed** field, so `CloudSyncEngine`'s `Codable` path and
  every existing call site keep working untouched. A whole-payload JSON is now just
  a field named `blob`.
- `CloudKitDatabase` reads and writes the full schema: an app keeps its record
  layout and needs **no migration**.

### Notes
- CloudKit has no boolean type — booleans are stored as numbers, so a round-trip
  cannot tell `true` from `1`. `SyncValue.from` returns `.int` and callers use
  `record.bool(_:)` only on fields they wrote as booleans; guessing would silently
  corrupt integer fields holding 0 or 1.
- **7 new tests** (26 total for `LorisSync`): typed round-trip, mismatch returns nil,
  blob backwards compatibility, blob on a typed record, persistence, `Codable` values.
- Verified: `swift build` (macOS), `xcodebuild -destination 'generic/platform=iOS'`,
  `swift test` — 43 tests, 0 failures.

## [0.6.0] — 2026-07-29

### Added — `LorisSync` sharing (`CKShare`)
The last capability keeping six apps (Aura, Clasp, Éclair, Halte, Piscine, Velya)
away from the shared engine.

- `SharedCloudDatabase` — refines `CloudDatabase`, so non-sharing conformers and
  mocks are untouched.
  - `share(recordID:type:title:permission:)` → `ShareInfo`. **Idempotent**: CloudKit
    refuses a second share on one record, so reuse is silent rather than an error
    every caller must guard against.
  - `existingShare(recordID:type:)`, `acceptShare(at:)`, `fetchShared(type:)`,
    `stopSharing(recordID:type:)`.
  - `accept(metadata:)` on `CloudKitDatabase` for the path the system actually
    uses (`userDidAcceptCloudKitShareWith`).
- `ShareInfo.isOwner` — owners revoke, participants leave. Conflating the two ships
  a "Remove" button that fails for half the users.
- `ShareError` — `invalidShare`, `recordNotFound`, `notOwner`.

### The trap this locks down
Shared records live in `sharedCloudDatabase`, a **different database** from the
private one. `fetchAll` never returns them. An app that assumes one database shows
the owner their own data and participants nothing at all — so
`testSharedRecordsNeverAppearInThePrivateFetch` asserts the two stores stay
separate, and the mock keeps them in separate dictionaries on purpose.

### Notes
- Seeded from Velya's `CloudKitShareManager`, the portfolio's most complete
  implementation.
- **10 new tests** (19 total for `LorisSync`): idempotent share, unknown record,
  private/shared separation, double accept, malformed link, owner-revokes vs
  participant-leaves.
- Verified: `swift build` (macOS), `xcodebuild -destination 'generic/platform=iOS'`,
  `swift test` — 36 tests, 0 failures.

## [0.5.0] — 2026-07-29

### Added — `LorisSync` can finally sync incrementally and be woken by push
`LorisSync` shipped as a full-fetch engine: every sync re-downloaded the whole
zone, with no server push and no way to learn about deletions. That is correct
for the one small profile it was extracted from (Mela/ProfileSyncKit), and it is
why **no app adopted it** — seven apps in the portfolio need `CKSubscription`
and four need change tokens, so migrating would have *removed* capability.

- `IncrementalCloudDatabase` — refines `CloudDatabase` rather than replacing it,
  so existing conformers and mocks keep compiling untouched.
  - `registerChangeSubscription(id:)` — silent push on zone change, idempotent.
  - `fetchChanges(type:since:)` → `ZoneChanges` (changed, deletedIDs, token, wasReset).
- `ZoneChanges.wasReset` — set when the server rejects an aged-out token. The
  payload is then a full snapshot, not a delta; callers must replace rather than
  merge. Getting this wrong loses records silently, which is why it is explicit.
- Change tokens cross the API as opaque `Data`, so nothing above the CloudKit
  adapter imports CloudKit.
- `ChangeTokenStore` + `UserDefaultsChangeTokenStore` — persistence behind a
  protocol (App Group suite when an extension syncs too; otherwise each process
  keeps its own token and they fight). Stores the suite *name*, not a
  `UserDefaults` instance, which is not Sendable under Swift 6.
- Deletions now propagate. Without `deletedIDs`, a deleted record resurrects on
  the next upload.

### Fixed
- `CloudKitDatabase`'s header claimed the engine was "fully tested against
  `MockCloudDatabase`". No such mock and no `LorisSync` test target existed.
  Both now do: **9 tests** covering token advance, empty deltas, deletion
  propagation, expired-token reset, idempotent subscription, account gating and
  the token store.

### Notes
- Seeded from Velya's `SharedAlarmSync`, the only engine in the portfolio with
  subscriptions, change tokens and sharing together — following the rule that made
  `LorisReports` succeed: **extract from the most complete implementation, not the
  most elegant one.**
- Still missing before this can replace a rich engine: `CKShare` (six apps use it).
- Verified: `swift build` (macOS), `xcodebuild -destination 'generic/platform=iOS'`,
  and `swift test` — 17 tests, 0 failures.

## [0.4.2] — 2026-07-29

### Fixed — `LorisDesignCore` high-contrast card border was invisible in light mode
- `LorisDesignTokens.cardBorderHighContrast` defaulted to `.white.opacity(0.55)`.
  That colour is applied only when the user has asked for increased contrast, and
  on a light background a white border is exactly what they cannot see — the
  setting made the card edge *less* visible for the people it exists to help.
  Now `.primary.opacity(0.4)`, which adapts to the colour scheme. This is what
  404's PulseUI used; the value was changed during the port into the kit.
- Nothing consumes `LorisDesignCore` yet, so no app's appearance changes.
- Verified: `swift build` (macOS) and `xcodebuild -destination 'generic/platform=iOS'`
  both succeed.

### Note for adopters
`GlassCard` is **not** a drop-in swap. The kit's defaults differ from every existing
copy — e.g. 404/PulseUI uses cornerRadius 20 against the kit's 14. Adopting apps must
set `LorisDesignTokens.current` to their own values at launch to keep visual parity.

## [0.4.1] — 2026-07-28

### Fixed — `LorisReports` bundle delivery on macOS
- `BugReportConversationView.generateBundle()` and `BugReportFormView.generateBundle()`
  presented the package's `ShareSheet` on every platform. On macOS that view is only a
  stub reading *"Sharing not yet supported on this platform — open the bundle URL
  manually"*, so a macOS user who generated a report hit a dead end and had no way to
  send it. Both call sites are now platform-aware: iOS keeps the share sheet, while
  non-UIKit targets dismiss and leave delivery to the host's
  `BugReportContextProvider.generateBundle` (open Mail, reveal in Finder…).
- Ported from Clasp's fork, which carried the correct behaviour. **TypeMetrics** (macOS,
  already on `LorisReports` and shipping) is fixed by this change too.
- Verified: `swift build` (macOS, exercises the new branch) and
  `xcodebuild -destination 'generic/platform=iOS'` both succeed.

## [0.4.0] — 2026-07-25

### Added — "app chassis" v2 (modular products; apps import only what they use)
- `LorisSync` — protocol-abstracted CloudKit sync engine (seeded from Mela/ProfileSyncKit,
  the best-abstracted of the portfolio's 9 hand-rolled sync engines).
- `LorisReports` — in-app bug reports + triage, with localization and tests (seeded from
  Lumen's BugReportKit, canonical of the 5 divergent forks: Clasp/404/Lumen/lumen-bridge/TypeMetrics).
- `LorisDesignCore` — shared `LorisDesignTokens` + canonical `GlassCard` (ported from
  404/PulseUI, the richest of the 4 copies: contrast/reduce-transparency aware, macOS
  variant, Liquid Glass border on iOS 18+).
- `Licensing/` in LorisLabsKit: `TrialManager` (keychain-backed trial clock, per-bundle
  namespace) and `LicenseVerifier` + `LicenseStore` (offline RS256 JWT verification,
  parameterized issuer/product/public-key/machine-id) — generalized from Throttle's
  TrialService/LicenseService so the license worker pattern works for every app.

### Notes
- Existing `LorisLabsKit` target untouched — Clasp's and Lumen's imports keep working.
- Clasp now consumes the package via a relative symlink (its stale git clone is gone).

## [0.3.0] — 2026-04-29

### Added
- `ReferralKit` namespace: end-to-end refer-a-friend integration with `referrals.lorislab.fr` worker.
  - `ReferralKit.configure(bundleID:, workerURL:)`
  - `ReferralIdentity` (iCloud Keychain UUID)
  - `ReferralClient` (lookup / share / claim / me with HMAC verification)
  - `ReferralCache` (keychain-backed offline cache)
  - `ReferralEntitlement` (Observable bonus state)
  - `ReferralDeepLink` (Universal Link parser)
  - `ReferralPurchaseHelper` (StoreKit appAccountToken)
  - SwiftUI views: `ReferralShareView`, `ReferralRedeemView`, `ReferralStatusBanner`, `ReferralAmbassadorBadge`

### Removed
- Legacy `ReferralManager` (local-only code generator). Replaced by the
  new server-backed `ReferralKit` (worker-validated, HMAC-signed).

## [0.2.0] — 2026-04-25

### Added
- **`LorisLabsPaywallView`** — reusable SwiftUI paywall with configurable tiers, popular badges, save badges, accent color and styling. Builds `PaywallTier` directly from a StoreKit `Product`.
- **`PaywallStyle`** — visual configuration (accent / background / card / button strings).
- **`ReferralManager`** — foundation for app-side referral tracking. Generates 8-char Crockford-base32 share codes, persists in `UserDefaults`, validates incoming codes, prevents self-referral and duplicate redemption per device.
- **`ReferralCodeFormat`** — code-generation + validation utility.
- **CI workflow** (`.github/workflows/ci.yml`) — runs `swift build` + `swift test` on macOS 15.

### Internal
- 22 unit tests across 5 suites — all passing.
- `swift test` clean.

## [0.1.0] — 2026-04-25

### Added
- **`SmartReviewPromptManager`** — smart App Store review prompt with launch / success / error tracking, Apple-cap aware, configurable cooldowns.
- **`MoreFromLorisLabsView`** — drop-in cross-promotion list for Settings.
- **`LorisLabsApp.portfolio`** — canonical app catalog (Lumen, LumenTV, Clasp, TypeMetrics, 404 Network).
- 11 unit tests.
- README + Package.swift.
