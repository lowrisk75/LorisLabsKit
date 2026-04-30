# Changelog

All notable changes to LorisLabsKit are documented here.

## [0.3.0] — 2026-04-29

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
