import Foundation

/// A verified paid entitlement, remembered so access survives a period offline.
///
/// Holds the kind and the owned products, not just "paid": with a boolean, a
/// lifetime buyer came back offline as a subscriber and a tiered app lost the
/// tier until the App Store answered.
struct CachedPaidEntitlement: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case lifetime
        case subscription
    }

    var kind: Kind
    var productIDs: Set<String>
    /// Latest expiration seen when the entitlement was verified; nil for lifetime.
    var subscriptionExpiration: Date?
    var verifiedAt: Date

    var entitlementState: EntitlementState {
        switch kind {
        case .lifetime: .lifetime
        case .subscription: .subscribed(expiration: subscriptionExpiration)
        }
    }

    /// Recomputed from the app's current ranks, so a re-ranked tier applies offline too.
    func highestTierRank(ranks: [String: Int]) -> Int {
        productIDs.compactMap { ranks[$0] }.max() ?? 0
    }
}

/// Keychain storage for `CachedPaidEntitlement`.
///
/// Also keeps writing the two legacy keys (`cached.paid`, `lastVerified`), so
/// an app rolled back to an older kit build still finds a paying user offline,
/// and reads them when no full record exists yet (device upgraded from such a build).
struct PaywallEntitlementCache {
    static let recordKey = "loris.paywall.cached.entitlement"
    static let legacyPaidKey = "loris.paywall.cached.paid"
    static let legacyVerifiedKey = "loris.paywall.lastVerified"

    let keychain: LorisKeychain

    /// Records a verified paid entitlement.
    func save(_ entitlement: CachedPaidEntitlement) {
        save(entitlement, verifiedAt: entitlement.verifiedAt)
    }

    /// Records the result of a successful store read; `nil` means "verified, not paid".
    func save(_ entitlement: CachedPaidEntitlement?, verifiedAt: Date) {
        if let entitlement, let data = try? JSONEncoder().encode(entitlement) {
            try? keychain.save(data, forKey: Self.recordKey)
        } else {
            try? keychain.delete(forKey: Self.recordKey)
        }
        try? keychain.save(entitlement == nil ? "0" : "1", forKey: Self.legacyPaidKey)
        try? keychain.save(String(verifiedAt.timeIntervalSince1970), forKey: Self.legacyVerifiedKey)
    }

    /// The cached paid entitlement if it was verified less than `tolerance` ago.
    func freshEntitlement(now: Date, tolerance: TimeInterval) -> CachedPaidEntitlement? {
        guard let cached = stored(), now.timeIntervalSince(cached.verifiedAt) < tolerance else { return nil }
        return cached
    }

    private func stored() -> CachedPaidEntitlement? {
        if let data = try? keychain.data(forKey: Self.recordKey),
           let record = try? JSONDecoder().decode(CachedPaidEntitlement.self, from: data) {
            return record
        }
        // Legacy boolean: keep its old meaning (subscription, products unknown).
        guard (try? keychain.string(forKey: Self.legacyPaidKey)) == "1",
              let raw = try? keychain.string(forKey: Self.legacyVerifiedKey),
              let seconds = TimeInterval(raw) else { return nil }
        return CachedPaidEntitlement(
            kind: .subscription,
            productIDs: [],
            subscriptionExpiration: nil,
            verifiedAt: Date(timeIntervalSince1970: seconds)
        )
    }
}
