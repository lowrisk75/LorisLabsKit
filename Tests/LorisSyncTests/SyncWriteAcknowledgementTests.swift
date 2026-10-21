import Foundation
import Testing
@testable import LorisSync

private enum AckFixtureError: Error, Equatable { case denied, offline }

private actor MutationScript {
    let result: SyncMutationResult<String, String>
    let failure: AckFixtureError?
    private(set) var calls = 0
    init(_ result: SyncMutationResult<String, String>, failure: AckFixtureError? = nil) {
        self.result = result
        self.failure = failure
    }
    func dispatch() throws -> SyncMutationResult<String, String> {
        calls += 1
        if let failure { throw failure }
        return result
    }
    func count() -> Int { calls }
}

private struct AckProfile: SyncablePayload {
    static let recordType = "Profile"
    let id: String
    var label: String
}

private actor AcknowledgedDatabase: CloudDatabase {
    enum Mode: Sendable { case confirmed, missing, denied }
    let mode: Mode
    private(set) var calls = 0
    init(_ mode: Mode) { self.mode = mode }
    func accountStatus() async -> SyncAccountStatus { .available }
    func fetchAll(type: String) async throws -> [SyncRecord] { [] }
    func save(_ records: [SyncRecord]) async throws {
        _ = try await SyncWriteAcknowledgements.perform(
            saving: records.map(\.id), deleting: [], matchesIdentity: { $0 == $1.id }
        ) {
            await self.savedResults(records)
        }
    }
    private func savedResults(_ records: [SyncRecord]) -> SyncMutationResult<String, SyncRecord> {
        calls += 1
        var results: [String: Result<SyncRecord, any Error>] = [:]
        for record in records where mode != .missing {
            results[record.id] = mode == .denied ? .failure(AckFixtureError.denied) : .success(record)
        }
        return SyncMutationResult(saves: results, deletions: [:])
    }
    func delete(ids: [String], type: String) async throws {
        _ = try await SyncWriteAcknowledgements.perform(saving: [], deleting: ids) {
            await self.deletedResults(ids)
        } as [String: String]
    }
    private func deletedResults(_ ids: [String]) -> SyncMutationResult<String, String> {
        calls += 1
        var results: [String: Result<Void, any Error>] = [:]
        for id in ids where mode != .missing {
            results[id] = mode == .denied ? .failure(AckFixtureError.denied) : .success(())
        }
        return SyncMutationResult(saves: [:], deletions: results)
    }
    func count() -> Int { calls }
}

@Suite("Exact transport acknowledgements, synthetic operations")
struct SyncWriteAcknowledgementTests {
    @Test func returnsAcknowledgedServerValueNotClientEcho() async throws {
        let script = MutationScript(.init(saves: ["a": .success("server")], deletions: ["b": .success(())]))
        let confirmed = try await SyncWriteAcknowledgements.perform(saving: ["a"], deleting: ["b"]) {
            try await script.dispatch()
        }
        #expect(confirmed == ["a": "server"])
        #expect(await script.count() == 1)
    }

