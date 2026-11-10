import Foundation

/// App-managed free trial, stored in the keychain.
///
/// The copies this replaces kept the start date in `UserDefaults`, where
/// deleting the app's data — or offloading and reinstalling it — handed the
/// user a fresh trial every time. Keychain items outlive app removal, so a
/// trial is granted once per device.
///
/// Setting the clock back does not extend the trial: the latest time seen is
/// kept beside the start date and used whenever the clock reads earlier.
/// The portfolio's only trial engine; `TrialManager` delegates to it.
public struct LorisTrialService: Sendable {
    private let keychain: LorisKeychain
    private let duration: TimeInterval
    private let startKey: String
    private let lastSeenKey: String
    /// `TrialManager`'s item held whole seconds; keep writing that format so
    /// an older build can still read it.
    private let storesWholeSeconds: Bool

    static let defaultStartKey = "loris.paywall.trial.start"

    public init(duration: TimeInterval, keychainService: String) {
        self.init(duration: duration, keychain: LorisKeychain(service: keychainService))
    }

    init(duration: TimeInterval, keychain: LorisKeychain, startKey: String = Self.defaultStartKey, storesWholeSeconds: Bool = false) {
        self.storesWholeSeconds = storesWholeSeconds
        self.duration = duration
        self.keychain = keychain
        self.startKey = startKey
        self.lastSeenKey = startKey + ".lastSeen"
    }

    /// When the trial began, or nil if it never did.
    public var startDate: Date? {
        guard let raw = try? keychain.string(forKey: startKey),
              let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public var hasStarted: Bool { startDate != nil }

    /// Starts the trial on first call and does nothing afterwards.
    @discardableResult
    public func startIfNeeded(now: Date = Date()) -> Bool {
        guard startDate == nil else { return false }
        let seconds = storesWholeSeconds ? String(Int64(now.timeIntervalSince1970)) : String(now.timeIntervalSince1970)
        try? keychain.save(seconds, forKey: startKey)
        try? keychain.save(String(now.timeIntervalSince1970), forKey: lastSeenKey)
        return true
    }

    /// Time elapsed since the start, measured against the latest time ever seen
    /// (never earlier than the start), so moving the clock back gains nothing.
    private func elapsed(since start: Date, now: Date) -> TimeInterval {
        let lastSeen = (try? keychain.string(forKey: lastSeenKey)).flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
        let effectiveNow = max(now, lastSeen ?? start, start)
        // Advance the mark only when time moved forward meaningfully, to
        // avoid a keychain write on every read.
        if now > (lastSeen ?? .distantPast).addingTimeInterval(60) {
            try? keychain.save(String(now.timeIntervalSince1970), forKey: lastSeenKey)
        }
        return effectiveNow.timeIntervalSince(start)
    }

    public func daysRemaining(now: Date = Date()) -> Int {
        guard let start = startDate else { return 0 }
        let remaining = duration - elapsed(since: start, now: now)
        guard remaining > 0 else { return 0 }
        // The stored start date survives a Double→String→Double round-trip, so
        // `remaining` can exceed the exact duration by a few microseconds.
        // Without the epsilon, a fresh 7-day trial rounds up to 8 days.
        return max(0, Int(ceil(remaining / 86_400 - 1e-6)))
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard let start = startDate else { return false }
        return elapsed(since: start, now: now) < duration
    }

    public func hasExpired(now: Date = Date()) -> Bool {
        hasStarted && !isActive(now: now)
    }

    /// Adopts a trial that an earlier version of the app stored in
    /// `UserDefaults`, so migrating to the keychain neither restarts a running
    /// trial nor hands a second one to someone who already used theirs.
    ///
    /// Safe to call on every launch: it only ever writes when the keychain has
    /// no start date yet. Returns true when a legacy date was adopted.
    @discardableResult
    public func migrateLegacyStart(
        fromUserDefaultsKey key: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard startDate == nil,
              let legacy = defaults.object(forKey: key) as? Date else { return false }
        try? keychain.save(String(legacy.timeIntervalSince1970), forKey: startKey)
        return true
    }

    /// Testing and support only — clears the stored start date.
    public func reset() {
        try? keychain.delete(forKey: startKey)
        try? keychain.delete(forKey: lastSeenKey)
    }
}
