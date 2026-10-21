import Foundation
import Security
import LorisSecurityTesting
import Testing
@testable import LorisLabsKit

@Suite struct LorisKeychainTests {
    // Synthetic backend: no writes/prompts in the user's real Keychain.
    private func kc() -> LorisKeychain {
        LorisKeychain(service: "com.lorislab.kit.tests", backend: InMemoryLegacyKeychainBackend())
    }

    @Test func roundTripsAndDeletes() throws {
        let k = kc()
        try k.save("hunter2", forKey: "token")
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

    @Test func refusedRotationKeepsOldValueAndStatus() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let k = LorisKeychain(service: "old.service", backend: backend)
        try k.save("old", forKey: "token")
        backend.failNext(.update, with: errSecInteractionNotAllowed)
        #expect(throws: LorisKeychain.KeychainError.unexpectedStatus(errSecInteractionNotAllowed)) {
            try k.save("new", forKey: "token")
        }
        #expect(try k.string(forKey: "token") == "old")
        #expect(!backend.operations.contains(.delete))
        #expect(backend.identities.allSatisfy { $0.service == "old.service" && $0.accessGroup == nil && !$0.explicitLocalOnly })
    }

    @Test func emptyDataAndNonUTF8RemainCompatible() throws {
        let k = kc()
        try k.save(Data(), forKey: "empty")
        #expect(try k.data(forKey: "empty") == Data())
        try k.save(Data([0xff]), forKey: "binary")
        #expect(try k.string(forKey: "binary") == nil)
        try k.delete(forKey: "absent")
    }

    @Test func explicitGroupDoesNotSelectAnotherGroup() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let shared = LorisKeychain(service: "legacy", accessGroup: "shared", backend: backend)
        let privateStore = LorisKeychain(service: "legacy", accessGroup: "private", backend: backend)
        try shared.save("shared-fixture", forKey: "token")
        try privateStore.save("private-fixture", forKey: "token")
        #expect(try shared.string(forKey: "token") == "shared-fixture")
        #expect(try privateStore.string(forKey: "token") == "private-fixture")
        let wildcard = LorisKeychain(service: "legacy", backend: backend)
        #expect(throws: LorisKeychain.KeychainError.unexpectedStatus(errSecDuplicateItem)) {
            try wildcard.save("new-fixture", forKey: "token")
        }
    }
}
