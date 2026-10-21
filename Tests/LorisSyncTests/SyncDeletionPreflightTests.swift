import Foundation
import Testing
@testable import LorisSync

private enum DeleteFixtureError: Error, Equatable { case denied, missing, offline }
private struct DeleteMetadata: Sendable { let id: String; let type: String }
private actor DeleteScript {
    let rows: [String: DeleteMetadata]
    let failureID: String?
    let removeFailure: Bool
    private var events: [String] = []
    init(_ rows: [String: DeleteMetadata] = [:], failureID: String? = nil, removeFailure: Bool = false) {
        self.rows = rows; self.failureID = failureID; self.removeFailure = removeFailure
    }
    func lookup(_ id: String) throws -> DeleteMetadata {
        events.append("read:" + id)
        if id == failureID { throw DeleteFixtureError.denied }
        guard let row = rows[id] else { throw DeleteFixtureError.missing }
        return row
    }
    func remove(_ ids: [String]) throws {
        events.append("delete:" + ids.joined(separator: ","))
        if removeFailure { throw DeleteFixtureError.offline }
    }
    func recorded() -> [String] { events }
}

@Suite("Deletion preflight, synthetic callbacks; not server CAS")
struct SyncDeletionPreflightTests {
    @Test func allReadsPrecedeOneBatchDispatch() async throws {
        let script = goodScript()
        try await perform(script)
        #expect(await script.recorded() == ["read:a", "read:b", "delete:a,b"])
    }

    @Test func wrongTypeAfterValidPrefixPreventsEveryDeletion() async {
        let script = DeleteScript(["a": row("a"), "b": row("b", type: "Other")])
        await #expect(throws: CloudSyncDeletionError.recordTypeMismatch) { try await perform(script) }
        #expect(await script.recorded() == ["read:a", "read:b"])
    }

    @Test func returnedWrongIdentityPreventsDeletion() async {
        let script = DeleteScript(["a": row("different")])
        await #expect(throws: CloudSyncDeletionError.inconsistentIdentity) {
            try await perform(script, ids: ["a"])
        }
        #expect(await script.recorded() == ["read:a"])
    }

    @Test func lookupFailureAfterValidPrefixPropagatesWithoutMutation() async {
        let script = DeleteScript(["a": row("a")], failureID: "b")
        await #expect(throws: DeleteFixtureError.denied) { try await perform(script) }
        #expect(await script.recorded() == ["read:a", "read:b"])
    }

    @Test func missingRecordIsNotInventedSuccess() async {
        let script = DeleteScript()
        await #expect(throws: DeleteFixtureError.missing) { try await perform(script, ids: ["a"]) }
        #expect(await script.recorded() == ["read:a"])
    }

    @Test func duplicateRequestFailsBeforeReads() async {
        let script = goodScript()
        await #expect(throws: CloudSyncWriteError.invalidMutation) {
            try await perform(script, ids: ["a", "a"])
        }
        #expect(await script.recorded().isEmpty)
    }

    @Test func emptyRequestHasNoReadsOrMutation() async throws {
        let script = DeleteScript()
        try await perform(script, ids: [])
        #expect(await script.recorded().isEmpty)
    }

    @Test func blankTypeFailsBeforeReads() async {
        let script = goodScript()
        await #expect(throws: CloudSyncWriteError.invalidMutation) {
            try await perform(script, type: " \n")
        }
        #expect(await script.recorded().isEmpty)
    }

    @Test func typeComparisonUsesExactUTF8() async {
        let script = DeleteScript(["a": row("a", type: "e\u{0301}")])
        await #expect(throws: CloudSyncDeletionError.recordTypeMismatch) {
            try await perform(script, ids: ["a"], type: "\u{00E9}")
        }
        #expect(await script.recorded() == ["read:a"])
    }

    @Test func cancellationBeforeLookupPreventsEveryEffect() async {
        let script = goodScript()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await perform(script)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await script.recorded().isEmpty)
    }

    @Test func cancellationDuringLastLookupPreventsDeletion() async {
        let script = goodScript()
        let task = Task {
            try await SyncDeletionPreflight.perform(
                ids: ["a", "b"], type: "Fixture", policy: .allowNonAtomicPreflight,
                lookup: { id in
                    let row = try await script.lookup(id)
                    if id == "b" { withUnsafeCurrentTask { $0?.cancel() } }
                    return row
                }, matchesIdentity: { $0 == $1.id }, recordType: { $0.type },
                remove: { try await script.remove($0) })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await script.recorded() == ["read:a", "read:b"])
    }

    @Test func mutationFailurePropagatesWithoutReplay() async {
        let script = DeleteScript(["a": row("a"), "b": row("b")], removeFailure: true)
        await #expect(throws: DeleteFixtureError.offline) { try await perform(script) }
        #expect(await script.recorded() == ["read:a", "read:b", "delete:a,b"])
    }

    @Test func lateCancellationDoesNotInventRollback() async throws {
        let script = goodScript()
        let task = Task {
            try await SyncDeletionPreflight.perform(
                ids: ["a"], type: "Fixture", policy: .allowNonAtomicPreflight,
                lookup: { try await script.lookup($0) },
                matchesIdentity: { $0 == $1.id }, recordType: { $0.type },
                remove: {
                    try await script.remove($0)
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }
        try await task.value
        #expect(await script.recorded() == ["read:a", "delete:a"])
    }

    private func row(_ id: String, type: String = "Fixture") -> DeleteMetadata {
        .init(id: id, type: type)
    }
    private func goodScript() -> DeleteScript { DeleteScript(["a": row("a"), "b": row("b")]) }
    private func perform(_ script: DeleteScript, ids: [String] = ["a", "b"], type: String = "Fixture") async throws {
        try await SyncDeletionPreflight.perform(
            ids: ids, type: type, policy: .allowNonAtomicPreflight,
            lookup: { try await script.lookup($0) },
            matchesIdentity: { $0 == $1.id }, recordType: { $0.type },
            remove: { try await script.remove($0) })
    }
}
