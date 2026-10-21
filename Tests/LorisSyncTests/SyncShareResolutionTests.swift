import Foundation
import Testing
@testable import LorisSync
#if canImport(CloudKit)
import CloudKit
#endif

enum ShareFixtureError: Error, Equatable, Sendable { case missing, offline, denied, malformed }

private actor ShareEffects {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func recorded() -> [String] { events }
}

@Suite("Sharing lookup and target resolution, synthetic callbacks")
struct SyncShareResolutionTests {
    @Test func explicitMissingIsTheOnlyAbsentResult() async throws {
        let value: String? = try await SyncShareResolution.optional(
            isMissing: { ($0 as? ShareFixtureError) == .missing }
        ) { throw ShareFixtureError.missing }
        #expect(value == nil)
        let found = try await SyncShareResolution.optional(isMissing: { _ in false }) { "found" }
        #expect(found == "found")
    }

    @Test(arguments: [ShareFixtureError.offline, .denied, .malformed])
    func otherFailuresNeverBecomeAbsence(error: ShareFixtureError) async {
        await #expect(throws: error) {
            let _: String? = try await SyncShareResolution.optional(
                isMissing: { ($0 as? ShareFixtureError) == .missing }
            ) { throw error }
        }
    }

    @Test func cancelledLookupDoesNotBecomeMissing() async {
        let task = Task {
            let value: String? = try await SyncShareResolution.optional(isMissing: { _ in true }) {
                withUnsafeCurrentTask { $0?.cancel() }
                throw ShareFixtureError.missing
            }
            return value
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func privateLookupFailurePreventsFallbackOrRemoval() async {
        let effects = ShareEffects()
        await #expect(throws: ShareFixtureError.offline) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { () async throws -> String? in throw ShareFixtureError.offline },
                sharedZones: { await effects.record("zones"); return [1] },
                sharedRoot: { _ in "shared" },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func failureAfterFindingCandidateStillPreventsRemoval() async {
        let effects = ShareEffects()
        await #expect(throws: ShareFixtureError.denied) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { [1, 2] },
                sharedRoot: { zone in
                    if zone == 2 { throw ShareFixtureError.denied }
                    return "shared-1"
                },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test(arguments: [false, true])
    func sharedCollisionsRefuseRegardlessOfEnumerationOrder(reverse: Bool) async {
        let effects = ShareEffects()
        await #expect(throws: CloudSyncSharingError.ambiguousRecord) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { reverse ? [2, 1] : [1, 2] },
                sharedRoot: { zone in "root-in-zone-\(zone)" },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test(arguments: ["private-shared-root", "private-unshared-shadow"])
    func privateRootAlsoCountsAsAmbiguous(privateRoot: String) async {
        let effects = ShareEffects()
        await #expect(throws: CloudSyncSharingError.ambiguousRecord) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { privateRoot }, sharedZones: { [1] },
                sharedRoot: { _ in "shared-root" },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func uniqueSharedRootKeepsItsExactScopeAndIdentity() async throws {
        let effects = ShareEffects()
        try await SyncShareResolution.removeUnique(
            privateRoot: { nil as String? }, sharedZones: { [1, 2, 3] },
            sharedRoot: { zone in zone == 2 ? "zone2/root" : nil },
            remove: { candidate in
                #expect(candidate.scope == .sharedDatabase)
                await effects.record(candidate.root)
            })
        #expect(await effects.recorded() == ["zone2/root"])
    }

    @Test func privateRemovalWaitsForCompleteSharedScan() async throws {
        let effects = ShareEffects()
        try await SyncShareResolution.removeUnique(
            privateRoot: { "private/root" }, sharedZones: { [1, 2] },
            sharedRoot: { zone in
                await effects.record("lookup-\(zone)")
                return nil as String?
            },
            remove: { candidate in
                #expect(candidate.scope == .privateDatabase)
                await effects.record("remove")
            })
        #expect(await effects.recorded() == ["lookup-1", "lookup-2", "remove"])
    }

    @Test func noRootDoesNotPretendRemovalSucceeded() async {
        let effects = ShareEffects()
        await #expect(throws: ShareError.recordNotFound) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { [1] },
                sharedRoot: { _ in nil as String? },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func scanBudgetFailsBeforeAnySharedLookupOrRemoval() async {
        let effects = ShareEffects()
        await #expect(throws: CloudSyncSharingError.lookupLimitExceeded) {
            try await SyncShareResolution.removeUnique(
                maxZones: 1, privateRoot: { "private/root" }, sharedZones: { [1, 2] },
                sharedRoot: { _ in await effects.record("lookup"); return nil as String? },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func duplicateZoneEnumerationIsNotTrusted() async {
        let effects = ShareEffects()
        await #expect(throws: CloudSyncSharingError.inconsistentMetadata) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { [1, 1] },
                sharedRoot: { _ in "root" },
                remove: { _ in await effects.record("remove") })
        }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func ownershipRequiresKnownRoleNotOptionalIdentityEquality() throws {
        #expect(try SyncShareResolution.isOwner(role: .owner))
        #expect(try !SyncShareResolution.isOwner(role: .participant))
        #expect(throws: CloudSyncSharingError.inconsistentMetadata) {
            try SyncShareResolution.isOwner(role: .unknown)
        }
    }

    @Test func removalRoleMustMatchScope() throws {
        try SyncShareResolution.requireRemovalRole(scope: .privateDatabase, role: .owner, accepted: false)
        try SyncShareResolution.requireRemovalRole(scope: .sharedDatabase, role: .participant, accepted: true)
        for role in [SyncShareRole.participant, .unknown] {
            #expect(throws: ShareError.notOwner) {
                try SyncShareResolution.requireRemovalRole(scope: .privateDatabase, role: role, accepted: true)
            }
        }
        for role in [SyncShareRole.owner, .unknown] {
            #expect(throws: CloudSyncSharingError.inconsistentMetadata) {
                try SyncShareResolution.requireRemovalRole(scope: .sharedDatabase, role: role, accepted: true)
            }
        }
        #expect(throws: CloudSyncSharingError.inconsistentMetadata) {
            try SyncShareResolution.requireRemovalRole(scope: .sharedDatabase, role: .participant, accepted: false)
        }
    }

    @Test func duplicateUnqualifiedRecordIDsAreNotConflated() throws {
        try SyncShareResolution.ensureUniqueIDs(["one", "two"])
        #expect(throws: CloudSyncSharingError.ambiguousRecord) {
            try SyncShareResolution.ensureUniqueIDs(["same", "same"])
        }
    }

    @Test func cancellationDuringLastLookupPreventsRemoval() async {
        let effects = ShareEffects()
        let task = Task {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { [1] },
                sharedRoot: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "shared"
                },
                remove: { _ in await effects.record("remove") })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await effects.recorded().isEmpty)
    }

    @Test func removalErrorPropagatesWithoutReplayOrFallback() async {
        let effects = ShareEffects()
        await #expect(throws: ShareFixtureError.offline) {
            try await SyncShareResolution.removeUnique(
                privateRoot: { nil as String? }, sharedZones: { [1] }, sharedRoot: { _ in "shared" },
                remove: { _ in
                    await effects.record("attempt")
                    throw ShareFixtureError.offline
                })
        }
        #expect(await effects.recorded() == ["attempt"])
    }

    #if canImport(CloudKit)
    @Test func nativeErrorClassifierRequiresExactDomainAndCode() {
        for code in [CKError.Code.networkFailure, .permissionFailure, .partialFailure, .operationCancelled] {
            #expect(!CloudKitDatabase.isMissingRecord(NSError(domain: CKErrorDomain, code: code.rawValue)))
        }
        #expect(CloudKitDatabase.isMissingRecord(
            NSError(domain: CKErrorDomain, code: CKError.Code.unknownItem.rawValue)))
        #expect(!CloudKitDatabase.isMissingRecord(
            NSError(domain: "fixture.other-domain", code: CKError.Code.unknownItem.rawValue)))
    }
    #endif
}
