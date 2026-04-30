import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct ReferralIdentityTests {
    @Test(.disabled("Requires iCloud Keychain entitlement; runs on device only"))
    func identity_persistsAcrossInstances() throws {
        let service = "ReferralKit.test.\(UUID().uuidString)"
        let id1 = try ReferralIdentity(service: service).getOrCreateUUID()
        let id2 = try ReferralIdentity(service: service).getOrCreateUUID()
        #expect(id1 == id2)
        try ReferralIdentity(service: service).reset()
    }

    @Test(.disabled("Requires iCloud Keychain entitlement; runs on device only"))
    func identity_returnsValidUUID() throws {
        let service = "ReferralKit.test.\(UUID().uuidString)"
        let id = try ReferralIdentity(service: service).getOrCreateUUID()
        #expect(UUID(uuidString: id) != nil)
        try ReferralIdentity(service: service).reset()
    }

    @Test(.disabled("Requires iCloud Keychain entitlement; runs on device only"))
    func identity_resetCreatesNewUUID() throws {
        let service = "ReferralKit.test.\(UUID().uuidString)"
        let id1 = try ReferralIdentity(service: service).getOrCreateUUID()
        try ReferralIdentity(service: service).reset()
        let id2 = try ReferralIdentity(service: service).getOrCreateUUID()
        #expect(id1 != id2)
        try ReferralIdentity(service: service).reset()
    }
}
