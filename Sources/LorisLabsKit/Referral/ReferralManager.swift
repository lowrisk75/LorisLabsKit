import Foundation

/// Foundation for app-side referral tracking. Per-app StoreKit Promotional Offer
/// integration (the actual unlock mechanic) lives in each consuming app — this
/// type only handles code generation, sharing, and bookkeeping that's shared
/// across the portfolio.
///
/// Usage outline:
/// ```swift
/// let referrals = ReferralManager(appBundleIdentifier: Bundle.main.bundleIdentifier!)
/// let myCode = referrals.generateCodeForCurrentUser()
/// // Pass myCode to a Share sheet
///
/// // When the app receives a deep link or the user pastes a code:
/// if let referrer = referrals.recordIncomingReferral(code: code) {
///     // Hand off to the app's StoreKit Promotional Offer flow to apply the discount
/// }
/// ```
@MainActor
@Observable
public final class ReferralManager {

    public struct GeneratedCode: Equatable, Sendable {
        public let code: String
        public let createdAt: Date
    }

    public struct RedeemedCode: Equatable, Sendable {
        public let code: String
        public let referredBy: String?  // optional: who shared this code
        public let redeemedAt: Date
    }

    private enum Key {
        static let issuedCode = "lorislabskit.referral.issuedCode"
        static let issuedAt = "lorislabskit.referral.issuedAt"
        static let redeemedCode = "lorislabskit.referral.redeemedCode"
        static let redeemedAt = "lorislabskit.referral.redeemedAt"
        static let redeemedReferrer = "lorislabskit.referral.redeemedReferrer"
    }

    private let userDefaults: UserDefaults
    private let appBundleIdentifier: String

    public init(appBundleIdentifier: String, userDefaults: UserDefaults = .standard) {
        self.appBundleIdentifier = appBundleIdentifier
        self.userDefaults = userDefaults
    }

    // MARK: - Issued (this user's outgoing share code)

    /// Returns the user's existing referral code or generates one if absent.
    /// Code format: 8-character base32 (Crockford-safe) — short, friend-shareable, hard to mistype.
    @discardableResult
    public func generateCodeForCurrentUser() -> GeneratedCode {
        if let stored = userDefaults.string(forKey: Key.issuedCode),
           let createdAt = userDefaults.object(forKey: Key.issuedAt) as? Date {
            return GeneratedCode(code: stored, createdAt: createdAt)
        }
        let code = ReferralCodeFormat.makeShareableCode()
        let now = Date()
        userDefaults.set(code, forKey: Key.issuedCode)
        userDefaults.set(now, forKey: Key.issuedAt)
        return GeneratedCode(code: code, createdAt: now)
    }

    public var issuedCode: GeneratedCode? {
        guard let stored = userDefaults.string(forKey: Key.issuedCode),
              let createdAt = userDefaults.object(forKey: Key.issuedAt) as? Date else { return nil }
        return GeneratedCode(code: stored, createdAt: createdAt)
    }

    /// Universal-link URL pattern for sharing this code. Apps wire this to a
    /// `apple-app-site-association`-supporting domain (e.g. lorislab.fr/r/<code>).
    public func shareURL(for code: String, baseURL: URL = URL(string: "https://lorislab.fr/r/")!) -> URL {
        baseURL.appending(path: code)
    }

    // MARK: - Incoming (a code we received and want to redeem)

    /// Validate + store an incoming referral code. Returns the recorded value, or
    /// nil if the code is malformed or has already been redeemed for this device.
    @discardableResult
    public func recordIncomingReferral(code: String, referredBy: String? = nil) -> RedeemedCode? {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReferralCodeFormat.isValid(normalized) else { return nil }
        // Don't allow self-referral (your own code can't redeem on your own device).
        if let issued = userDefaults.string(forKey: Key.issuedCode), issued == normalized {
            return nil
        }
        // Already-redeemed? One redemption per device.
        if userDefaults.string(forKey: Key.redeemedCode) != nil { return nil }
        let now = Date()
        userDefaults.set(normalized, forKey: Key.redeemedCode)
        userDefaults.set(now, forKey: Key.redeemedAt)
        if let by = referredBy {
            userDefaults.set(by, forKey: Key.redeemedReferrer)
        }
        return RedeemedCode(code: normalized, referredBy: referredBy, redeemedAt: now)
    }

    public var redeemedCode: RedeemedCode? {
        guard let code = userDefaults.string(forKey: Key.redeemedCode),
              let date = userDefaults.object(forKey: Key.redeemedAt) as? Date else { return nil }
        return RedeemedCode(
            code: code,
            referredBy: userDefaults.string(forKey: Key.redeemedReferrer),
            redeemedAt: date
        )
    }

    // MARK: - Reset (debug / sign-out)

    public func resetIssued() {
        userDefaults.removeObject(forKey: Key.issuedCode)
        userDefaults.removeObject(forKey: Key.issuedAt)
    }

    public func resetRedeemed() {
        userDefaults.removeObject(forKey: Key.redeemedCode)
        userDefaults.removeObject(forKey: Key.redeemedAt)
        userDefaults.removeObject(forKey: Key.redeemedReferrer)
    }
}

/// Crockford-safe base32 alphabet (no I, L, O, U) — 8 chars = ~40 bits of entropy.
public enum ReferralCodeFormat {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let length = 8

    public static func makeShareableCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &rng) ?? "0" })
    }

    public static func isValid(_ candidate: String) -> Bool {
        guard candidate.count == length else { return false }
        let allowed = Set(alphabet)
        return candidate.allSatisfy { allowed.contains($0) }
    }
}
