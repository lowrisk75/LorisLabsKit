import Foundation

/// Syncs a single `SyncablePayload` over a `CloudDatabase`. Conflict policy is
/// last-writer-wins by record `modifiedAt` — correct for one profile a caregiver
/// edits (concurrent two-device edits are rare). An `actor` so concurrent
/// push/pull serialize cleanly.
public actor CloudSyncEngine<P: SyncablePayload> {
    private let database: CloudDatabase
    private let clock: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: CloudDatabase, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.clock = clock
    }

    public func isAvailable() async -> Bool {
        await database.accountStatus() == .available
    }

    /// Upload the local payload, stamped now.
    public func push(_ payload: P) async throws {
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        guard let blob = try? encoder.encode(payload) else { throw SyncError.encodingFailed }
        let record = SyncRecord(id: payload.id, type: P.recordType, blob: blob, modifiedAt: clock())
        try await database.save([record])
    }

    /// The newest remote payload, or nil if the cloud has none.
    public func pull() async throws -> P? {
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        let records = try await database.fetchAll(type: P.recordType)
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else { return nil }
        return try decoder.decode(P.self, from: newest.blob)
    }

    /// Erase the payload from the cloud (GDPR erasure).
    public func delete(_ id: String) async throws {
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        try await database.delete(ids: [id], type: P.recordType)
    }

    /// One-shot reconcile for first run / launch: returns the payload to ADOPT
    /// locally (cloud was newer or local was absent), or nil if the local copy
    /// already leads — in which case the caller should `push` it. The caller
    /// passes its local payload + the time it last changed.
    public func reconcile(local: P?, localModifiedAt: Date) async throws -> Reconciliation<P> {
        guard await isAvailable() else { return .offline }
        let records = try await database.fetchAll(type: P.recordType)
        let remote = records.max(by: { $0.modifiedAt < $1.modifiedAt })

        switch (local, remote) {
        case (nil, nil):
            return .nothingYet
        case let (.some(localPayload), nil):
            try await push(localPayload)
            return .pushedLocal
        case let (_, .some(remoteRecord)) where local == nil || remoteRecord.modifiedAt > localModifiedAt:
            let payload = try decoder.decode(P.self, from: remoteRecord.blob)
            return .adoptRemote(payload)
        case let (.some(localPayload), .some):
            try await push(localPayload)
            return .pushedLocal
        default:
            return .nothingYet
        }
    }
}

/// Outcome of a launch reconcile.
public enum Reconciliation<P: SyncablePayload>: Sendable {
    case offline          // no account → stay 100% local
    case nothingYet       // neither side has data
    case pushedLocal      // local seeded/leads the cloud
    case adoptRemote(P)   // the cloud is newer → overwrite local with this
}
