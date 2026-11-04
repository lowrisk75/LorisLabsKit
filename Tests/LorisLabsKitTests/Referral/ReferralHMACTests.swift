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

    // Hex is case-insensitive: the worker (or a proxy) may emit uppercase.
    @Test func verify_acceptsUppercaseSignature() throws {
        let secret = "test-shared-secret"
        let body = "{\"a\":1}"
        let sig = try ReferralHMAC.sign(secret: secret, body: body)
        #expect(sig != sig.uppercased(), "fixture must contain a-f digits")
        #expect(try ReferralHMAC.verify(secret: secret, body: body, signatureHex: sig.uppercased()))
    }

    @Test func verify_acceptsMixedCaseSignature() throws {
        let secret = "test-shared-secret"
        let body = "{\"a\":1}"
        let sig = try ReferralHMAC.sign(secret: secret, body: body)
        let mixed = String(sig.enumerated().map { $0.offset.isMultiple(of: 2) ? Character($0.element.uppercased()) : $0.element })
        #expect(try ReferralHMAC.verify(secret: secret, body: body, signatureHex: mixed))
    }

    @Test func verify_rejectsUppercaseSignatureOfOtherBody() throws {
        let secret = "test-shared-secret"
        let sig = try ReferralHMAC.sign(secret: secret, body: "{\"a\":1}")
        #expect(try !ReferralHMAC.verify(secret: secret, body: "{\"a\":2}", signatureHex: sig.uppercased()))
    }

    // Non-ASCII "hex-looking" characters must not slip past the length check.
    @Test func verify_rejectsFullWidthDigits() throws {
        let sig = String(repeating: "\u{FF11}", count: 64) // FULLWIDTH DIGIT ONE
        #expect(try !ReferralHMAC.verify(secret: "k", body: "x", signatureHex: sig))
    }
}
