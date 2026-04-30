import Foundation
import CryptoKit

/// Hex HMAC-SHA256. Matches the worker's `crypto/hmac.ts` byte-for-byte
/// so signed `/me` responses can be verified client-side.
public enum ReferralHMAC {
    public enum HMACError: Error, Sendable {
        case malformedSignature
        case bodyEncoding
    }

    public static func sign(secret: String, body: String) throws -> String {
        guard let bodyData = body.data(using: .utf8),
              let secretData = secret.data(using: .utf8) else {
            throw HMACError.bodyEncoding
        }
        let key = SymmetricKey(data: secretData)
        let mac = HMAC<SHA256>.authenticationCode(for: bodyData, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(secret: String, body: String, signatureHex: String) throws -> Bool {
        guard signatureHex.count == 64,
              signatureHex.allSatisfy({ $0.isHexDigit }) else {
            return false
        }
        let computed = try sign(secret: secret, body: body)
        // Constant-time comparison via XOR over the hex strings (both are
        // already same length and known-hex).
        guard computed.count == signatureHex.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(computed.utf8, signatureHex.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }
}

private extension Character {
    var isHexDigit: Bool {
        isASCII && (isNumber || ("a"..."f").contains(self) || ("A"..."F").contains(self))
    }
}
