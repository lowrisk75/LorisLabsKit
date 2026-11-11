import CommonCrypto
import CryptoKit
import Foundation
import LorisSecurity
import Security

/// Debug-only developer unlock — the canonical form of the 84-line
/// `DevUnlockService` that was copied, byte-identical, into 11 LorisLabs apps
/// (404, Lumen, Clasp, Éclair, Throttle, CoreShieldAI, Terrace, TypeMetrics,
/// Rampart, AuroraPulse, Sinkhole). Improvements over the copies:
///
///  • the per-app secret (`expectedHash`) is **injected**, not a constant baked
///    into every Release binary where it could be attacked offline;
///  • the recommended hash is salted and stretched (PBKDF2-SHA256), so a
///    leaked hash is expensive to brute-force — generate it with
///    `makeExpectedHash(password:bundleId:)`;
///  • the comparison runs in constant time, and the unlock flag is stored
///    under the app's own keychain service;
///  • one implementation to audit and fix, not eleven.
///
/// Keep call sites `#if DEBUG` — App Review 2.3.1 forbids hidden/undocumented
/// features, and nothing here should ship in Release.
@MainActor
public final class LorisDevUnlock {
    private let expectedHash: String
    private let bundleId: String
    private let keychain: LorisKeychain
    /// Pre-service flag (`<bundleId>.dev-unlocked`, account only). Still read
    /// and cleared on the system keychain; never written.
    private let legacyAccount: String?

    private static let flagKey = "unlocked"

    /// Minimum PBKDF2 work accepted in an `expectedHash`.
    public nonisolated static let minimumIterations = 10_000
    /// Work used by `makeExpectedHash` by default (OWASP 2023 guidance for PBKDF2-SHA256).
    public nonisolated static let defaultIterations = 600_000
    private nonisolated static let saltedPrefix = "pbkdf2-sha256"
    private nonisolated static let minimumSaltBytes = 16

    /// - Parameters:
    ///   - expectedHash: preferably `makeExpectedHash(password:bundleId:)` output
    ///     (`pbkdf2-sha256$<iterations>$<salt hex>$<hash hex>`). The legacy
    ///     unsalted form — hex SHA-256 of `bundleId + password`, see
    ///     `digest(bundleId:password:)` — is still accepted.
    ///   - bundleId: defaults to the running bundle; injectable for tests.
    public convenience init(expectedHash: String,
                            bundleId: String = Bundle.main.bundleIdentifier ?? "com.lorislab.unknown") {
        self.init(expectedHash: expectedHash, bundleId: bundleId,
                  keychain: LorisKeychain(service: "\(bundleId).dev-unlock"),
                  legacyAccount: "\(bundleId).dev-unlocked")
    }

    /// Tests: synthetic keychain, no legacy lookup.
    convenience init(expectedHash: String, bundleId: String, backend: any LegacyKeychainBackend) {
        self.init(expectedHash: expectedHash, bundleId: bundleId,
                  keychain: LorisKeychain(service: "\(bundleId).dev-unlock", backend: backend),
                  legacyAccount: nil)
    }

    private init(expectedHash: String, bundleId: String, keychain: LorisKeychain, legacyAccount: String?) {
        self.expectedHash = expectedHash
        self.bundleId = bundleId
        self.keychain = keychain
        self.legacyAccount = legacyAccount
    }

    // MARK: Hashes

    /// Legacy, unsalted: `SHA256(bundleId + password)` as lowercase hex.
    /// Bundle-scoped, so the same password yields a different hash per app.
    /// Prefer `makeExpectedHash(password:bundleId:)` for new apps.
    public nonisolated static func digest(bundleId: String, password: String) -> String {
        SHA256.hash(data: Data((bundleId + password).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Salted, stretched hash to inject as `expectedHash`:
    /// `pbkdf2-sha256$<iterations>$<salt hex>$<hash hex>`, with a random
    /// 16-byte salt. Run once (e.g. in a playground) and paste the result.
    public nonisolated static func makeExpectedHash(password: String, bundleId: String,
                                                    iterations: Int = defaultIterations) -> String {
        var salt = Data(count: minimumSaltBytes)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, minimumSaltBytes, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return makeExpectedHash(password: password, bundleId: bundleId, salt: salt, iterations: iterations)
    }

    nonisolated static func makeExpectedHash(password: String, bundleId: String, salt: Data, iterations: Int) -> String {
        let derived = pbkdf2(password: bundleId + password, salt: salt, iterations: iterations) ?? Data()
        return [saltedPrefix, String(iterations), hex(salt), hex(derived)].joined(separator: "$")
    }

    /// Whether `password` matches `expectedHash` for `bundleId`. Pure: no
    /// keychain access. Accepts the salted form (at least `minimumIterations`,
    /// 16-byte salt) or the legacy 64-hex digest, in any hex case; the final
    /// comparison runs in constant time.
    public nonisolated static func matches(password: String, bundleId: String, expectedHash: String) -> Bool {
        if expectedHash.hasPrefix(saltedPrefix + "$") {
            let parts = expectedHash.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, parts[0] == saltedPrefix,
                  let iterations = Int(parts[1]), iterations >= minimumIterations, iterations <= 10_000_000,
                  let salt = data(fromHex: parts[2]), salt.count >= minimumSaltBytes,
                  let expected = data(fromHex: parts[3]), expected.count == 32,
                  let derived = pbkdf2(password: bundleId + password, salt: salt, iterations: iterations)
            else { return false }
            return ConstantTime.equals(derived, expected)
        }
        guard expectedHash.utf8.count == 64, data(fromHex: expectedHash) != nil else { return false }
        return ConstantTime.equals(Data(digest(bundleId: bundleId, password: password).utf8),
                                   Data(expectedHash.lowercased().utf8))
    }

    // MARK: Unlock state

    public var isUnlocked: Bool {
        keychain.contains(Self.flagKey) || legacyFlagExists()
    }

    /// Verify the password against `expectedHash`; on match, persist the unlock
    /// flag in the keychain under `<bundleId>.dev-unlock`. Returns whether the
    /// app is now unlocked. A mismatch writes nothing.
    @discardableResult
    public func unlock(password: String) -> Bool {
        guard Self.matches(password: password, bundleId: bundleId, expectedHash: expectedHash) else { return false }
        do {
            try keychain.save("1", forKey: Self.flagKey)
            return true
        } catch {
            return false
        }
    }

    /// Clear the unlock flag (and the pre-service legacy flag, if any).
    public func lock() {
        try? keychain.delete(forKey: Self.flagKey)
        if let legacyAccount {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: legacyAccount,
            ] as CFDictionary)
        }
    }

    private func legacyFlagExists() -> Bool {
        guard let legacyAccount else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: Helpers

    private nonisolated static func pbkdf2(password: String, salt: Data, iterations: Int) -> Data? {
        guard iterations > 0, iterations <= Int(UInt32.max) else { return nil }
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    private nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Strict ASCII hex (any case), even length.
    private nonisolated static func data(fromHex string: String) -> Data? {
        let bytes = Array(string.utf8)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: c - 0x30
            case 0x41...0x46: c - 0x41 + 10
            case 0x61...0x66: c - 0x61 + 10
            default: nil
            }
        }
        var out = Data(capacity: bytes.count / 2)
        var i = 0
        while i < bytes.count {
            guard let hi = nibble(bytes[i]), let lo = nibble(bytes[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }
}
