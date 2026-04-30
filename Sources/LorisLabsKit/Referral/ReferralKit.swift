import Foundation

/// Top-level namespace and entry point for the LorisLabs refer-a-friend
/// program. Apps call `ReferralKit.configure(bundleID:, workerURL:)` at
/// launch, then access state via `ReferralKit.shared` or use the SwiftUI
/// views.
@MainActor
public final class ReferralKit {
    /// The shared instance is created lazily by the first `configure(...)`
    /// call. Until then, accessing this throws a fatalError.
    public static var shared: ReferralKit {
        guard let instance = _shared else {
            fatalError("ReferralKit.configure(bundleID:, workerURL:) must be called before accessing ReferralKit.shared")
        }
        return instance
    }
    private static var _shared: ReferralKit?

    /// Bundle identifier the worker uses to scope per-app config.
    public let bundleID: String

    /// Base URL for `referrals.lorislab.fr` (or staging equivalent).
    public private(set) var workerURL: URL

    /// Observable entitlement source-of-truth — drop into your app's
    /// `hasPaidPro` gate.
    public let entitlement: ReferralEntitlement

    private init(bundleID: String, workerURL: URL) {
        self.bundleID = bundleID
        self.workerURL = workerURL
        self.entitlement = ReferralEntitlement()
    }

    /// Configure or reconfigure ReferralKit. Subsequent calls swap the
    /// worker URL (useful for staging) while preserving identity.
    public static func configure(bundleID: String, workerURL: URL) {
        if let existing = _shared, existing.bundleID == bundleID {
            existing.workerURL = workerURL
            return
        }
        _shared = ReferralKit(bundleID: bundleID, workerURL: workerURL)
    }

    /// Test seam: reset shared instance.
    static func _resetForTesting() {
        _shared = nil
    }
}

// MARK: - Refresh

extension ReferralKit {
    /// Refresh entitlement state: hydrate from local cache first (so the UI
    /// shows last-known-good immediately), then fetch fresh from the worker
    /// over the network.
    ///
    /// Call from app launch and after a successful purchase.
    public func refresh(hmacSecret: String) async {
        let identity = ReferralIdentity()
        guard let uuid = try? identity.getOrCreateUUID() else { return }

        // 1. Hydrate from cache if fresh
        let cache = ReferralCache()
        if let cached = try? cache.fetchIfFresh(maxAge: 86_400) {
            entitlement.update(from: cached)
        }

        // 2. Fetch fresh from worker
        let client = ReferralClient(
            workerURL: workerURL,
            bundleID: bundleID,
            hmacSecret: hmacSecret
        )
        do {
            let me = try await client.me(uuid: uuid)
            let signedAt = ISO8601DateFormatter().date(from: me._signedAt) ?? Date()
            let bonusUntil = me.bonusUntil.flatMap { ISO8601DateFormatter().date(from: $0) }
            let cached = ReferralCache.CachedMe(
                uuid: me.uuid,
                code: me.code,
                confirmedReferrals: me.confirmedReferrals,
                pendingReferrals: me.pendingReferrals,
                bonusUntil: bonusUntil,
                tiersUnlocked: me.tiersUnlocked,
                rewardsAvailable: me.rewardsAvailable.map {
                    ReferralCache.CachedReward(tier: $0.tier, promoCode: $0.promoCode, redeemUrl: $0.redeemUrl)
                },
                signedAt: signedAt
            )
            entitlement.update(from: cached)
            try? cache.store(cached)
        } catch {
            // Network failure — keep using cached entitlement
        }
    }
}
