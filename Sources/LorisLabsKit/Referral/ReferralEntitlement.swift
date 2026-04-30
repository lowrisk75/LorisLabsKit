import Foundation
import Observation

@MainActor
@Observable
public final class ReferralEntitlement {
    public private(set) var bonusUntil: Date?
    public private(set) var confirmedReferrals: Int = 0
    public private(set) var pendingReferrals: Int = 0
    public private(set) var tiersUnlocked: Set<String> = []
    public private(set) var availableRewards: [ReferralCache.CachedReward] = []
    public private(set) var lastSyncedAt: Date?

    public var isActive: Bool {
        guard let until = bonusUntil else { return false }
        return until > Date()
    }

    public var progressTowardsTier5: Double {
        min(1.0, Double(confirmedReferrals) / 5.0)
    }

    public var progressTowardsTier10: Double {
        min(1.0, Double(confirmedReferrals) / 10.0)
    }

    public init() {}

    public func update(from me: ReferralCache.CachedMe) {
        self.bonusUntil = me.bonusUntil
        self.confirmedReferrals = me.confirmedReferrals
        self.pendingReferrals = me.pendingReferrals
        self.tiersUnlocked = Set(me.tiersUnlocked)
        self.availableRewards = me.rewardsAvailable
        self.lastSyncedAt = me.signedAt
    }

    public func clear() {
        self.bonusUntil = nil
        self.confirmedReferrals = 0
        self.pendingReferrals = 0
        self.tiersUnlocked = []
        self.availableRewards = []
        self.lastSyncedAt = nil
    }
}