    @Test(arguments: [false, true])
    func propagatesItemErrorsWithoutReplay(deletion: Bool) async {
        let script = MutationScript(.init(
            saves: deletion ? [:] : ["a": .failure(AckFixtureError.denied)],
            deletions: deletion ? ["a": .failure(AckFixtureError.denied)] : [:]))
        await #expect(throws: AckFixtureError.denied) {
            _ = try await SyncWriteAcknowledgements.perform(
                saving: deletion ? [] : ["a"], deleting: deletion ? ["a"] : []
            ) { try await script.dispatch() }
        }
        #expect(await script.count() == 1)
    }

    @Test(arguments: 0..<4)
    func missingOrUnexpectedConfirmationIsNotSuccess(variant: Int) async {
        let response: SyncMutationResult<String, String>
        switch variant {
        case 0: response = .init(saves: [:], deletions: [:])
        case 1: response = .init(saves: ["a": .success("ok"), "extra": .success("other")], deletions: [:])
        case 2: response = .init(saves: ["a": .success("ok")], deletions: ["extra": .success(())])
        default: response = .init(saves: ["wrong": .success("ok")], deletions: [:])
        }
        let script = MutationScript(response)
        await #expect(throws: CloudSyncWriteError.incompleteAcknowledgement) {
            _ = try await SyncWriteAcknowledgements.perform(saving: ["a"], deleting: []) {
                try await script.dispatch()
            }
        }
        #expect(await script.count() == 1)
    }

    @Test func deleteMustHaveItsOwnAcknowledgement() async {
        let script = MutationScript(.init(saves: [:], deletions: [:]))
        await #expect(throws: CloudSyncWriteError.incompleteAcknowledgement) {
            _ = try await SyncWriteAcknowledgements.perform(saving: [], deleting: ["a"]) {
                try await script.dispatch()
            }
        }
    }

    @Test func mismatchedSavedIdentityIsRejected() async {
        let script = MutationScript(.init(saves: ["a": .success("other-id")], deletions: [:]))
        await #expect(throws: CloudSyncWriteError.mismatchedSavedIdentity) {
            _ = try await SyncWriteAcknowledgements.perform(
                saving: ["a"], deleting: [], matchesIdentity: { $0 == $1 }
            ) { try await script.dispatch() }
        }
    }

    @Test(arguments: 0..<3)
    func invalidRequestNeverDispatches(variant: Int) async {
        let script = MutationScript(.init(saves: [:], deletions: [:]))
        let saving = variant == 0 ? ["a", "a"] : (variant == 2 ? ["a"] : [])
        let deleting = variant == 1 ? ["a", "a"] : (variant == 2 ? ["a"] : [])
        await #expect(throws: CloudSyncWriteError.invalidMutation) {
            _ = try await SyncWriteAcknowledgements.perform(saving: saving, deleting: deleting) {
                try await script.dispatch()
            }
        }
        #expect(await script.count() == 0)
    }

    @Test func emptyMutationDoesNotDispatch() async throws {
        let script = MutationScript(.init(saves: [:], deletions: [:]))
        let confirmed = try await SyncWriteAcknowledgements.perform(saving: [], deleting: []) {
            try await script.dispatch()
        }
        #expect(confirmed.isEmpty)
        #expect(await script.count() == 0)
    }

    @Test func cancellationBeforeDispatchPreventsEffect() async {
        let script = MutationScript(.init(saves: ["a": .success("ok")], deletions: [:]))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SyncWriteAcknowledgements.perform(saving: ["a"], deleting: []) {
                try await script.dispatch()
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await script.count() == 0)
    }

    @Test func cancellationAfterCommitDoesNotInventRollback() async throws {
        let task = Task {
            try await SyncWriteAcknowledgements.perform(saving: ["a"], deleting: []) {
                withUnsafeCurrentTask { $0?.cancel() }
                return SyncMutationResult(saves: ["a": .success("confirmed")], deletions: [:])
            }
        }
        #expect(try await task.value == ["a": "confirmed"])
    }

    @Test func globalFailureIsNotRetried() async {
        let script = MutationScript(.init(saves: [:], deletions: [:]), failure: .offline)
        await #expect(throws: AckFixtureError.offline) {
            _ = try await SyncWriteAcknowledgements.perform(saving: ["a"], deleting: []) {
                try await script.dispatch()
            }
        }
        #expect(await script.count() == 1)
    }

    @Test func partialEffectsAreNotReportedAsWholeBatchSuccess() async {
        let script = MutationScript(.init(saves: [
            "confirmed-effect": .success("server"),
            "failed-effect": .failure(AckFixtureError.denied)
        ], deletions: [:]))
        await #expect(throws: AckFixtureError.denied) {
            _ = try await SyncWriteAcknowledgements.perform(
                saving: ["confirmed-effect", "failed-effect"], deleting: []
            ) { try await script.dispatch() }
        }
        #expect(await script.count() == 1) // No retry or compensating deletion.
    }

    @Test func profileReconcileCannotClaimPushedLocalWithoutAck() async {
        let db = AcknowledgedDatabase(.missing)
        let engine = CloudSyncEngine<AckProfile>(database: db)
        await #expect(throws: CloudSyncWriteError.incompleteAcknowledgement) {
            _ = try await engine.reconcile(local: AckProfile(id: "profile", label: "fixture"),
                                           localModifiedAt: .distantPast)
        }
        #expect(await db.count() == 1)
    }

    @Test func profilePushAndDeletePropagateItemFailure() async {
        let db = AcknowledgedDatabase(.denied)
        let engine = CloudSyncEngine<AckProfile>(database: db)
        await #expect(throws: AckFixtureError.denied) {
            try await engine.push(AckProfile(id: "profile", label: "fixture"))
        }
        await #expect(throws: AckFixtureError.denied) { try await engine.delete("profile") }
        #expect(await db.count() == 2)
    }

    @Test func profileReconcileStillSucceedsWithExactAck() async throws {
        let db = AcknowledgedDatabase(.confirmed)
        let engine = CloudSyncEngine<AckProfile>(database: db)
        let result = try await engine.reconcile(local: AckProfile(id: "profile", label: "fixture"),
                                                localModifiedAt: .distantPast)
        guard case .pushedLocal = result else {
            Issue.record("Expected acknowledged local push"); return
        }
        #expect(await db.count() == 1)
    }
}
