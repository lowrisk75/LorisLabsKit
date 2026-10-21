import Foundation
import Testing
@testable import LorisSync

private actor FollowUpEffects {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func recorded() -> [String] { events }
}

private struct FollowUpProfile: SyncablePayload, Equatable {
    static let recordType = "FollowUpProfile"
    let id: String
}

@Suite("Final review follow-ups (R-F2, C-1, C-5, C-6), no provider")
struct SyncReviewFollowUpTests {
    @Test func ownerRevocationIgnoresCollidingSharedRoots() async throws {
        let effects = FollowUpEffects()
        try await SyncShareResolution.removeOwned(
            privateRoot: { "private/root" },
            remove: { candidate in
                #expect(candidate.scope == .privateDatabase)
                await effects.record(candidate.root)
            })
        #expect(await effects.recorded() == ["private/root"])
    }

    @Test func ownerRevocationWithoutPrivateRootRemovesNothing() async {
        let effects = FollowUpEffects()
        await #expect(throws: ShareError.recordNotFound) {
            try await SyncShareResolution.removeOwned(
                privateRoot: { nil as String? },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func leaveNeverSelectsPrivateAndStillRefusesSharedCollisions() async throws {
        let effects = FollowUpEffects()
        try await SyncShareResolution.removeParticipating(
            sharedZones: { [1, 2] },
            sharedRoot: { zone in zone == 2 ? "zone2/root" : nil },
            remove: { candidate in
                #expect(candidate.scope == .sharedDatabase)
                await effects.record(candidate.root)
            })
        #expect(await effects.recorded() == ["zone2/root"])
        await #expect(throws: CloudSyncSharingError.ambiguousRecord) {
            try await SyncShareResolution.removeParticipating(
                sharedZones: { [1, 2] }, sharedRoot: { zone in "root-\(zone)" },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded() == ["zone2/root"])
    }

    @Test func canonicallyEquivalentIDsAreDistinctBytes() throws {
        let composed = "\u{00E9}", decomposed = "e\u{0301}"
        #expect(composed == decomposed) // Swift String equality is canonical.
        try SyncShareResolution.ensureUniqueIDs([Data(composed.utf8), Data(decomposed.utf8)])
        #expect(throws: CloudSyncSharingError.ambiguousRecord) {
            try SyncShareResolution.ensureUniqueIDs([Data(composed.utf8), Data(composed.utf8)])
        }
    }

    @Test func reflectionAndDescriptionsDoNotExposeSecrets() throws {
        let scope = SyncOutboxScope(accountID: "account-secret", namespace: "ns-secret")
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Note",
                                                  token: Data("token-secret".utf8))
        let share = ShareInfo(url: URL(string: "https://www.icloud.com/share/url-secret")!,
                              recordID: "record-secret", isOwner: true, participantCount: 2)
        let record = SyncRecord(id: "record-secret", type: "Note",
                                fields: ["body": .string("payload-secret")], modifiedAt: Date())
        let changes = ZoneChanges(changed: [record], deletedIDs: ["deleted-secret"],
                                  token: Data("token-secret".utf8), wasReset: false)
        for value in [checkpoint, scope, share, record, changes] as [Any] {
            var dumped = ""
            dump(value, to: &dumped)
            let rendered = dumped + String(describing: value) + String(reflecting: value)
            #expect(!rendered.contains("secret"))
            #expect(!rendered.contains("dG9rZW4")) // base64 of the token
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteLocalTimestampIsRejectedBeforeAnyRead(seconds: Double) async throws {
        let database = MockCloudDatabase()
        let engine = CloudSyncEngine<FollowUpProfile>(database: database)
        await #expect(throws: CloudSyncPayloadError.invalidRecord) {
            _ = try await engine.reconcile(local: FollowUpProfile(id: "p"),
                                           localModifiedAt: Date(timeIntervalSinceReferenceDate: seconds))
        }
        #expect(try await database.fetchAll(type: FollowUpProfile.recordType).isEmpty)
    }
}
