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
}
