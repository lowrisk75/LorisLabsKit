import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct ReferralManagerTests {

    private func makeManager() -> (ReferralManager, UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let mgr = ReferralManager(appBundleIdentifier: "com.test.app", userDefaults: defaults)
        return (mgr, defaults)
    }

    @Test func generatesAndPersistsCode() {
        let (mgr, _) = makeManager()
        let first = mgr.generateCodeForCurrentUser()
        #expect(first.code.count == ReferralCodeFormat.length)
        #expect(ReferralCodeFormat.isValid(first.code))

        // Calling again returns the SAME code (idempotent)
        let second = mgr.generateCodeForCurrentUser()
        #expect(first.code == second.code)
    }

    @Test func refusesSelfReferral() {
        let (mgr, _) = makeManager()
        let mine = mgr.generateCodeForCurrentUser()
        let result = mgr.recordIncomingReferral(code: mine.code)
        #expect(result == nil)
    }

    @Test func acceptsValidExternalCode() {
        let (mgr, _) = makeManager()
        let result = mgr.recordIncomingReferral(code: "ABCD1234", referredBy: "kevin")
        #expect(result != nil)
        #expect(result?.code == "ABCD1234")
        #expect(result?.referredBy == "kevin")
    }

    @Test func rejectsMalformedCode() {
        let (mgr, _) = makeManager()
        #expect(mgr.recordIncomingReferral(code: "TOOSHORT") == nil) // 8 chars but contains 'O' (not in alphabet)
        #expect(mgr.recordIncomingReferral(code: "WAY_TOO_LONG_CODE") == nil)
        #expect(mgr.recordIncomingReferral(code: "abc") == nil)
        #expect(mgr.recordIncomingReferral(code: "") == nil)
    }

    @Test func onlyOneRedemptionPerDevice() {
        let (mgr, _) = makeManager()
        _ = mgr.recordIncomingReferral(code: "ABCD1234")
        let second = mgr.recordIncomingReferral(code: "EFGH5678")
        #expect(second == nil)
    }

    @Test func resetIssuedClearsCode() {
        let (mgr, _) = makeManager()
        _ = mgr.generateCodeForCurrentUser()
        mgr.resetIssued()
        #expect(mgr.issuedCode == nil)
    }

    @Test func shareURLIsWellFormed() {
        let (mgr, _) = makeManager()
        let code = "ABCD1234"
        let url = mgr.shareURL(for: code)
        #expect(url.absoluteString == "https://lorislab.fr/r/ABCD1234")
    }
}

@Suite struct ReferralCodeFormatTests {
    @Test func generatedCodesAreUnique() {
        let codes = (0..<100).map { _ in ReferralCodeFormat.makeShareableCode() }
        let unique = Set(codes)
        // Vanishingly unlikely to have collisions across 100 codes at 32^8 = ~1 trillion space
        #expect(unique.count == codes.count)
    }

    @Test func validatesCorrectLength() {
        #expect(ReferralCodeFormat.isValid("ABCD1234"))
        #expect(!ReferralCodeFormat.isValid("ABCD123"))    // 7 chars
        #expect(!ReferralCodeFormat.isValid("ABCD12345")) // 9 chars
    }

    @Test func excludesAmbiguousLetters() {
        // I, L, O, U not in alphabet
        #expect(!ReferralCodeFormat.isValid("ABCDEFGI"))
        #expect(!ReferralCodeFormat.isValid("ABCDEFGL"))
        #expect(!ReferralCodeFormat.isValid("ABCDEFGO"))
        #expect(!ReferralCodeFormat.isValid("ABCDEFGU"))
    }
}
