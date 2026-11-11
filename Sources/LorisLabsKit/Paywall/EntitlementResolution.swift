import Foundation

/// The parts of a verified StoreKit transaction the entitlement decision reads.
struct EntitlementTransactionSnapshot: Sendable, Equatable {
    var productID: String
    var expirationDate: Date?
    var revocationDate: Date?
}

/// What `refreshEntitlements` should publish and do with the offline cache.
struct EntitlementResolution: Equatable {
    enum CacheUpdate: Equatable {
        /// Freshly verified paid entitlement.
        case store(CachedPaidEntitlement)
        /// Verified not paid, or offline with nothing fresh to trust.
        case clear
        /// Restored from the cache: leave the record and its verification time alone.
        case keep
    }

    /// Paid entitlement, or nil when not paid (the store then falls back to the trial).
    var entitlement: EntitlementState?
    var subscriptionExpiration: Date?
    var purchasedProductIDs: Set<String>
    var highestTierRank: Int
    var cacheUpdate: CacheUpdate
}

extension LorisPaywallStore {
    /// Pure decision behind `refreshEntitlements`: StoreKit's answer first, then
    /// — only when the store was unreachable — a fresh cached entitlement with
    /// its kind and products, so lifetime stays lifetime and tiers survive offline.
    ///
    /// - Parameter freshCache: the cached entitlement already filtered by
    ///   `offlineTolerance`, or nil.
    nonisolated static func resolveEntitlement(
        transactions: [EntitlementTransactionSnapshot],
        configuration: PaywallConfiguration,
        isStoreReachable: Bool,
        freshCache: CachedPaidEntitlement?,
        now: Date
    ) -> EntitlementResolution {
        var isLifetime = false
        var subscriptionExpiry: Date?
        var foundPaid = false
        var owned: Set<String> = []

        for transaction in transactions where transaction.revocationDate == nil {
            owned.insert(transaction.productID)

            if configuration.lifetimeProductIDs.contains(transaction.productID) {
                isLifetime = true
                foundPaid = true
            } else if let expiry = transaction.expirationDate {
                if expiry > now {
                    foundPaid = true
                    subscriptionExpiry = max(subscriptionExpiry ?? expiry, expiry)
                }
            } else {
                // Non-consumable not declared as lifetime — still a purchase.
                isLifetime = true
                foundPaid = true
            }
        }

        func rank(_ ids: Set<String>) -> Int {
            ids.compactMap { configuration.productTierRanks[$0] }.max() ?? 0
        }

        if foundPaid {
            return EntitlementResolution(
                entitlement: isLifetime ? .lifetime : .subscribed(expiration: subscriptionExpiry),
                subscriptionExpiration: subscriptionExpiry,
                purchasedProductIDs: owned,
                highestTierRank: rank(owned),
                cacheUpdate: .store(CachedPaidEntitlement(
                    kind: isLifetime ? .lifetime : .subscription,
                    productIDs: owned,
                    subscriptionExpiration: isLifetime ? nil : subscriptionExpiry,
                    verifiedAt: now
                ))
            )
        }

        if !isStoreReachable, let cached = freshCache {
            // Offline and previously paid — keep the same kind and tier rather
            // than locking the user out of (or downgrading) an app they bought.
            return EntitlementResolution(
                entitlement: cached.entitlementState,
                subscriptionExpiration: cached.subscriptionExpiration,
                purchasedProductIDs: cached.productIDs,
                highestTierRank: cached.highestTierRank(ranks: configuration.productTierRanks),
                cacheUpdate: .keep
            )
        }

        return EntitlementResolution(
            entitlement: nil,
            subscriptionExpiration: subscriptionExpiry,
            purchasedProductIDs: owned,
            highestTierRank: rank(owned),
            cacheUpdate: .clear
        )
    }
}
