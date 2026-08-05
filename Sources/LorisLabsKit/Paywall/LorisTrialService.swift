import Foundation

/// App-managed free trial, stored in the keychain.
///
/// The copies this replaces kept the start date in `UserDefaults`, where
/// deleting the app's data — or offloading and reinstalling it — handed the
/// user a fresh trial every time. Keychain items outlive app removal, so a
/// trial is granted once per device.
public struct LorisTrialService: Sendable {
    private let keychain: LorisKeychain
    private let duration: TimeInterval

    private static let startKey = "loris.paywall.trial.start"

    public init(duration: TimeInterval, keychainService: String) {
        self.duration = duration
        self.keychain = LorisKeychain(service: keychainService)
    }

    /// When the trial began, or nil if it never did.
    public var startDate: Date? {
        guard let raw = try? keychain.string(forKey: Self.startKey),
              let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public var hasStarted: Bool { startDate != nil }

    /// Starts the trial on first call and does nothing afterwards.
    @discardableResult
    public func startIfNeeded(now: Date = Date()) -> Bool {
        guard startDate == nil else { return false }
        try? keychain.save(String(now.timeIntervalSince1970), forKey: Self.startKey)
        return true
    }

    public func daysRemaining(now: Date = Date()) -> Int {
        guard let start = startDate else { return 0 }
        let remaining = duration - now.timeIntervalSince(start)
        guard remaining > 0 else { return 0 }
        // The stored start date survives a Double→String→Double round-trip, so
        // `remaining` can exceed the exact duration by a few microseconds.
        // Without the epsilon, a fresh 7-day trial rounds up to 8 days.
        return max(0, Int(ceil(remaining / 86_400 - 1e-6)))
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard let start = startDate else { return false }
        return now.timeIntervalSince(start) < duration
    }

    public func hasExpired(now: Date = Date()) -> Bool {
        hasStarted && !isActive(now: now)
    }

    /// Testing and support only — clears the stored start date.
    public func reset() {
        try? keychain.delete(forKey: Self.startKey)
    }
}
