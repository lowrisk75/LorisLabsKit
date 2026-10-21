import Foundation
import Testing
@testable import LorisSync
#if canImport(CloudKit)
import CloudKit
#endif

private struct Profile: SyncablePayload, Equatable {
    static let recordType = "VersionedProfile"
    let id: String
    var name: String
}

/// A database without compare-and-set support.
private struct PlainDatabase: CloudDatabase {
    func accountStatus() async -> SyncAccountStatus { .available }
    func save(_ records: [SyncRecord]) async throws {}
    func fetchAll(type: String) async throws -> [SyncRecord] { [] }
    func delete(ids: [String], type: String) async throws {}
}

@Suite("Server compare-and-set synchronisation, in-memory server")
struct SyncVersioningTests {
    private func record(_ profile: Profile, at date: Date) throws -> SyncRecord {
        SyncRecord(id: profile.id, type: Profile.recordType,
                   blob: try JSONEncoder().encode(profile), modifiedAt: date)
    }

    @Test func firstSyncCreatesAndReturnsServerVersion() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let version) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        guard case .upToDate(let again) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: version, hasLocalChanges: false) else {
            Issue.record("expected up to date"); return
        }
        #expect(again == version)
    }

    @Test func farFutureClientClockCannotWinWithoutTheServerVersion() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        // A participant writes with an absurd future date: ordering must ignore it.
        await db.seed([try record(Profile(id: "p", name: "Hijack"), at: .distantFuture)])
        let outcome = try await engine.synchronize(local: Profile(id: "p", name: "Ana edited"),
                                                   base: base, hasLocalChanges: true)
        guard case .conflict(let remote, let remoteVersion) = outcome else {
            Issue.record("a concurrent change must surface as a conflict, not overwrite"); return
        }
        #expect(remote.name == "Hijack")
        #expect(remoteVersion != base)
        // After merging, writing against the remote version succeeds.
        guard case .pushed = try await engine.synchronize(local: Profile(id: "p", name: "Merged"),
                                                          base: remoteVersion, hasLocalChanges: true) else {
            Issue.record("merge write against the current version must succeed"); return
        }
        #expect(try await stored(in: db) == Profile(id: "p", name: "Merged"))
    }

    /// Decoded comparison: JSON key order is not stable, bytes are not comparable.
    private func stored(in db: MockCloudDatabase) async throws -> Profile? {
        guard let blob = try await db.fetchAll(type: Profile.recordType).first?.blob else { return nil }
        return try JSONDecoder().decode(Profile.self, from: blob)
    }

    @Test func unchangedLocalAdoptsRemote() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        await db.seed([try record(Profile(id: "p", name: "Remote"), at: .distantPast)])
        guard case .adoptRemote(let payload, _) = try await engine.synchronize(
            local: Profile(id: "p", name: "Old"), base: nil, hasLocalChanges: false) else {
            Issue.record("expected adoption"); return
        }
        #expect(payload.name == "Remote")
    }

    @Test func staleCreateIsAConflictNotAnOverwrite() async throws {
        let db = MockCloudDatabase()
        await db.seed([try record(Profile(id: "p", name: "Exists"), at: .distantPast)])
        do {
            _ = try await db.save(try record(Profile(id: "p", name: "Mine"), at: Date()), expecting: nil)
            Issue.record("create-only must fail when the record exists")
        } catch CloudSyncConflictError.serverRecordChanged(let current) {
            #expect(current?.record.id == "p")
        }
        #expect(try await stored(in: db) == Profile(id: "p", name: "Exists"))
    }

    @Test func remoteDeletionIsReportedNotRecreated() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        try await db.delete(ids: ["p"], type: Profile.recordType)
        guard case .remoteDeleted = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: base, hasLocalChanges: true) else {
            Issue.record("expected remoteDeleted"); return
        }
        #expect(try await db.fetchAll(type: Profile.recordType).isEmpty)
    }

    @Test func unsupportedDatabaseFailsClosed() async {
        let engine = CloudSyncEngine<Profile>(database: PlainDatabase())
        await #expect(throws: CloudSyncConflictError.versioningUnsupported) {
            _ = try await engine.synchronize(local: nil, base: nil, hasLocalChanges: false)
        }
    }

    private func version(_ id: String, _ tag: String, token: String = "x") -> SyncRecordVersion {
        SyncRecordVersion(identity: Data(id.utf8), tag: Data(tag.utf8), token: Data(token.utf8), serverModifiedAt: nil)
    }

    @Test func versionEqualityUsesRecordAndChangeTagAndRedacts() throws {
        let a = version("p", "t1"), b = version("p", "t1", token: "y")
        #expect(a == b)
        #expect(a != version("p", "t2"))
        #expect(a != version("q", "t1"), "the same tag on another record is not the same version")
        var dumped = ""
        dump(a, to: &dumped)
        #expect(!dumped.contains("t1") && !"\(a)".contains("t1"))
        let restored = try JSONDecoder().decode(SyncRecordVersion.self, from: JSONEncoder().encode(a))
        #expect(restored == a)
        #expect(throws: CloudSyncReadError.invalidRecord) {
            _ = try JSONDecoder().decode(SyncRecordVersion.self,
                                         from: Data(#"{"identity":"cA==","tag":"","token":"eA=="}"#.utf8))
        }
    }

    @Test func knownRecordIsReadByIDSoASecondRecordCannotBlockSync() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: false) else {
            Issue.record("expected a push"); return
        }
        // A participant plants a second record of the same type.
        await db.seed([try record(Profile(id: "planted", name: "x"), at: .distantFuture)])
        guard case .upToDate(let again) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: base, hasLocalChanges: false) else {
            Issue.record("by-ID sync must ignore other records"); return
        }
        #expect(again == base)
    }

    @Test func unreadableRemoteIsReportedAndOnlyOverwrittenOnPurpose() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        await db.seed([try record(Profile(id: "p", name: "Newer app"), at: .distantPast)])
        await db.markUnreadable("p")
        guard case .remoteUnreadable(let remoteVersion) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana edited"), base: base, hasLocalChanges: true) else {
            Issue.record("unreadable remote must be reported, not overwritten"); return
        }
        #expect(try await stored(in: db) == Profile(id: "p", name: "Newer app"))
        // Deliberate repair: base = the unreadable version, still compare-and-set.
        guard case .pushed = try await engine.synchronize(
            local: Profile(id: "p", name: "Repaired"), base: remoteVersion, hasLocalChanges: true) else {
            Issue.record("deliberate repair must succeed"); return
        }
        #expect(try await stored(in: db) == Profile(id: "p", name: "Repaired"))
    }

    @Test func localDeletionAndForeignBaseAreRejected() async {
        let engine = CloudSyncEngine<Profile>(database: MockCloudDatabase())
        await #expect(throws: CloudSyncPayloadError.invalidRecord) {
            _ = try await engine.synchronize(local: nil, base: nil, hasLocalChanges: true)
        }
        await #expect(throws: CloudSyncPayloadError.inconsistentIdentity) {
            _ = try await engine.synchronize(local: Profile(id: "p", name: "x"),
                                             base: version("other", "t"), hasLocalChanges: true)
        }
    }

    @Test func versionedSavePreservesFieldsItDoesNotSend() async throws {
        let db = MockCloudDatabase()
        let first = try await db.save(SyncRecord(id: "r", type: "T", fields: ["a": .int(1), "newer": .string("keep")],
                                                 modifiedAt: .distantPast), expecting: nil)
        _ = try await db.save(SyncRecord(id: "r", type: "T", fields: ["a": .int(2)], modifiedAt: .distantPast),
                              expecting: first)
        let stored = try await db.fetchAll(type: "T").first
        #expect(stored?.int("a") == 2)
        #expect(stored?.string("newer") == "keep")
    }

    @Test func legacyPublicShareCanBeMigratedToInviteOnly() async throws {
        let db = MockCloudDatabase()
        await db.seed([SyncRecord(id: "a", type: "Item", fields: [:], modifiedAt: .distantPast)])
        _ = try await db.share(recordID: "a", type: "Item", title: nil, access: .anyoneWithLink(.readWrite))
        await #expect(throws: CloudSyncSharePermissionError.existingPermissionMismatch) {
            _ = try await db.share(recordID: "a", type: "Item", title: nil)
        }
        _ = try await db.updateShareAccess(recordID: "a", type: "Item", access: .invitedOnly)
        _ = try await db.share(recordID: "a", type: "Item", title: nil)
        #expect(await db.access(of: "a") == .invitedOnly)
    }

    @Test func secondDeviceWithAnotherProfileIDCannotCreateADuplicate() async throws {
        let db = MockCloudDatabase()
        let first = CloudSyncEngine<Profile>(database: db)
        _ = try await first.synchronize(local: Profile(id: "device-a", name: "Ana"), base: nil, hasLocalChanges: true)
        let second = CloudSyncEngine<Profile>(database: db)
        await #expect(throws: CloudSyncPayloadError.inconsistentIdentity) {
            _ = try await second.synchronize(local: Profile(id: "device-b", name: "Ana"), base: nil, hasLocalChanges: true)
        }
        #expect(try await db.fetchAll(type: Profile.recordType).map(\.id) == ["device-a"])
    }

    @Test func undecodablePayloadIsUnreadableNotFatal() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        // A newer app version writes a blob this version cannot decode.
        await db.seed([SyncRecord(id: "p", type: Profile.recordType, blob: Data("{\"v\":2}".utf8), modifiedAt: .distantPast)])
        guard case .remoteUnreadable = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: base, hasLocalChanges: false) else {
            Issue.record("undecodable payload must be reported, not thrown"); return
        }
    }

    @Test func repairIsAFullReplacementThatRemovesUnreadableFields() async throws {
        let db = MockCloudDatabase()
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .pushed(let base) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected a push"); return
        }
        var newer = try record(Profile(id: "p", name: "Newer"), at: .distantPast)
        newer.fields["unsupported"] = .string("asset-like")
        await db.seed([newer])
        await db.markUnreadable("p")
        guard case .remoteUnreadable(let version) = try await engine.synchronize(
            local: Profile(id: "p", name: "Ana"), base: base, hasLocalChanges: false) else {
            Issue.record("expected unreadable"); return
        }
        guard case .pushed(let repaired) = try await engine.synchronize(
            local: Profile(id: "p", name: "Repaired"), base: version, hasLocalChanges: true) else {
            Issue.record("repair must succeed"); return
        }
        #expect(try await db.fetchAll(type: Profile.recordType).first?.fields["unsupported"] == nil)
        guard case .upToDate = try await engine.synchronize(
            local: Profile(id: "p", name: "Repaired"), base: repaired, hasLocalChanges: false) else {
            Issue.record("after repair the record must be readable and in sync"); return
        }
    }

    @Test func fullReplacementIsTheWayToClearAField() async throws {
        let db = MockCloudDatabase()
        let v1 = try await db.save(SyncRecord(id: "r", type: "T", fields: ["note": .string("private")],
                                              modifiedAt: .distantPast), expecting: nil)
        _ = try await db.save(SyncRecord(id: "r", type: "T", fields: [:], modifiedAt: .distantPast),
                              expecting: v1, replacingAllFields: true)
        #expect(try await db.fetchAll(type: "T").first?.fields["note"] == nil)
    }

    @Test func freshDeviceFindsAndRepairsAnUnreadableProfile() async throws {
        let db = MockCloudDatabase()
        await db.seed([try record(Profile(id: "p", name: "Newer"), at: .distantPast)])
        await db.markUnreadable("p")
        let engine = CloudSyncEngine<Profile>(database: db)
        // Never synced (no base): discovery must not throw on unreadable content.
        guard case .remoteUnreadable(let version) = try await engine.synchronize(
            local: Profile(id: "p", name: "Mine"), base: nil, hasLocalChanges: true) else {
            Issue.record("a fresh device must be told the profile is unreadable"); return
        }
        guard case .pushed = try await engine.synchronize(
            local: Profile(id: "p", name: "Mine"), base: version, hasLocalChanges: true) else {
            Issue.record("deliberate repair must succeed"); return
        }
        // No local copy and no base: discovery + by-ID read, also tolerant.
        await db.markUnreadable("p")
        guard case .remoteUnreadable = try await engine.synchronize(local: nil, base: nil, hasLocalChanges: false) else {
            Issue.record("discovery without a local copy must report unreadable"); return
        }
    }

    @Test func payloadIdentityMismatchStaysAnIntegrityError() async throws {
        let db = MockCloudDatabase()
        // Record "p" whose payload claims to be "q".
        await db.seed([SyncRecord(id: "p", type: Profile.recordType,
                                  blob: try JSONEncoder().encode(Profile(id: "q", name: "x")), modifiedAt: .distantPast)])
        let engine = CloudSyncEngine<Profile>(database: db)
        await #expect(throws: CloudSyncPayloadError.inconsistentIdentity) {
            _ = try await engine.synchronize(local: Profile(id: "p", name: "Mine"), base: nil, hasLocalChanges: false)
        }
    }

    @Test func overwritingAnUndecodablePayloadIsAFullReplacement() async throws {
        let db = MockCloudDatabase()
        var newer = SyncRecord(id: "p", type: Profile.recordType, blob: Data("{\"v\":2}".utf8), modifiedAt: .distantPast)
        newer.fields["extra"] = .string("from newer app")
        await db.seed([newer])
        let engine = CloudSyncEngine<Profile>(database: db)
        guard case .remoteUnreadable(let version) = try await engine.synchronize(
            local: Profile(id: "p", name: "Mine"), base: nil, hasLocalChanges: true) else {
            Issue.record("expected unreadable"); return
        }
        guard case .pushed = try await engine.synchronize(
            local: Profile(id: "p", name: "Mine"), base: version, hasLocalChanges: true) else {
            Issue.record("repair must succeed"); return
        }
        #expect(try await db.fetchAll(type: Profile.recordType).first?.fields["extra"] == nil)
        #expect(try await stored(in: db) == Profile(id: "p", name: "Mine"))
    }

    #if canImport(CloudKit)
    @Test func nativeVersionDecodingRejectsForgedOrUntaggedArchivesWithoutCrashing() throws {
        let id = CKRecord.ID(recordName: "p", zoneID: CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName))
        let record = CKRecord(recordType: Profile.recordType, recordID: id)
        // A never-saved record has no change tag: it cannot be a server version.
        #expect(throws: CloudSyncReadError.invalidRecord) { _ = try CloudKitDatabase.version(of: record) }
        // Real system-fields archive, but untagged: rejected.
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        let untagged = SyncRecordVersion(identity: Data("p".utf8), tag: Data("t".utf8),
                                         token: coder.encodedData, serverModifiedAt: nil)
        #expect(throws: CloudSyncReadError.invalidRecord) { _ = try CloudKitDatabase.decodeVersion(untagged) }
        // Garbage and a secure archive of another class: rejected, not crashed.
        let otherClass = try NSKeyedArchiver.archivedData(withRootObject: "not a record" as NSString,
                                                          requiringSecureCoding: true)
        for token in [Data("garbage".utf8), otherClass, Data(repeating: 0xFF, count: 512)] {
            let forged = SyncRecordVersion(identity: Data("p".utf8), tag: Data("t".utf8),
                                           token: token, serverModifiedAt: nil)
            #expect(throws: CloudSyncReadError.invalidRecord) { _ = try CloudKitDatabase.decodeVersion(forged) }
        }
    }
    #endif
}
