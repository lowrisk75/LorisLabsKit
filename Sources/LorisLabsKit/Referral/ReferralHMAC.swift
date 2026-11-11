import Foundation
import CryptoKit
import LorisSecurity

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

    /// Hex is case-insensitive: `signatureHex` may be upper, lower or mixed
    /// case. It is lowercased (ASCII only, after validation) and compared to
    /// the lowercase `sign` output in constant time.
    public static func verify(secret: String, body: String, signatureHex: String) throws -> Bool {
        guard signatureHex.utf8.count == 64,
              signatureHex.allSatisfy({ $0.isHexDigit }) else {
            return false
        }
        let computed = try sign(secret: secret, body: body)
        return ConstantTime.equals(Data(computed.utf8), Data(signatureHex.lowercased().utf8))
    }
}

private extension Character {
    var isHexDigit: Bool {
        isASCII && (isNumber || ("a"..."f").contains(self) || ("A"..."F").contains(self))
    }
}
