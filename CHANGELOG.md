# Changelog

All notable changes to LorisLabsKit are documented here.

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
