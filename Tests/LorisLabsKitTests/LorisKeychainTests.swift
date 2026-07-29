import Foundation
import Testing
@testable import LorisLabsKit

@Suite struct LorisKeychainTests {
    // A unique service per run so tests never collide with real items or each other.
    private func kc() -> LorisKeychain {
        LorisKeychain(service: "com.lorislab.kit.tests." + UUID().uuidString)
    }

    @Test func roundTripsAndDeletes() throws {
        let k = kc()
        // Keychain may be unavailable in a sandboxed CI runner; if the first write
        // can't reach it, skip rather than fail on the environment.
        do { try k.save("hunter2", forKey: "token") }
        catch LorisKeychain.KeychainError.unexpectedStatus(let s) where s == errSecMissingEntitlement || s == errSecNotAvailable {
            return
        }
        #expect(try k.string(forKey: "token") == "hunter2")
        #expect(k.contains("token"))
        // Upsert: second save wins.
        try k.save("rotated", forKey: "token")
        #expect(try k.string(forKey: "token") == "rotated")
        try k.delete(forKey: "token")
        #expect(try k.string(forKey: "token") == nil)
        #expect(!k.contains("token"))
    }

    @Test func missingKeyIsNilNotError() throws {
        let k = kc()
        #expect(try k.string(forKey: "never-written") == nil)
    }
}
