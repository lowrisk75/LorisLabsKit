import Testing
import Foundation
@testable import LorisLabsKit

struct ReferralHMACTests {
    @Test func sign_then_verify_succeeds() throws {
        let secret = "test-shared-secret"
        let body = "{\"a\":1}"
        let sig = try ReferralHMAC.sign(secret: secret, body: body)
        #expect(try ReferralHMAC.verify(secret: secret, body: body, signatureHex: sig))
    }

    @Test func verify_rejectsTamperedBody() throws {
        let secret = "test-shared-secret"
        let sig = try ReferralHMAC.sign(secret: secret, body: "{\"a\":1}")
        #expect(try !ReferralHMAC.verify(secret: secret, body: "{\"a\":2}", signatureHex: sig))
    }

    @Test func verify_rejectsTamperedSig() throws {
        let secret = "test-shared-secret"
        let body = "{\"a\":1}"
        let sig = try ReferralHMAC.sign(secret: secret, body: body)
        let tampered = String(sig.dropLast(2)) + (sig.hasSuffix("00") ? "11" : "00")
        #expect(try !ReferralHMAC.verify(secret: secret, body: body, signatureHex: tampered))
    }

    @Test func verify_rejectsWrongLengthAndNonHex() throws {
        let secret = "k"
        let body = "x"
        #expect(try !ReferralHMAC.verify(secret: secret, body: body, signatureHex: "tooshort"))
        #expect(try !ReferralHMAC.verify(secret: secret, body: body, signatureHex: String(repeating: "z", count: 64)))
    }

    @Test func sign_outputIs64HexChars() throws {
        let sig = try ReferralHMAC.sign(secret: "k", body: "x")
        #expect(sig.count == 64)
        #expect(sig.allSatisfy { $0.isHexDigit })
    }
}
