# Changelog

All notable changes to LorisLabsKit are documented here.

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
