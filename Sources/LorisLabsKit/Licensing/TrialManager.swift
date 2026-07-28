import Foundation
import OSLog
import Security

/// Portfolio-generic trial clock (ported from Throttle's TrialService).
/// State lives in Keychain so re-installing the app doesn't reset the clock —
/// only a deliberate Keychain wipe (or a new machine) gives a fresh trial.
///
/// Typical activation rule in an app:
///   `isPro = licenseValid || storeKitEntitlement || trial.isActive`
@MainActor
public final class TrialManager {
    private let logger: Logger
    private let trialDuration: TimeInterval
    private let keychain: TrialKeychain

    public private(set) var startedAt: Date?

    /// - Parameters:
    ///   - bundleId: keychain namespace, e.g. "com.lorislab.claspapp" — each app gets its own clock
    ///   - days: trial length (default 7)
    public init(bundleId: String, days: Int = 7) {
        self.logger = Logger(subsystem: bundleId, category: "Trial")
        self.trialDuration = TimeInterval(days) * 24 * 3600
        self.keychain = TrialKeychain(service: "\(bundleId).trial")
        self.startedAt = keychain.load()
        if startedAt == nil {
            let now = Date()
            self.startedAt = now
            try? keychain.save(now)
            logger.info("Trial started at \(now.ISO8601Format(), privacy: .public)")
        }
    }

    /// True while inside the trial window.
    public var isActive: Bool {
        guard let started = startedAt else { return false }
        return Date().timeIntervalSince(started) < trialDuration
    }

    /// Days remaining (0 once expired) — for countdown banners.
    public var daysLeft: Int {
        guard let started = startedAt else { return 0 }
        let remaining = trialDuration - Date().timeIntervalSince(started)
        if remaining <= 0 { return 0 }
        return max(1, Int(ceil(remaining / (24 * 3600))))
    }

    /// True iff the trial has started AND is now expired (distinct banner copy).
    public var hasExpired: Bool {
        startedAt != nil && !isActive
    }

    /// Reset trial state (dev tooling / tests only — never expose in UI).
    public func reset() {
        keychain.clear()
        startedAt = nil
    }
}

// MARK: - Keychain backing

private struct TrialKeychain {
    let service: String
    private let account = "started-at"

    func save(_ date: Date) throws {
        let value = String(Int64(date.timeIntervalSince1970))
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func load() -> Date? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8),
              let secs = Int64(s) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(secs))
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
