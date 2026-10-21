import Foundation

/// A read could not produce a complete, unambiguous result. Never treat this
/// as an empty snapshot or permission to erase local data.
public enum CloudSyncReadError: Error, Equatable, Sendable {
    case invalidRecord
    case conflictingChanges
    case paginationLimitExceeded
    case invalidCheckpoint
}

// Internal seam: exercised without CKContainer, accounts or network access.
struct SyncResultPage<Value: Sendable, Cursor: Sendable>: Sendable {
    var results: [Result<Value, any Error>]
    var continuation: Cursor?
    var checkpoint: Cursor? = nil
}

enum SyncPageCollector {
    /// Bound accepted pages, not native allocation or server work. No partial
    /// values/checkpoint escape on item error, page error, cancellation or limit.
    static func collect<Value: Sendable, Cursor: Sendable>(
        startingAt cursor: Cursor? = nil,
        maxPages: Int = 1_000,
        fetch: @Sendable (Cursor?) async throws -> SyncResultPage<Value, Cursor>
    ) async throws -> (values: [Value], checkpoint: Cursor?) {
        var cursor = cursor
        var values: [Value] = []
        var pageCount = 0
        while true {
            try Task.checkCancellation()
            guard pageCount < maxPages else {
                throw CloudSyncReadError.paginationLimitExceeded
            }
            let page = try await fetch(cursor)
            try Task.checkCancellation()
            for result in page.results {
                values.append(try result.get())
            }
            pageCount += 1
            guard let next = page.continuation else {
                return (values, page.checkpoint)
            }
            cursor = next
        }
    }
}

enum SyncZoneAccumulator {
    /// A later page supersedes an earlier change to the same identity.
    /// Two contrary events inside one unordered page have no defensible order.
    static func combine(_ pages: [ZoneChanges], token: Data?, wasReset: Bool) throws -> ZoneChanges {
        var records: [Data: SyncRecord] = [:]
        var deleted: [Data: String] = [:]
        for page in pages {
            let changedIDs = Set(page.changed.map { Data($0.id.utf8) })
            let deletedIDs = Set(page.deletedIDs.map { Data($0.utf8) })
            guard changedIDs.count == page.changed.count,
                  changedIDs.isDisjoint(with: deletedIDs),
                  deletedIDs.count == page.deletedIDs.count else {
                throw CloudSyncReadError.conflictingChanges
            }
            for record in page.changed {
                let identity = Data(record.id.utf8)
                records[identity] = record
                deleted.removeValue(forKey: identity)
            }
            for id in page.deletedIDs {
                let identity = Data(id.utf8)
                records.removeValue(forKey: identity)
                deleted[identity] = id
            }
        }
        return ZoneChanges(changed: records.values.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) },
                           deletedIDs: deleted.values.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) },
                           token: token, wasReset: wasReset)
    }
}
