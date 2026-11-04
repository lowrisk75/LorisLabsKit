import CryptoKit
import Foundation
import LorisSecurity
import Security

/// Debug-only developer unlock — the canonical form of the 84-line
/// `DevUnlockService` that was copied, byte-identical, into 11 LorisLabs apps
/// (404, Lumen, Clasp, Éclair, Throttle, CoreShieldAI, Terrace, TypeMetrics,
/// Rampart, AuroraPulse, Sinkhole). Two improvements over the copies:
///
///  • the per-app secret (`expectedHash`) is **injected**, not a constant baked
///    into every Release binary where it could be attacked offline;
///  • one implementation to audit and fix, not eleven.
///
/// Keep call sites `#if DEBUG` — App Review 2.3.1 forbids hidden/undocumented
/// features, and nothing here should ship in Release.
@MainActor
public final class LorisDevUnlock {
    private let expectedHash: String
    private let bundleId: String
    private let keychainKey: String

    /// - Parameters:
    ///   - expectedHash: hex SHA-256 of `bundleId + password` for the app's dev
    ///     password. Generate with `LorisDevUnlock.digest(bundleId:password:)`.
    ///   - bundleId: defaults to the running bundle; injectable for tests.
    public init(expectedHash: String,
                bundleId: String = Bundle.main.bundleIdentifier ?? "com.lorislab.unknown") {
        self.expectedHash = expectedHash
        self.bundleId = bundleId
        self.keychainKey = "\(bundleId).dev-unlocked"
    }

    /// Pure and deterministic: `SHA256(bundleId + password)` as lowercase hex.
    /// Bundle-scoped, so the same password yields a different hash per app.
    /// `nonisolated` — it touches no actor state, so it's callable from anywhere.
    public nonisolated static func digest(bundleId: String, password: String) -> String {
        SHA256.hash(data: Data((bundleId + password).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `password` hashes to `expectedHash` for `bundleId`. Pure: no
    /// keychain access. `expectedHash` is accepted in any hex case; the check
    /// runs in constant time over the lowercase hex digest.
    public nonisolated static func matches(password: String, bundleId: String, expectedHash: String) -> Bool {
        guard expectedHash.utf8.count == 64,
              expectedHash.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) })
        else { return false }
        return ConstantTime.equals(Data(digest(bundleId: bundleId, password: password).utf8),
                                   Data(expectedHash.lowercased().utf8))
    }

    public var isUnlocked: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Verify the password against `expectedHash`; on match, persist the unlock
    /// flag in the keychain. Returns whether the app is now unlocked.
    @discardableResult
    public func unlock(password: String) -> Bool {
        guard Self.matches(password: password, bundleId: bundleId, expectedHash: expectedHash) else { return false }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: Data("1".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(item as CFDictionary)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Clear the unlock flag.
    public func lock() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ] as CFDictionary)
    }
}
