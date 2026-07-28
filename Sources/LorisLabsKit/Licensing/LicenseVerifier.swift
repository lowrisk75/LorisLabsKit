import Foundation
import Security

/// Portfolio-generic offline license verification (ported from Throttle's
/// LicenseService, parameterized so any app can use it against its own
/// license worker + signing key instead of the hardcoded throttle.pro values).
///
/// The license is an RS256 JWT minted by a Cloudflare license worker
/// (see throttle-license-worker for the reference implementation). Verification
/// is fully offline against a bundled public key.
public struct LicenseVerifier: Sendable {

    public struct Claims: Codable, Sendable {
        public let iss: String
        public let machineId: String
        public let email: String
        public let product: String
        public let appVersion: String
        public let iat: TimeInterval
        public let exp: TimeInterval
        public let nbf: TimeInterval
    }

    public struct Configuration: Sendable {
        public let issuer: String            // e.g. "clasp-license"
        public let product: String           // e.g. "clasp.pro"
        public let publicKeyDER: Data        // RSA public key, DER (SecKeyCreateWithData)
        /// Stable machine identifier the JWT was bound to at activation
        /// (e.g. IOPlatformUUID on macOS, identifierForVendor on iOS).
        public let machineId: @Sendable () -> String
        /// Clock-skew tolerance — a slightly-off clock must not void a valid license.
        public let clockSkew: TimeInterval

        public init(issuer: String, product: String, publicKeyDER: Data,
                    machineId: @escaping @Sendable () -> String,
                    clockSkew: TimeInterval = 300) {
            self.issuer = issuer
            self.product = product
            self.publicKeyDER = publicKeyDER
            self.machineId = machineId
            self.clockSkew = clockSkew
        }
    }

    private let config: Configuration

    public init(_ config: Configuration) {
        self.config = config
    }

    /// Verify an RS256 license JWT offline. Returns the claims when the
    /// signature is valid AND issuer/product/machine/time-window all check out.
    public func verify(_ jwt: String, at now: Date = Date()) -> Claims? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3,
              let headerData = Self.base64UrlDecode(String(parts[0])),
              let payloadData = Self.base64UrlDecode(String(parts[1])),
              let signatureData = Self.base64UrlDecode(String(parts[2])) else {
            return nil
        }
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256" else { return nil }

        let signingInput = "\(parts[0]).\(parts[1])"
        guard let signingData = signingInput.data(using: .utf8) else { return nil }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var keyError: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(config.publicKeyDER as CFData,
                                                   attrs as CFDictionary, &keyError) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingData as CFData,
            signatureData as CFData,
            &error
        )
        guard isValid else { return nil }

        guard let claims = try? JSONDecoder().decode(Claims.self, from: payloadData) else { return nil }
        let t = now.timeIntervalSince1970
        guard claims.iss == config.issuer,
              claims.product == config.product,
              claims.machineId == config.machineId(),
              t >= claims.nbf - config.clockSkew,
              t < claims.exp + config.clockSkew else {
            return nil
        }
        return claims
    }

    static func base64UrlDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        b64.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: b64)
    }
}

// MARK: - Stored license (keychain persistence, per-app namespace)

public struct StoredLicense: Codable, Sendable {
    public let licenseKey: String
    public let jwt: String
    public let activatedAt: Date

    public init(licenseKey: String, jwt: String, activatedAt: Date) {
        self.licenseKey = licenseKey
        self.jwt = jwt
        self.activatedAt = activatedAt
    }
}

public struct LicenseStore: Sendable {
    private let service: String
    private let account = "current"

    public init(bundleId: String) {
        self.service = "\(bundleId).license"
    }

    public func save(_ stored: StoredLicense) throws {
        let data = try JSONEncoder().encode(stored)
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

    public func load() -> StoredLicense? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredLicense.self, from: data)
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
