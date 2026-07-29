import Foundation
import Security

/// Canonical keychain wrapper — unifies the two forks copied across the portfolio:
/// `KeychainStore` (Éclair, 98L) and `KeychainHelper` (Clasp/CoreShield/Terrace,
/// 60L). The same need under two names, in ~8 apps. This is the throwing,
/// `Sendable`, service-scoped design (the better of the two), with the ergonomics
/// of the static one.
///
/// Items are `WhenUnlockedThisDeviceOnly` — never synced to iCloud Keychain.
public struct LorisKeychain: Sendable {
    public let service: String

    /// - Parameter service: keychain service scope. Defaults to the bundle id, so
    ///   two LorisLabs apps on the same device never read each other's items.
    public init(service: String = Bundle.main.bundleIdentifier ?? "com.lorislab.unknown") {
        self.service = service
    }

    public enum KeychainError: Error, Sendable, Equatable {
        case unexpectedStatus(OSStatus)
        case notUTF8
    }

    private func baseQuery(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
    }

    // MARK: Data

    public func save(_ data: Data, forKey key: String) throws {
        var q = baseQuery(key)
        SecItemDelete(q as CFDictionary)                 // upsert: last write wins
        q[kSecValueData] = data
        q[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func data(forKey key: String) throws -> Data? {
        var q = baseQuery(key)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:   return out as? Data
        case errSecItemNotFound: return nil
        default:              throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: String convenience

    public func save(_ value: String, forKey key: String) throws {
        guard let d = value.data(using: .utf8) else { throw KeychainError.notUTF8 }
        try save(d, forKey: key)
    }

    public func string(forKey key: String) throws -> String? {
        guard let d = try data(forKey: key) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: Delete / probe

    public func delete(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func contains(_ key: String) -> Bool {
        SecItemCopyMatching(baseQuery(key) as CFDictionary, nil) == errSecSuccess
    }
}
