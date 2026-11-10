import Foundation
import LorisLabsKit
import Security
import StoreKit
import StoreKitTest
import Testing

private final class BundleToken {}

/// End-to-end paywall tests against StoreKitTest: real `Product`,
/// `Transaction.currentEntitlements`, purchases and refunds, from a local
/// configuration. Offline is simulated by making product loading fail, which
/// is how `LorisPaywallStore` learns the App Store is unreachable.
///
/// Writes to the login keychain under a unique service per test and deletes it
/// afterwards.
@MainActor
@Suite(.serialized) struct PaywallStoreKitTests {
    static let lifetime = "com.lorislab.kit.test.lifetime"
    static let pro = "com.lorislab.kit.test.pro.monthly"
    static let plus = "com.lorislab.kit.test.plus.monthly"

    let session: SKTestSession
    let keychainService = "com.lorislab.kit.tests.storekit.\(UUID().uuidString)"

    init() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "PaywallTest", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    private func store() -> LorisPaywallStore {
        LorisPaywallStore(configuration: PaywallConfiguration(
            productIDs: [Self.lifetime, Self.pro, Self.plus],
            lifetimeProductIDs: [Self.lifetime],
            productLoadRetries: 1,
            productTierRanks: [Self.pro: 1, Self.plus: 2, Self.lifetime: 3],
            keychainService: keychainService
        ))
    }

    private func cleanUp(_ store: LorisPaywallStore) {
        store.stop()
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ] as CFDictionary)
    }

    private func buy(_ id: String, with store: LorisPaywallStore) async throws {
        let product = try #require(store.products.first { $0.id == id })
        let ok = await store.purchase(product)
        #expect(ok, "purchase failed: \(store.lastError ?? "no error")")
    }

    private func goOffline() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
    }

    // MARK: Online

    @Test func lifetimePurchaseIsLifetime() async throws {
        let s = store(); defer { cleanUp(s) }
        await s.start()
        #expect(s.products.count == 3)

        try await buy(Self.lifetime, with: s)

        #expect(s.entitlement == .lifetime)
        #expect(s.purchasedProductIDs == [Self.lifetime])
        #expect(s.highestTierRank == 3)
    }

    @Test func tieredSubscriptionReportsItsTier() async throws {
        let s = store(); defer { cleanUp(s) }
        await s.start()

        try await buy(Self.plus, with: s)

        guard case .subscribed(let expiration) = s.entitlement else {
            Issue.record("expected a subscription, got \(s.entitlement)"); return
        }
        #expect(expiration != nil)
        #expect(s.highestTierRank == 2)
        #expect(s.purchasedProductIDs.contains(Self.plus))
    }

    @Test func refundRemovesAccess() async throws {
        let s = store(); defer { cleanUp(s) }
        await s.start()
        try await buy(Self.lifetime, with: s)

        let transaction = try #require(session.allTransactions().first { $0.productIdentifier == Self.lifetime })
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        // The test session applies the refund asynchronously; give it up to 2 s.
        for _ in 0..<20 where s.entitlement.isPaid {
            try await Task.sleep(for: .milliseconds(100))
            await s.refreshEntitlements()
        }

        #expect(!s.entitlement.isPaid)
        #expect(s.highestTierRank == 0)
    }

    // MARK: Offline

    /// The regression the boolean cache caused: offline, a lifetime buyer
    /// came back as a subscriber with no products and no tier.
    @Test func offlineRestoreKeepsLifetimeAndTier() async throws {
        let online = store(); defer { cleanUp(online) }
        await online.start()
        try await buy(Self.lifetime, with: online)
        online.stop()

        // StoreKit no longer vouches for the purchase and the store is unreachable.
        session.clearTransactions()
        try await goOffline()
        let offline = store()
        await offline.start()

        #expect(offline.entitlement == .lifetime)
        #expect(offline.purchasedProductIDs == [Self.lifetime])
        #expect(offline.highestTierRank == 3)
    }

    @Test func offlineRestoreKeepsSubscriptionTier() async throws {
        let online = store(); defer { cleanUp(online) }
        await online.start()
        try await buy(Self.plus, with: online)
        online.stop()

        session.clearTransactions()
        try await goOffline()
        let offline = store()
        await offline.start()

        guard case .subscribed = offline.entitlement else {
            Issue.record("expected a subscription, got \(offline.entitlement)"); return
        }
        #expect(offline.highestTierRank == 2)
        #expect(offline.purchasedProductIDs == [Self.plus])
    }

    /// Online and nothing owned: the cache is cleared, so a later offline
    /// launch grants nothing.
    @Test func verifiedUnpaidClearsTheCache() async throws {
        let s = store(); defer { cleanUp(s) }
        await s.start()
        try await buy(Self.lifetime, with: s)

        session.clearTransactions()
        await s.refreshEntitlements() // reachable: verified, not paid
        #expect(!s.entitlement.isPaid)

        try await goOffline()
        let offline = store()
        await offline.start()
        #expect(!offline.entitlement.isPaid)
        #expect(offline.purchasedProductIDs.isEmpty)
    }
}
