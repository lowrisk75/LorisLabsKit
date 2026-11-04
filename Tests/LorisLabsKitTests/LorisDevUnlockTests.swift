import Foundation
import Testing
@testable import LorisLabsKit

@Suite struct LorisDevUnlockTests {
    @Test func digestIsStableHexAndBundleScoped() {
        let a = LorisDevUnlock.digest(bundleId: "com.lorislab.throttle", password: "open")
        #expect(a.count == 64)
        #expect(a.allSatisfy { $0.isHexDigit })
        // Deterministic.
        #expect(a == LorisDevUnlock.digest(bundleId: "com.lorislab.throttle", password: "open"))
        // Bundle-scoped: same password, different app → different hash. This is why
        // each app needs its own expectedHash (the very reason it was per-app config).
        #expect(a != LorisDevUnlock.digest(bundleId: "com.lorislab.clasp", password: "open"))
    }

    @Test @MainActor func wrongPasswordNeverUnlocks() {
        let known = LorisDevUnlock.digest(bundleId: "com.test.app", password: "secret")
        let unlock = LorisDevUnlock(expectedHash: known, bundleId: "com.test.app")
        // Mismatch is rejected before any keychain write.
        #expect(unlock.unlock(password: "wrong") == false)
    }

    // `matches` is the pure check `unlock` runs before touching the keychain.
    @Test func matchesAcceptsRightPasswordOnly() {
        let known = LorisDevUnlock.digest(bundleId: "com.test.app", password: "secret")
        #expect(LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: known))
        #expect(!LorisDevUnlock.matches(password: "wrong", bundleId: "com.test.app", expectedHash: known))
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.other.app", expectedHash: known))
    }

    // A hash pasted from `shasum` tooling or a doc in uppercase must still unlock.
    @Test func matchesIsCaseInsensitiveOnExpectedHash() {
        let known = LorisDevUnlock.digest(bundleId: "com.test.app", password: "secret")
        #expect(known != known.uppercased())
        #expect(LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: known.uppercased()))
        #expect(!LorisDevUnlock.matches(password: "wrong", bundleId: "com.test.app", expectedHash: known.uppercased()))
    }

    @Test func matchesRejectsMalformedExpectedHash() {
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: ""))
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: "abc"))
        let known = LorisDevUnlock.digest(bundleId: "com.test.app", password: "secret")
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: " " + known))
    }

    @Test @MainActor func wrongPasswordRejectedWithUppercaseExpectedHash() {
        let known = LorisDevUnlock.digest(bundleId: "com.test.app", password: "secret").uppercased()
        let unlock = LorisDevUnlock(expectedHash: known, bundleId: "com.test.app")
        #expect(unlock.unlock(password: "wrong") == false)
    }
}
