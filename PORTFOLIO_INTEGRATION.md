# LorisLabsKit — Per-App Integration Guide

Generic instructions for integrating `LorisLabsKit` into any LorisLabs app. Use this as the template for new apps; see Lumen's `audit-output/lorislabskit-integration-guide.md` for a fully-worked example.

## Step 1 — Add the package

In Xcode: **File → Add Package Dependencies → Add Local…** → select `~/GitHub/LorisLabsKit/`.

Or in your `Package.swift`:
```swift
.package(path: "../LorisLabsKit"),
```

## Step 2 — Add this app to the catalog

Edit `~/GitHub/LorisLabsKit/Sources/LorisLabsKit/CrossPromotion/LorisLabsApp.swift` and append your app to `LorisLabsApp.portfolio`:

```swift
LorisLabsApp(
    name: "<App Name>",
    bundleIdentifier: "com.lorislab.<key>",
    ascAppId: "<ASC App ID>",
    tagline: "<one-line value prop>",
    category: "<Productivity | Utilities | Lifestyle | …>"
),
```

Then commit + push to LorisLabsKit (`git -C ~/GitHub/LorisLabsKit commit -am "Add <App> to portfolio"`).

## Step 3 — Wire the smart review prompt

In your `@main App` struct:

```swift
import LorisLabsKit

@main
struct MyApp: App {
    @State private var reviewManager = SmartReviewPromptManager(
        bundleIdentifier: Bundle.main.bundleIdentifier!
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(reviewManager)
        }
    }
}
```

In your App init or first onAppear, call `reviewManager.recordLaunch()`.

In any "moment of success" view (a successful action the user just completed):
```swift
@Environment(SmartReviewPromptManager.self) private var reviewManager

var body: some View {
    SuccessView()
        .reviewPromptOnAppear(reviewManager)
}
```

In your subscription manager, post trial state changes:
```swift
reviewManager.recordTrialState(.proPaid)   // or .free / .trialActive
```

Anywhere the user hits an error:
```swift
reviewManager.recordError()  // 7-day prompt blackout
```

## Step 4 — Add cross-promotion to Settings

In your `SettingsView`:

```swift
import LorisLabsKit

Section("More from LorisLabs") {
    MoreFromLorisLabsView(currentBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
}
```

The portfolio list filters out the current app automatically.

## Step 5 — Use the reusable paywall (when shipping Pro tier)

Replace any custom paywall view with `LorisLabsPaywallView`:

```swift
LorisLabsPaywallView(
    headline: "Unlock <App> Pro",
    subhead: "<one-line>",
    features: [
        "<feature 1>",
        "<feature 2>",
        "<feature 3>",
    ],
    tiers: [
        PaywallTier(product: monthlyProduct),
        PaywallTier(product: annualProduct, isPopular: true, saveBadge: "Save 44%"),
        PaywallTier(product: lifetimeProduct),
    ],
    style: PaywallStyle(accentColor: <AppBrandColor>),
    onPurchase: { tier in
        do { try await purchase(productID: tier.id) } catch { /* show error */ }
    },
    onRestore: { try? await AppStore.sync() },
    onCancel: { dismiss() }
)
```

## Step 6 — Optional: referral

```swift
let referrals = ReferralManager(appBundleIdentifier: Bundle.main.bundleIdentifier!)

// In Settings → Share row:
let myCode = referrals.generateCodeForCurrentUser()
let url = referrals.shareURL(for: myCode.code)  // https://lorislab.fr/r/<CODE>

// In .onOpenURL:
if let recorded = referrals.recordIncomingReferral(code: incomingCode) {
    // Hand off to your StoreKit Promotional Offer flow
}
```

The actual StoreKit Promotional Offer (granting the discount) is per-app and requires a small signing endpoint — see Lumen's integration guide Step 7.3 for the full pattern.

## Step 7 — Verify

1. `swift build` from your app target — no warnings about LorisLabsKit symbols
2. Build & run in Simulator — review prompt fires on a successful "moment of success" after 5+ launches and 5+ minutes spread across days
3. Settings → "More from LorisLabs" — list shows the other portfolio apps with App Store links
4. (If using paywall) Tier selection works, purchase flow connects to your StoreKit code

## Apps to integrate, in order

| App | Status | Priority | Notes |
|---|---|---|---|
| **Lumen for Frigate** | Live, 1.11 on TestFlight | High | First consumer, see `audit-output/lorislabskit-integration-guide.md` |
| **Clasp** | Live, no IAP yet | High | Add Pro IAP first, then integrate |
| **TypeMetrics** | Live, no IAP yet | Medium | Same — needs IAP first |
| **404 Network** | Live, has IAP | Medium | Cross-promo + review prompt easy adds |
| **Aura** | In-dev | High at ship | Use the reusable paywall day-one |
| **Heol** | In-dev | High at ship | Same |
| **Synthesis (InkWell)** | In-dev | High at ship | Same |
| **Éclair** | In-dev | High at ship | Same |
| **ProofCheck** | In-dev | High at ship | Same |
| **Bilan** | In-dev | Medium at ship | Same |
| **Rampart** | In-dev | Medium at ship | Same |
| **Sinkhole** | In-dev | Low | Free utility, mostly review prompt |
| **AuroraPulse** | In-dev | Low | Free utility |
| **Byty (Terrace)** | In-dev | High at ship | Has paywall already, migrate to LorisLabsPaywallView |

## Updating the package catalog as new apps ship

When an app's status moves from in-dev → live (i.e. it gets an `ascAppId`):

1. Edit `Sources/LorisLabsKit/CrossPromotion/LorisLabsApp.swift`
2. Add the entry to `portfolio` array
3. Bump CHANGELOG.md (e.g. "0.3.0 — Added <App> to portfolio")
4. Bump `Package.swift` version comment
5. `git commit && git push` — CI runs, all consuming apps see the new entry on next build
