# LorisLabsKit

[![CI](https://github.com/lowrisk75/LorisLabsKit/actions/workflows/ci.yml/badge.svg)](https://github.com/lowrisk75/LorisLabsKit/actions/workflows/ci.yml)

Shared SwiftUI utilities for the LorisLabs app portfolio. Built for iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+.

Latest release: **0.10.0** (requires LorisFoundation 0.2.0+) — see [CHANGELOG.md](CHANGELOG.md).

## What's inside

### Sync integrity closure (local, unreleased)

**Behaviour change:** `CloudKitDatabase` now refuses physical data deletion by default (`CloudSyncDeletionError.physicalDeletionDisabled`); the non-atomic preflight below requires an explicit `.allowNonAtomicPreflight`. `CloudSyncEngine` rejects overlapping operations with `operationInProgress` (no queue). Also: outgoing record validation (ASCII name subset, reserved fields, finite values), byte-exact identities, single-profile checks, existing-share permission mismatch errors and an additive host-scoped `ScopedSyncCheckpoint`, which is not account authentication. Sharing is invite-only by default (add people with `SyncShareItem` + SwiftUI `ShareLink`; public links are opt-in); prefer `revokeOwnedShare` / `leaveShare`. Use `synchronize` (server compare-and-set, explicit conflicts) instead of clock-based `reconcile`. Unreadable records are quarantined instead of stalling sync. See [FR/EN contract and limits](Documentation/SYNC-CLOSURE.md).

### Deletion preflight (local, unreleased; not atomic CAS; opt-in since the closure)

Private deletion now validates every requested record's identity/type before one mutation batch. Lookup/type errors prevent all dispatch. Concurrent replacement and provider/cascade gates remain open: this is not atomic typed deletion. See [FR/EN contract](Documentation/SYNC-DELETION-PREFLIGHT.md).

### Field integrity (local, unreleased)

Native mapping now preserves supported numeric values exactly or rejects the whole record; unsupported fields are no longer silently omitted. Schema/boolean/empty-array and provider limits remain explicit. See [FR/EN contract](Documentation/SYNC-FIELD-INTEGRITY.md).

### Checkpoint decoding (local, unreleased)

Present-but-invalid incremental checkpoint bytes now fail before zone setup instead of becoming an implicit first fetch. Preserve original bytes and require explicit host recovery. See [FR/EN contract and remaining provider gates](Documentation/SYNC-CHECKPOINT-DECODING.md).

### Revision outbox (local, unreleased)

RevisionedSyncOutbox provides account/namespace/session-bound local intent and exact mutation receipts. Persist its versioned bytes with domain changes in one host transaction; it is not an independent store, encryption or an automatic CloudKit dispatcher. See [FR/EN API, transaction/lifecycle contract and limits](Documentation/SYNC-REVISION-OUTBOX.md).


### Sync sharing resolution (local, unreleased)

Sharing lookups now propagate non-missing errors, use explicit participant roles and refuse ambiguous private/shared targets before removal. Duplicate short IDs across shared zones fail closed. See [FR/EN contracts and native/account/TOCTOU limits](Documentation/SYNC-SHARING-RESOLUTION.md).


### Sync transport acknowledgements (local, unreleased)

Native writes/setup/subscriptions/share acceptance now validate per-item results and returned identities before reporting success. Errors may still follow remote effects: no automatic replay or rollback promise. See [FR/EN contracts and remaining durability/native gates](Documentation/SYNC-WRITE-ACKNOWLEDGEMENTS.md).


### Sync read integrity (local, unreleased)

LorisSync now drains private/shared query pages and incremental changes, and reports read failures instead of silently returning partial success. See [FR/EN contracts and remaining native/durability gates](Documentation/SYNC-READ-INTEGRITY.md). No app migration or production qualification is implied.


### Security compatibility (local, unreleased)

`LorisKeychain` delegates to adjacent `../LorisFoundation` / `LorisSecurity` without changing service/default-group/storage selectors. Rotation updates value only and never deletes first; existing protection is preserved, not silently rewritten. Empty Data and legacy error mapping remain. See [FR/EN decision and native limits](Documentation/SDK-SECURITY-ADOPTION.md). No app migration or remote release implied.

### Reviews and the app catalogue

Create one `SmartReviewPromptManager` per app process. Record a completed user task once, after it actually completes; navigation, launch, onboarding and purchases are not completion signals. StoreKit remains responsible for whether a prompt appears.

```swift
let reviews = SmartReviewPromptManager(bundleIdentifier: "com.example.app")

// After a real task completes (do not put this in onAppear):
reviews.recordCompletedAction()

// On the completion screen; false during sheets, alerts, editing or other work:
CompletedTaskView()
    .reviewPromptWhenIdle(reviews, isIdle: !showingSheet && !isEditing)
```

Defaults: 14 elapsed days, five completions across three distinct days, a fresh completion in this session, at least two minutes of session use, a two-second quiet pause, 120 days between attempts and at most one attempt per version. Leaving the screen or backgrounding cancels the transient opportunity without consuming the cooldown. Interaction and eligibility are rechecked before requesting. Payment, satisfaction, errors and support history never select reviewers. Legacy `recordSuccessMoment` and `reviewPromptOnAppear` remain compatible, but require the same real completion signals.

Use the optional `additionalEligibility` closure to recheck native modal/window state that SwiftUI does not observe. It runs before and after the quiet pause; returning `false` does not consume an attempt. Keep automatic requests off when the host has no clear completed task followed by an idle screen.

`ReviewAttempt` can conservatively import an earlier request during migration. An attempted request is persisted before StoreKit is invoked, even when StoreKit shows nothing. These conservative thresholds are product defaults, not a measured guarantee of ratings or a claim that the system prompt appeared. [Apple guidance](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews).

The catalogue includes 21 published apps verified against Apple's FR/US listings on 2026-10-15. Official icons and FR/EN descriptions are bundled: no network request, tracking or credential is needed to display the menu. Links use the person's App Store storefront. The current app and its debug/extension bundle variants are excluded.

```swift
// In Settings, inside an existing NavigationStack:
LorisLabsAppsLink(currentBundleIdentifier: "com.example.app")

// Or present LorisLabsAppsMenu in a host-owned sheet/navigation stack.
// Existing Form/List integrations may still use MoreFromLorisLabsView.
```

Run `python3 Scripts/update-portfolio-catalog.py` to refresh the public catalogue and icons. New app descriptions require explicit review in that script; this never publishes an app. Apps using a vendored SDK must update their reviewed snapshot and hashes explicitly. Sève's local integration includes this product alongside its existing frozen LorisReports snapshot.

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

The review thresholds can be configured per app. Keep enough engagement and time between requests, and qualify the actual host triggers rather than relying solely on SDK tests. `errorBlackoutDays` and `requireNonTrialUser` are retained for source compatibility and do not influence eligibility.

## Testing

```bash
swift test
```

## License

Internal LorisLabs use.
