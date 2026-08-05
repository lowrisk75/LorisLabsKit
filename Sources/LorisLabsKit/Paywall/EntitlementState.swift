import Foundation

/// What the user is currently entitled to.
public enum EntitlementState: Sendable, Equatable {
    case none
    case trial(daysRemaining: Int)
    case subscribed(expiration: Date?)
    case lifetime

    /// True whenever paid features should be unlocked, trial included.
    public var isPro: Bool {
        switch self {
        case .none: false
        case .trial, .subscribed, .lifetime: true
        }
    }

    /// True only for a genuine purchase — use this to decide whether to keep
    /// nudging the user toward the paywall.
    public var isPaid: Bool {
        switch self {
        case .none, .trial: false
        case .subscribed, .lifetime: true
        }
    }
}

/// Health of an auto-renewable subscription.
///
/// No app in the portfolio surfaced this before: a subscription failing to
/// renew looked exactly like an active one until the day it vanished.
public enum RenewalStatus: Sendable, Equatable {
    /// No auto-renewable subscription is active (lifetime buyers land here too).
    case notSubscribed

    /// Renewing normally.
    case active(expiration: Date?)

    /// Still valid, but auto-renew is off — it will lapse on `expiration`.
    case expiringSoon(expiration: Date)

    /// Payment failed; Apple is retrying while access continues until `until`.
    case inGracePeriod(until: Date?)

    /// Payment failed and access has stopped while Apple retries.
    case inBillingRetry

    /// Refunded or revoked by Apple.
    case revoked

    /// Lapsed.
    case expired

    /// Cases the app should act on — prompt to update payment, or win back.
    public var needsAttention: Bool {
        switch self {
        case .notSubscribed, .active: false
        case .expiringSoon, .inGracePeriod, .inBillingRetry, .revoked, .expired: true
        }
    }
}
