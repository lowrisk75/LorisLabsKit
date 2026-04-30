import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct ReferralEntitlementTests {
    @Test func isActive_falseWhenBonusUntilNil() {
        let e = ReferralEntitlement()
        #expect(e.isActive == false)
    }

    @Test func isActive_falseWhenBonusUntilPast() {
        let e = ReferralEntitlement()
        e.update(from: ReferralCache.CachedMe(
            uuid: "u", code: "ABCDEF",
            confirmedReferrals: 0, pendingReferrals: 0,
            bonusUntil: Date(timeIntervalSinceNow: -3600),
            tiersUnlocked: [], rewardsAvailable: [],
            signedAt: Date()
        ))
        #expect(e.isActive == false)
    }

    @Test func isActive_trueWhenBonusUntilFuture() {
        let e = ReferralEntitlement()
        e.update(from: ReferralCache.CachedMe(
            uuid: "u", code: "ABCDEF",
            confirmedReferrals: 1, pendingReferrals: 0,
            bonusUntil: Date(timeIntervalSinceNow: 30 * 86400),
            tiersUnlocked: [], rewardsAvailable: [],
            signedAt: Date()
        ))
        #expect(e.isActive == true)
        #expect(e.confirmedReferrals == 1)
    }

    @Test func progressTowards5_capsAt1() {
        let e = ReferralEntitlement()
        e.update(from: ReferralCache.CachedMe(
            uuid: "u", code: "ABCDEF",
            confirmedReferrals: 7, pendingReferrals: 0,
            bonusUntil: nil, tiersUnlocked: ["tier5"],
            rewardsAvailable: [], signedAt: Date()
        ))
        #expect(e.progressTowardsTier5 == 1.0)
        #expect(e.progressTowardsTier10 == 0.7)
    }
}
