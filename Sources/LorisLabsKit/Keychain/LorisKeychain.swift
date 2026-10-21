import Foundation
import Security
import LorisSecurity

/// Canonical keychain wrapper — unifies the two forks copied across the portfolio:
/// `KeychainStore` (Éclair, 98L) and `KeychainHelper` (Clasp/CoreShield/Terrace,
/// 60L). The same need under two names, in ~8 apps. This is the throwing,
/// `Sendable`, service-scoped design (the better of the two), with the ergonomics
/// of the static one.
///
/// New items use `WhenUnlockedThisDeviceOnly`. Existing identity/protection is
/// preserved; this legacy bridge does not silently select a different keychain.
public struct LorisKeychain: Sendable {
    public let service: String
    private let storage: LegacyKeychainStore

    /// - Parameter service: keychain service scope. Defaults to the bundle id, so
    ///   existing service names remain unchanged. Default-group behavior still
    ///   depends on the signed host's entitlements; it is not a sharing guarantee.
    public init(service: String = Bundle.main.bundleIdentifier ?? "com.lorislab.unknown") {
        self.init(service: service, backend: SystemLegacyKeychainBackend())
    }

    /// Explicit signed group for hosts that require a known private/shared
    /// namespace. The nil-group legacy initializer does NOT prove privacy.
    public init(service: String, accessGroup: String) {
        self.init(service: service, accessGroup: accessGroup, backend: SystemLegacyKeychainBackend())
    }

    init(service: String, accessGroup: String? = nil, backend: any LegacyKeychainBackend) {
        self.service = service
        storage = LegacyKeychainStore(service: service, accessGroup: accessGroup, backend: backend)
    }

    public enum KeychainError: Error, Sendable, Equatable {
        case unexpectedStatus(OSStatus)
        case notUTF8
    }

    private func perform<T>(_ action: () throws -> T) throws -> T {
        do { return try action() }
        catch let error as LorisSecurity.KeychainError {
            throw KeychainError.unexpectedStatus(error.status ?? (error == .malformedData ? errSecDecode : errSecParam))
        }
    }

    // MARK: Data

    public func save(_ data: Data, forKey key: String) throws {
        try perform { try storage.upsert(data, account: key) }
    }

    public func data(forKey key: String) throws -> Data? {
        try perform { try storage.read(account: key) }
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
        try perform { try storage.remove(account: key) }
    }

    public func contains(_ key: String) -> Bool {
        (try? storage.contains(account: key)) ?? false
    }
}
