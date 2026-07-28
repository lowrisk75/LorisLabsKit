import Foundation

/// One synced record, engine-facing and CloudKit-agnostic. The payload lives in
/// `blob` (JSON); `modifiedAt` drives last-writer-wins.
public struct SyncRecord: Sendable, Equatable {
    public let id: String
    public let type: String
    public var blob: Data
    public var modifiedAt: Date

    public init(id: String, type: String, blob: Data, modifiedAt: Date) {
        self.id = id
        self.type = type
        self.blob = blob
        self.modifiedAt = modifiedAt
    }
}

/// Whether the user's iCloud account can currently be used.
public enum SyncAccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, temporarilyUnavailable, unknown
}

/// The minimal CloudKit surface the engine needs, behind a protocol so it can be
/// mocked in tests (CI never touches real iCloud). A single small profile makes
/// a full fetch/save correct and simple — no change-token bookkeeping required.
public protocol CloudDatabase: Sendable {
    func accountStatus() async -> SyncAccountStatus
    /// Save (insert-or-replace) records in the user's private zone.
    func save(_ records: [SyncRecord]) async throws
    /// Every record of `type` in the zone (one profile → a tiny set).
    func fetchAll(type: String) async throws -> [SyncRecord]
    /// Delete records by id (GDPR erasure — wiping the synced profile).
    func delete(ids: [String], type: String) async throws
}

public enum SyncError: Error, Equatable {
    case accountUnavailable
    case encodingFailed
}
