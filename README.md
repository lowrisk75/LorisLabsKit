# LorisLabsKit

[![CI](https://github.com/lowrisk75/LorisLabsKit/actions/workflows/ci.yml/badge.svg)](https://github.com/lowrisk75/LorisLabsKit/actions/workflows/ci.yml)

Shared SwiftUI utilities for the LorisLabs app portfolio. Built for iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+.

Current version: **0.3.0** — see [CHANGELOG.md](CHANGELOG.md).

## What's inside

### `SmartReviewPromptManager`
Smart App Store review prompt with launch/success/error tracking and Apple-cap-aware cooldowns.
Requires iOS 17+/macOS 14+.

```swift
let reviewManager = SmartReviewPromptManager(bundleIdentifier: Bundle.main.bundleIdentifier!)

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(reviewManager)
        }
    }
}

// In your view, on a moment of success:
@Environment(\.requestReview) var requestReview
@Environment(SmartReviewPromptManager.self) var reviewManager

// After user views a captured event:
.task { reviewManager.requestIfAppropriate(via: requestReview) }
```

Or even simpler with the modifier:
```swift
EventDetailView(event: event)
    .reviewPromptOnAppear(reviewManager)
```

### `MoreFromLorisLabsView`
Drop-in cross-promotion view for Settings → "More from LorisLabs".

```swift
Section("More from LorisLabs") {
    MoreFromLorisLabsView(currentBundleIdentifier: Bundle.main.bundleIdentifier!)
}
```

The portfolio list lives in `LorisLabsApp.portfolio`. Add new apps there as the catalog grows.

### `LorisLabsPaywallView`
Reusable StoreKit-2 paywall with configurable tiers, popular badges, save badges, and per-app accent color.

```swift
LorisLabsPaywallView(
    headline: "Unlock Lumen Pro",
    subhead: "Unlimited cameras, AI features, all platforms.",
    features: ["Unlimited cameras", "Face recognition", "License plate", "Apple Watch + TV + Vision Pro"],
    tiers: [
        PaywallTier(id: "monthly", displayName: "Monthly", priceText: "$2.99 / mo", billingCadence: .monthly),
        PaywallTier(id: "annual", displayName: "Annual", priceText: "$19.99 / yr",
                    trailingNote: "7-day free trial · less than $2/mo",
                    billingCadence: .annual, isPopular: true, saveBadge: "Save 44%"),
        PaywallTier(id: "lifetime", displayName: "Lifetime", priceText: "$49.99",
                    trailingNote: "One-time purchase", billingCadence: .lifetime),
    ],
    style: PaywallStyle(accentColor: .blue),
    onPurchase: { tier in await myStoreManager.purchase(tier.id) },
    onRestore: { await myStoreManager.restore() },
    onCancel: { dismiss() }
)
```

You can also build `PaywallTier` directly from a StoreKit `Product`:
```swift
let tier = PaywallTier(product: product, isPopular: true, saveBadge: "Save 44%")
```

## ReferralKit

Server-backed refer-a-friend program. Drop-in for any LorisLabs app.

### Quickstart

```swift
import LorisLabsKit

@main struct YourApp: App {
    init() {
        ReferralKit.configure(
            bundleID: Bundle.main.bundleIdentifier!,
            workerURL: URL(string: "https://referrals.lorislab.fr")!
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await ReferralKit.shared.refresh(
                        hmacSecret: AppSecrets.referralHmac
                    )
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL,
                          let link = ReferralDeepLink.parse(url) else { return }
                    // Show ReferralRedeemView with link.code prefilled
                }
        }
    }
}
```

### Wiring entitlement into your gate

```swift
@Observable final class SubscriptionManager {
    var hasPaidPro: Bool {
        purchasedProductIDs.contains(...) || ReferralKit.shared.entitlement.isActive
    }
}
```

### Required app-side config

| Key | Source |
|---|---|
| `bundleID` | `Bundle.main.bundleIdentifier` |
| Worker URL | `https://referrals.lorislab.fr` |
| `HMAC_<SLUG>` | xcconfig at build time (not committed) |
| Associated domain entitlement | Add `applinks:r.lorislab.fr` to entitlements |

### Views

- `ReferralShareView` — referrer's share UI (+ progress bars, share sheet)
- `ReferralRedeemView` — referee's code entry
- `ReferralStatusBanner` — in-flight pipeline status
- `ReferralAmbassadorBadge` — tier 5+ badge

## Adding to a project

In Xcode: **File → Add Package Dependencies → Add Local…** → select this repo's path.

Or in `Package.swift`:
```swift
dependencies: [
    .package(path: "../LorisLabsKit"),
],
```

## Configuration

`SmartReviewPromptManager.Configuration` defaults are sensible for premium-utility apps. Customise per app:

```swift
let config = SmartReviewPromptManager.Configuration(
    minimumLaunches: 5,
    minimumSuccessMoments: 3,
    minimumDaysSinceInstall: 7,
    cooldownDays: 60,
    errorBlackoutDays: 7,
    requireNonTrialUser: true
)
```

## Testing

```bash
swift test
```

## License

Internal LorisLabs use.
