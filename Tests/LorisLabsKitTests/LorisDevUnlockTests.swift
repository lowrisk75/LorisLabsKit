import Foundation
import LorisSecurityTesting
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

    // MARK: Salted, stretched hash (PBKDF2-SHA256)

    private let fastIterations = 10_000 // the minimum accepted; keeps tests quick

    @Test func saltedHashMatchesOnlyTheRightPassword() {
        let hash = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        #expect(hash.hasPrefix("pbkdf2-sha256$10000$"))
        #expect(LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: hash))
        #expect(!LorisDevUnlock.matches(password: "wrong", bundleId: "com.test.app", expectedHash: hash))
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.other.app", expectedHash: hash))
    }

    @Test func saltIsRandomPerHash() {
        let a = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        let b = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        #expect(a != b)
        #expect(LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: b))
    }

    @Test func saltedHashAcceptsUppercaseHex() {
        let hash = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        let parts = hash.split(separator: "$").map(String.init)
        let upper = [parts[0], parts[1], parts[2].uppercased(), parts[3].uppercased()].joined(separator: "$")
        #expect(LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: upper))
    }

    @Test func weakOrMalformedSaltedHashesAreRejected() {
        let salt = Data(repeating: 7, count: 16)
        let weak = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", salt: salt, iterations: 1_000)
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: weak))

        let shortSalt = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", salt: Data(repeating: 7, count: 8), iterations: fastIterations)
        #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: shortSalt))

        let good = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", salt: salt, iterations: fastIterations)
        let parts = good.split(separator: "$").map(String.init)
        for bad in [
            "pbkdf2-sha1$" + parts[1...].joined(separator: "$"),
            [parts[0], "abc", parts[2], parts[3]].joined(separator: "$"),
            [parts[0], parts[1], parts[2], String(parts[3].dropLast(2))].joined(separator: "$"),
            [parts[0], parts[1], parts[2] + "zz", parts[3]].joined(separator: "$"),
            good + "$extra",
        ] {
            #expect(!LorisDevUnlock.matches(password: "secret", bundleId: "com.test.app", expectedHash: bad), "\(bad)")
        }
    }

    // MARK: Keychain flag is service-scoped

    @Test @MainActor func unlockFlagLivesUnderTheAppsService() {
        let backend = InMemoryLegacyKeychainBackend()
        let hash = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        let unlock = LorisDevUnlock(expectedHash: hash, bundleId: "com.test.app", backend: backend)

        #expect(!unlock.isUnlocked)
        #expect(unlock.unlock(password: "secret"))
        #expect(unlock.isUnlocked)
        #expect(backend.identities.allSatisfy { $0.service == "com.test.app.dev-unlock" })

        unlock.lock()
        #expect(!unlock.isUnlocked)
    }

    @Test @MainActor func wrongPasswordWritesNothing() {
        let backend = InMemoryLegacyKeychainBackend()
        let hash = LorisDevUnlock.makeExpectedHash(password: "secret", bundleId: "com.test.app", iterations: fastIterations)
        let unlock = LorisDevUnlock(expectedHash: hash, bundleId: "com.test.app", backend: backend)

        #expect(!unlock.unlock(password: "wrong"))
        #expect(!backend.operations.contains(.add) && !backend.operations.contains(.update))
    }
}
