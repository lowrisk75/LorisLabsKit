import Foundation
import Testing
@testable import LorisSync

private struct IdentityProfile: SyncablePayload {
    static let recordType = "Profile"
    let id: String
}
private actor IdentityProvider: CloudDatabase {
    let records: [SyncRecord]
    private var writes = 0
    init(_ records: [SyncRecord]) { self.records = records }
    func accountStatus() async -> SyncAccountStatus { .available }
    func fetchAll(type: String) async throws -> [SyncRecord] { records }
    func save(_ records: [SyncRecord]) async throws { writes += 1 }
    func delete(ids: [String], type: String) async throws { writes += 1 }
    func count() -> Int { writes }
}
@Suite("Legacy single-profile identity contract, no provider")
struct SyncProfileIdentityTests {
    @Test func decodedPayloadCannotChangeTransportIdentity() async throws {
        let record = try remote("a", payloadID: "b")
        let engine = CloudSyncEngine<IdentityProfile>(database: IdentityProvider([record]))
        await #expect(throws: CloudSyncPayloadError.inconsistentIdentity) { _ = try await engine.pull() }
    }
    @Test func reconcileDoesNotAdoptOrOverwriteAnotherProfile() async throws {
        let db = IdentityProvider([try remote("other", payloadID: "other")])
        let engine = CloudSyncEngine<IdentityProfile>(database: db)
        await #expect(throws: CloudSyncPayloadError.inconsistentIdentity) {
            _ = try await engine.reconcile(local: .init(id: "local"), localModifiedAt: .distantPast)
        }
        #expect(await db.count() == 0)
    }
    @Test func multipleProfilesAreNotResolvedByArbitraryNewestDate() async throws {
        let engine = CloudSyncEngine<IdentityProfile>(database: IdentityProvider([
            try remote("a", payloadID: "a"), try remote("b", payloadID: "b")
        ]))
        await #expect(throws: CloudSyncPayloadError.ambiguousProfiles) { _ = try await engine.pull() }
    }
    @Test func wrongTypeIsNotAdopted() async throws {
        var record = try remote("a", payloadID: "a")
        record = SyncRecord(id: record.id, type: "Other", fields: record.fields, modifiedAt: record.modifiedAt)
        let engine = CloudSyncEngine<IdentityProfile>(database: IdentityProvider([record]))
        await #expect(throws: CloudSyncPayloadError.invalidRecord) { _ = try await engine.pull() }
    }
    private func remote(_ id: String, payloadID: String) throws -> SyncRecord {
        .init(id: id, type: "Profile", blob: try JSONEncoder().encode(IdentityProfile(id: payloadID)), modifiedAt: .distantPast)
    }
}
