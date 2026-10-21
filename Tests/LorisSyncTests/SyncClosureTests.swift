import Foundation
import Testing
@testable import LorisSync

private struct ClosureProfile: SyncablePayload {
    static let recordType = "Profile"
    let id: String
    let value: Int
}
private enum ClosureFailure: Error { case denied }
private actor PausedProfileDatabase: CloudDatabase {
    private var paused = false
    private var fetch: CheckedContinuation<[SyncRecord], Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var writes: [Int] = []
    private var failSave = false
    func accountStatus() async -> SyncAccountStatus { .available }
    func fetchAll(type: String) async throws -> [SyncRecord] {
        if !paused {
            paused = true
            return await withCheckedContinuation { continuation in
                fetch = continuation
                entered?.resume(); entered = nil
            }
        }
        return []
    }
    func waitForFetch() async {
        if fetch != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func releaseFetch() { fetch?.resume(returning: []); fetch = nil }
    func save(_ records: [SyncRecord]) async throws {
        if failSave { throw ClosureFailure.denied }
        for record in records { writes.append(try JSONDecoder().decode(ClosureProfile.self, from: record.blob).value) }
    }
    func delete(ids: [String], type: String) async throws { writes.append(-1) }
    func values() -> [Int] { writes }
    func setFailSave(_ value: Bool) { failSave = value }
}

@Suite("Sync closure integrity, deterministic local scheduling")
struct SyncClosureTests {
    @Test(arguments: ["push", "pull", "delete", "reconcile"])
    func overlapCannotOvertakePendingReconcile(operation: String) async throws {
        let db = PausedProfileDatabase()
        let engine = CloudSyncEngine<ClosureProfile>(database: db)
        let first = Task { try await engine.reconcile(local: .init(id: "id", value: 1), localModifiedAt: .distantPast) }
        await db.waitForFetch()
        await #expect(throws: CloudSyncOperationError.operationInProgress) {
            switch operation {
            case "push": try await engine.push(.init(id: "id", value: 2))
            case "pull": _ = try await engine.pull()
            case "delete": try await engine.delete("id")
            default: _ = try await engine.reconcile(local: .init(id: "id", value: 2), localModifiedAt: .distantPast)
            }
        }
        #expect(await db.values().isEmpty)
        await db.releaseFetch()
        _ = try await first.value
        #expect(await db.values() == [1])
        try await engine.push(.init(id: "id", value: 3))
        #expect(await db.values() == [1, 3])
    }

    @Test func operationGateReleasesAfterWriteFailure() async throws {
        let db = PausedProfileDatabase()
        let engine = CloudSyncEngine<ClosureProfile>(database: db)
        await db.setFailSave(true)
        await #expect(throws: ClosureFailure.denied) { try await engine.push(.init(id: "id", value: 1)) }
        await db.setFailSave(false)
        try await engine.push(.init(id: "id", value: 2))
        #expect(await db.values() == [2])
    }

    @Test func cancelledOperationReleasesGateWithoutDispatchingWrite() async throws {
        let db = PausedProfileDatabase()
        let engine = CloudSyncEngine<ClosureProfile>(database: db)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await engine.push(.init(id: "id", value: 1))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await db.values().isEmpty)
        try await engine.push(.init(id: "id", value: 2))
        #expect(await db.values() == [2])
    }

    @Test func cancelledPendingReadReleasesGateWithoutUploading() async throws {
        let db = PausedProfileDatabase()
        let engine = CloudSyncEngine<ClosureProfile>(database: db)
        let task = Task { try await engine.reconcile(local: .init(id: "id", value: 1), localModifiedAt: .distantPast) }
        await db.waitForFetch()
        task.cancel()
        await db.releaseFetch()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await db.values().isEmpty)
        try await engine.push(.init(id: "id", value: 2))
        #expect(await db.values() == [2])
    }

    @Test(arguments: [false, true])
    func byteDistinctIDsSurviveOneOrManyPages(singlePage: Bool) throws {
        let a = item("\u{00E9}", 1), b = item("e\u{0301}", 2)
        let pages = singlePage ? [ZoneChanges(changed: [a, b])] : [ZoneChanges(changed: [a]), ZoneChanges(changed: [b])]
        let result = try SyncZoneAccumulator.combine(pages, token: Data([7]), wasReset: true)
        #expect(result.changed.count == 2)
        #expect(result.changed.map { Data($0.id.utf8) }.contains(Data(a.id.utf8)))
        #expect(result.changed.map { Data($0.id.utf8) }.contains(Data(b.id.utf8)))
        #expect(result.token == Data([7]))
    }

    @Test(arguments: [false, true])
    func deletingOneUnicodeSpellingPreservesTheOther(deleteFirst: Bool) throws {
        let a = item("\u{00E9}", 1), b = "e\u{0301}"
        let save = ZoneChanges(changed: [a]), deletion = ZoneChanges(deletedIDs: [b])
        let result = try SyncZoneAccumulator.combine(deleteFirst ? [deletion, save] : [save, deletion],
                                                     token: Data([7]), wasReset: false)
        #expect(result.changed.count == 1)
        #expect(result.deletedIDs.count == 1)
        #expect(result.changed.first.map { Data($0.id.utf8) } == Data(a.id.utf8))
        #expect(result.deletedIDs.first.map { Data($0.utf8) } == Data(b.utf8))
    }

    private func item(_ id: String, _ n: Int) -> SyncRecord {
        .init(id: id, type: "Item", fields: ["value": .int(n)], modifiedAt: Date(timeIntervalSince1970: 1))
    }
}
