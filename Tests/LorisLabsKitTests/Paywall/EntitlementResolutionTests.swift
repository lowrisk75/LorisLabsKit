import Foundation
import Testing
@testable import LorisLabsKit

/// The decision `refreshEntitlements` makes from what StoreKit returned, the
/// store's reachability and the offline cache. StoreKit itself is not exercised
/// here: `SKTestSession` needs a host app and fails with `invalidApp` under
/// `swift test`.
@Suite struct EntitlementResolutionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private let config = PaywallConfiguration(
        productIDs: ["app.lifetime", "app.pro.monthly", "app.plus.monthly"],
        lifetimeProductIDs: ["app.lifetime"],
        productTierRanks: ["app.pro.monthly": 1, "app.plus.monthly": 2, "app.lifetime": 3],
        keychainService: "com.lorislab.kit.tests.resolution"
    )

    private func tx(_ id: String, expires: Date? = nil, revoked: Date? = nil) -> EntitlementTransactionSnapshot {
        EntitlementTransactionSnapshot(productID: id, expirationDate: expires, revocationDate: revoked)
    }

    private func resolve(
        _ transactions: [EntitlementTransactionSnapshot],
        reachable: Bool = true,
        cached: CachedPaidEntitlement? = nil
    ) -> EntitlementResolution {
        LorisPaywallStore.resolveEntitlement(
            transactions: transactions, configuration: config,
            isStoreReachable: reachable, freshCache: cached, now: now
        )
    }

    // MARK: Online

    @Test func onlineLifetimeIsLifetimeAndCachedAsSuch() {
        let r = resolve([tx("app.lifetime")])
        #expect(r.entitlement == .lifetime)
        #expect(r.purchasedProductIDs == ["app.lifetime"])
        #expect(r.highestTierRank == 3)
        #expect(r.cacheUpdate == .store(CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: now)))
    }

    @Test func onlineTieredSubscriptionKeepsHighestTierAndLatestExpiry() {
        let soon = now.addingTimeInterval(5 * day), later = now.addingTimeInterval(20 * day)
        let r = resolve([tx("app.pro.monthly", expires: soon), tx("app.plus.monthly", expires: later)])
        #expect(r.entitlement == .subscribed(expiration: later))
        #expect(r.highestTierRank == 2)
        #expect(r.subscriptionExpiration == later)
        #expect(r.cacheUpdate == .store(CachedPaidEntitlement(kind: .subscription, productIDs: ["app.pro.monthly", "app.plus.monthly"], subscriptionExpiration: later, verifiedAt: now)))
    }

    @Test func lifetimeWinsOverSubscription() {
        let r = resolve([tx("app.pro.monthly", expires: now.addingTimeInterval(day)), tx("app.lifetime")])
        #expect(r.entitlement == .lifetime)
        if case .store(let cached) = r.cacheUpdate { #expect(cached.kind == .lifetime) } else { Issue.record("expected a cache write") }
    }

    @Test func revokedAndExpiredGrantNothingAndClearTheCache() {
        let r = resolve([tx("app.lifetime", revoked: now), tx("app.pro.monthly", expires: now.addingTimeInterval(-1))])
        #expect(r.entitlement == nil)
        #expect(r.cacheUpdate == .clear)
        // Revoked products are not "owned"; an expired one still is, as before.
        #expect(!r.purchasedProductIDs.contains("app.lifetime"))
    }

    @Test func onlineWithNothingIgnoresAnOldCache() {
        let cached = CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: now)
        let r = resolve([], reachable: true, cached: cached)
        #expect(r.entitlement == nil)
        #expect(r.cacheUpdate == .clear)
        #expect(r.purchasedProductIDs.isEmpty)
    }

    // MARK: Offline

    @Test func offlineLifetimeRestoresAsLifetime() {
        let cached = CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: now.addingTimeInterval(-3600))
        let r = resolve([], reachable: false, cached: cached)
        #expect(r.entitlement == .lifetime)
        #expect(r.purchasedProductIDs == ["app.lifetime"])
        #expect(r.highestTierRank == 3)
        // Keep the record (and its verification time) — not a fresh verification.
        #expect(r.cacheUpdate == .keep)
    }

    @Test func offlineTieredSubscriptionRestoresTier() {
        let expiry = now.addingTimeInterval(10 * day)
        let cached = CachedPaidEntitlement(kind: .subscription, productIDs: ["app.plus.monthly"], subscriptionExpiration: expiry, verifiedAt: now.addingTimeInterval(-3600))
        let r = resolve([], reachable: false, cached: cached)
        #expect(r.entitlement == .subscribed(expiration: expiry))
        #expect(r.highestTierRank == 2)
        #expect(r.subscriptionExpiration == expiry)
        #expect(r.cacheUpdate == .keep)
    }

    @Test func offlineWithoutFreshCacheFallsBackToTrialOrNone() {
        let r = resolve([], reachable: false, cached: nil)
        #expect(r.entitlement == nil)
        #expect(r.cacheUpdate == .clear)
    }

    /// StoreKit can still return local entitlements offline; they win over the cache.
    @Test func offlineButStoreKitReturnedPaidUsesStoreKit() {
        let cached = CachedPaidEntitlement(kind: .subscription, productIDs: ["app.pro.monthly"], subscriptionExpiration: nil, verifiedAt: now.addingTimeInterval(-3600))
        let r = resolve([tx("app.lifetime")], reachable: false, cached: cached)
        #expect(r.entitlement == .lifetime)
        #expect(r.purchasedProductIDs == ["app.lifetime"])
    }
}
