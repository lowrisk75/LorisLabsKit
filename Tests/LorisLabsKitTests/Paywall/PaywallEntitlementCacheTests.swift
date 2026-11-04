import Foundation
import LorisSecurityTesting
import Testing
@testable import LorisLabsKit

/// Offline restore of a paid entitlement. The cache used to hold one boolean,
/// so a lifetime buyer came back offline as `.subscribed(expiration: nil)` and
/// tiered apps lost the owned products (and so the tier) until the store answered.
@Suite struct PaywallEntitlementCacheTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let verifiedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func cache(_ backend: InMemoryLegacyKeychainBackend = InMemoryLegacyKeychainBackend()) -> PaywallEntitlementCache {
        PaywallEntitlementCache(keychain: LorisKeychain(service: "com.lorislab.kit.tests.paywall", backend: backend))
    }

    @Test func lifetimeRestoresAsLifetimeWithOwnedProducts() {
        let c = cache()
        c.save(CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: verifiedAt))

        let restored = c.freshEntitlement(now: verifiedAt.addingTimeInterval(3600), tolerance: day)
        #expect(restored?.kind == .lifetime)
        #expect(restored?.entitlementState == .lifetime)
        #expect(restored?.productIDs == ["app.lifetime"])
    }

    @Test func tieredSubscriptionRestoresTierAndExpiration() {
        let c = cache()
        let expiry = verifiedAt.addingTimeInterval(20 * day)
        c.save(CachedPaidEntitlement(kind: .subscription, productIDs: ["app.pro.monthly", "app.plus.yearly"], subscriptionExpiration: expiry, verifiedAt: verifiedAt))

        let restored = c.freshEntitlement(now: verifiedAt.addingTimeInterval(3600), tolerance: day)
        #expect(restored?.entitlementState == .subscribed(expiration: expiry))
        #expect(restored?.productIDs == ["app.pro.monthly", "app.plus.yearly"])
        let ranks = ["app.pro.monthly": 1, "app.plus.yearly": 2]
        #expect(restored?.highestTierRank(ranks: ranks) == 2)
    }

    @Test func staleCacheIsNotTrusted() {
        let c = cache()
        c.save(CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: verifiedAt))
        #expect(c.freshEntitlement(now: verifiedAt.addingTimeInterval(day + 1), tolerance: day) == nil)
    }

    @Test func clearingRemovesThePaidEntitlement() {
        let c = cache()
        c.save(CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: verifiedAt))
        c.save(nil, verifiedAt: verifiedAt.addingTimeInterval(60))
        #expect(c.freshEntitlement(now: verifiedAt.addingTimeInterval(120), tolerance: day) == nil)
    }

    /// A device upgraded from a build that wrote only the boolean keeps access
    /// offline, with the old (subscription, no products) meaning.
    @Test func legacyBooleanCacheStillRestores() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.lorislab.kit.tests.paywall", backend: backend)
        try keychain.save("1", forKey: "loris.paywall.cached.paid")
        try keychain.save(String(verifiedAt.timeIntervalSince1970), forKey: "loris.paywall.lastVerified")

        let restored = PaywallEntitlementCache(keychain: keychain)
            .freshEntitlement(now: verifiedAt.addingTimeInterval(3600), tolerance: day)
        #expect(restored?.entitlementState == .subscribed(expiration: nil))
        #expect(restored?.productIDs == [])
    }

    /// The legacy keys keep being written so rolling the app back to an older
    /// kit build does not lock a paying user out offline.
    @Test func saveAlsoWritesLegacyKeys() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.lorislab.kit.tests.paywall", backend: backend)
        PaywallEntitlementCache(keychain: keychain)
            .save(CachedPaidEntitlement(kind: .lifetime, productIDs: ["app.lifetime"], subscriptionExpiration: nil, verifiedAt: verifiedAt))
        #expect(try keychain.string(forKey: "loris.paywall.cached.paid") == "1")
        #expect(try keychain.string(forKey: "loris.paywall.lastVerified") == String(verifiedAt.timeIntervalSince1970))
    }

    @Test func corruptRecordFallsBackToNothing() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.lorislab.kit.tests.paywall", backend: backend)
        try keychain.save("{not json", forKey: "loris.paywall.cached.entitlement")
        try keychain.save("0", forKey: "loris.paywall.cached.paid")
        #expect(PaywallEntitlementCache(keychain: keychain)
            .freshEntitlement(now: verifiedAt, tolerance: day) == nil)
    }
}
