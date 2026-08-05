import Foundation

/// Everything an app must declare to use `LorisPaywallStore`.
///
/// Product identifiers are injected rather than hardcoded — that hardcoding is
/// precisely why ~14 apps each grew their own StoreKit manager instead of
/// sharing one.
public struct PaywallConfiguration: Sendable {
    /// Every product the paywall may offer, subscriptions and one-time alike.
    public let productIDs: [String]

    /// Products that grant permanent access once bought (non-consumables).
    public let lifetimeProductIDs: Set<String>

    /// Consumables — tips, one-off unlocks that can be bought again.
    ///
    /// They never appear in `Transaction.currentEntitlements`, so an engine
    /// that only reads entitlements sees a tip purchase as a no-op. Declaring
    /// them here routes the purchase to `onConsumablePurchase` instead.
    public let consumableProductIDs: Set<String>

    /// How many times to retry a failed product load before giving up.
    /// A single attempt loses the storefront to one dropped packet.
    public let productLoadRetries: Int

    /// Subscription group used for renewal monitoring. When nil, the group of
    /// the first auto-renewable product found is used.
    public let subscriptionGroupID: String?

    /// Duration of the app-managed free trial, or nil when the app has none.
    public let trialDuration: TimeInterval?

    /// How long a previously verified entitlement stays trusted while the
    /// device cannot reach the App Store.
    public let offlineTolerance: TimeInterval

    /// How early an expiring subscription should be surfaced to the user.
    public let expiringSoonThreshold: TimeInterval

    /// Keychain service used for trial and cached-entitlement storage.
    public let keychainService: String

    public init(
        productIDs: [String],
        lifetimeProductIDs: Set<String> = [],
        consumableProductIDs: Set<String> = [],
        subscriptionGroupID: String? = nil,
        trialDuration: TimeInterval? = nil,
        offlineTolerance: TimeInterval = 24 * 60 * 60,
        expiringSoonThreshold: TimeInterval = 3 * 24 * 60 * 60,
        productLoadRetries: Int = 3,
        keychainService: String = Bundle.main.bundleIdentifier ?? "com.lorislab.unknown"
    ) {
        self.productIDs = productIDs
        self.lifetimeProductIDs = lifetimeProductIDs
        self.consumableProductIDs = consumableProductIDs
        self.productLoadRetries = max(1, productLoadRetries)
        self.subscriptionGroupID = subscriptionGroupID
        self.trialDuration = trialDuration
        self.offlineTolerance = offlineTolerance
        self.expiringSoonThreshold = expiringSoonThreshold
        self.keychainService = keychainService
    }
}
