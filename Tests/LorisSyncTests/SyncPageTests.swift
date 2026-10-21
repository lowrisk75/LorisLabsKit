import Foundation
import Testing
@testable import LorisSync

private enum PageFixtureError: Error, Equatable { case denied }

private actor PageScript<Value: Sendable> {
    var pages: [SyncResultPage<Value, Int>]
    var cursors: [Int?] = []

    init(_ pages: [SyncResultPage<Value, Int>]) { self.pages = pages }
    func fetch(_ cursor: Int?) throws -> SyncResultPage<Value, Int> {
        cursors.append(cursor)
        guard !pages.isEmpty else { throw PageFixtureError.denied }
        return pages.removeFirst()
    }
    func requests() -> [Int?] { cursors }
}

@Suite("Complete sync reads, synthetic pages")
struct SyncPageTests {
    @Test func drainsPagesAndOnlyReturnsFinalCheckpoint() async throws {
        let script = PageScript([
            SyncResultPage(results: [.success(1)], continuation: 11, checkpoint: 11),
            SyncResultPage(results: [], continuation: 12, checkpoint: 12),
            SyncResultPage(results: [.success(2)], continuation: nil, checkpoint: 13)
        ])
        let result = try await SyncPageCollector.collect(startingAt: 10, fetch: { try await script.fetch($0) })
        #expect(result.values == [1, 2])
        #expect(result.checkpoint == 13)
        #expect(await script.requests() == [10, 11, 12])
    }

    @Test func failedItemDoesNotBecomePartialSuccessOrCheckpoint() async {
        let script = PageScript([
            SyncResultPage(results: [.success(1)], continuation: 1, checkpoint: 1),
            SyncResultPage(results: [.success(2), .failure(PageFixtureError.denied)],
                           continuation: 2, checkpoint: 2),
            SyncResultPage(results: [.success(3)], continuation: nil, checkpoint: 3)
        ])
        await #expect(throws: PageFixtureError.denied) {
            _ = try await SyncPageCollector.collect(fetch: { try await script.fetch($0) })
        }
        #expect(await script.requests() == [nil, 1])
    }

    @Test func laterPageFailureThrowsInsteadOfReturningPrefix() async {
        let script = PageScript([
            SyncResultPage(results: [.success(1)], continuation: 1)
        ])
        await #expect(throws: PageFixtureError.denied) {
            _ = try await SyncPageCollector.collect(fetch: { try await script.fetch($0) })
        }
        #expect(await script.requests() == [nil, 1])
    }

    @Test func repeatedCursorIsBoundedWithoutExtraFetch() async {
        let script = PageScript([
            SyncResultPage(results: [.success(1)], continuation: 1),
            SyncResultPage(results: [.success(2)], continuation: 1),
            SyncResultPage(results: [.success(3)], continuation: nil)
        ])
        await #expect(throws: CloudSyncReadError.paginationLimitExceeded) {
            _ = try await SyncPageCollector.collect(maxPages: 2, fetch: { try await script.fetch($0) })
        }
        #expect(await script.requests() == [nil, 1])
    }

    @Test func cancellationAfterFetchDoesNotReleaseValuesOrAbsence() async {
        for hasValue in [false, true] {
            let task = Task {
                try await SyncPageCollector.collect { (_: Int?) in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return SyncResultPage<Int, Int>(
                        results: hasValue ? [.success(1)] : [], continuation: nil, checkpoint: 7)
                }
            }
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        }
    }

    @Test func cancellationBeforeFetchDoesNotCallBackend() async {
        let script = PageScript([SyncResultPage(results: [.success(1)], continuation: nil)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SyncPageCollector.collect(fetch: { try await script.fetch($0) })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await script.requests().isEmpty)
    }

    @Test func profileBlobAndTypedSchemaAreNotTruncated() async throws {
        // Contract shapes, not imported/migrated app code or native CKRecords.
        let profile = SyncRecord(id: "profile", type: "Profile", blob: Data("{}".utf8),
                                 modifiedAt: Date(timeIntervalSince1970: 1))
        let typed = SyncRecord(id: "item", type: "Item", fields: ["title": .string("fixture")],
                               modifiedAt: Date(timeIntervalSince1970: 2))
        let script = PageScript([
            SyncResultPage(results: [.success(profile)], continuation: 1),
            SyncResultPage(results: [.success(typed)], continuation: nil)
        ])
        let result = try await SyncPageCollector.collect(fetch: { try await script.fetch($0) })
        #expect(result.values == [profile, typed])
    }

    @Test func laterPageDeleteAndRecreationHaveOneFinalState() throws {
        let early = record("a", 1)
        let later = record("b", 2)
        let newest = record("a", 3)
        let result = try SyncZoneAccumulator.combine([
            ZoneChanges(changed: [early, later]),
            ZoneChanges(deletedIDs: ["a", "b"]),
            ZoneChanges(changed: [newest])
        ], token: Data([9]), wasReset: true)
        #expect(result.changed == [newest])
        #expect(result.deletedIDs == ["b"])
        #expect(result.token == Data([9]))
        #expect(result.wasReset)
    }

    @Test func contradictoryOrDuplicateUnorderedPageIsRejected() {
        let a = record("a", 1)
        for page in [
            ZoneChanges(changed: [a], deletedIDs: ["a"]),
            ZoneChanges(changed: [a, a]),
            ZoneChanges(deletedIDs: ["a", "a"])
        ] {
            #expect(throws: CloudSyncReadError.conflictingChanges) {
                try SyncZoneAccumulator.combine([page], token: Data([1]), wasReset: false)
            }
        }
    }

    @Test func emptySnapshotIsARealSuccessNotAnErrorFallback() async throws {
        let script = PageScript<Int>([
            SyncResultPage(results: [], continuation: nil, checkpoint: 8)
        ])
        let result = try await SyncPageCollector.collect(fetch: { try await script.fetch($0) })
        #expect(result.values.isEmpty)
        #expect(result.checkpoint == 8)
    }

    private func record(_ id: String, _ version: Int) -> SyncRecord {
        SyncRecord(id: id, type: "Item", fields: ["v": .int(version)],
                   modifiedAt: Date(timeIntervalSince1970: Double(version)))
    }
}
