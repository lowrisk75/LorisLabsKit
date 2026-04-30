import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct ReferralCacheTests {
    @Test func storeAndFetch_roundtrip() throws {
        let cache = ReferralCache(service: "ReferralKit.test.\(UUID().uuidString)")
        let payload = ReferralCache.CachedMe(
            uuid: "u", code: "ABCDEF",
            confirmedReferrals: 3, pendingReferrals: 1,
            bonusUntil: Date(timeIntervalSince1970: 1_750_000_000),
            tiersUnlocked: ["tier5"], rewardsAvailable: [],
            signedAt: Date()
        )
        try cache.store(payload)
        let fetched = try cache.fetch()
        #expect(fetched?.code == "ABCDEF")
        #expect(fetched?.confirmedReferrals == 3)
        try cache.clear()
    }

    @Test func fetch_returnsNilWhenEmpty() throws {
        let cache = ReferralCache(service: "ReferralKit.test.\(UUID().uuidString)")
        #expect(try cache.fetch() == nil)
    }

    @Test func staleCheck_returnsNilWhenSignedAtTooOld() throws {
        let cache = ReferralCache(service: "ReferralKit.test.\(UUID().uuidString)")
        let payload = ReferralCache.CachedMe(
            uuid: "u", code: "ABCDEF", confirmedReferrals: 0, pendingReferrals: 0,
            bonusUntil: nil, tiersUnlocked: [], rewardsAvailable: [],
            signedAt: Date(timeIntervalSinceNow: -25 * 3600)
        )
        try cache.store(payload)
        #expect(try cache.fetchIfFresh(maxAge: 24 * 3600) == nil)
        try cache.clear()
    }
}
