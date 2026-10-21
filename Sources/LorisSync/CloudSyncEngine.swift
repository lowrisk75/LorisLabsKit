import Foundation

/// Syncs a single `SyncablePayload` over a `CloudDatabase`. Prefer
/// `synchronize(local:base:hasLocalChanges:)` (server compare-and-set, explicit
/// conflicts, no clocks) with a `VersionedCloudDatabase`. `reconcile` is legacy
/// last-writer-wins by client `modifiedAt` and trusts device clocks.
/// One complete operation at a time; overlap fails explicitly rather than reentering
/// a stale decision, queueing unbounded work or automatically replaying writes.
public actor CloudSyncEngine<P: SyncablePayload> {
    let database: CloudDatabase
    private let clock: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var operationInProgress = false

    func beginOperation() throws {
        try Task.checkCancellation()
        guard !operationInProgress else { throw CloudSyncOperationError.operationInProgress }
        operationInProgress = true
    }

    func endOperation() { operationInProgress = false }

    func outgoingRecord(_ payload: P) throws -> SyncRecord {
        guard let blob = try? encoder.encode(payload) else { throw SyncError.encodingFailed }
        let record = SyncRecord(id: payload.id, type: P.recordType, blob: blob, modifiedAt: clock())
        guard record.modifiedAt.timeIntervalSinceReferenceDate.isFinite else { throw CloudSyncPayloadError.invalidRecord }
        return record
    }

    func validatedRemote(_ record: SyncRecord, expectedID: String?) throws -> SyncRecord {
        guard let remote = try singleRemote([record], expectedID: expectedID) else {
            throw CloudSyncPayloadError.invalidRecord
        }
        return remote
    }

    func decoded(_ record: SyncRecord) throws -> P { try decodePayload(record) }

    public init(database: CloudDatabase, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.clock = clock
    }

    public func isAvailable() async -> Bool {
        await database.accountStatus() == .available
    }

    /// Upload the local payload, stamped now. Overwrites without compare-and-set.
    @available(*, deprecated, message: "Overwrites concurrent server changes. Use synchronize(local:base:hasLocalChanges:)")
    public func push(_ payload: P) async throws {
        try beginOperation()
        defer { operationInProgress = false }
        try await pushWithinOperation(payload)
    }

    private func pushWithinOperation(_ payload: P) async throws {
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        try Task.checkCancellation()
        let record = try outgoingRecord(payload)
        try Task.checkCancellation()
        try await database.save([record])
    }

    /// The newest remote payload, or nil if the cloud has none.
    public func pull() async throws -> P? {
        try beginOperation()
        defer { operationInProgress = false }
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        try Task.checkCancellation()
        let records = try await database.fetchAll(type: P.recordType)
        try Task.checkCancellation()
        guard let remote = try singleRemote(records, expectedID: nil) else { return nil }
        return try decodePayload(remote)
    }

    /// Request provider deletion; not a complete legal/privacy erasure workflow.
    /// Native physical data deletion is disabled unless explicitly configured.
    public func delete(_ id: String) async throws {
        try beginOperation()
        defer { operationInProgress = false }
        guard await isAvailable() else { throw SyncError.accountUnavailable }
        try Task.checkCancellation()
        try await database.delete(ids: [id], type: P.recordType)
    }

    /// One-shot legacy profile reconcile: may upload local state, or return an
    /// adoption candidate. Host must commit adoption only if its local revision
    /// is still current; this actor cannot protect edits in the host's store.
    @available(*, deprecated, message: "Trusts device clocks (last-writer-wins). Use synchronize(local:base:hasLocalChanges:) with a VersionedCloudDatabase")
    public func reconcile(local: P?, localModifiedAt: Date) async throws -> Reconciliation<P> {
        try beginOperation()
        defer { operationInProgress = false }
        // NaN/infinite would make every "remote is newer" test false.
        guard localModifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CloudSyncPayloadError.invalidRecord
        }
        guard await isAvailable() else { return .offline }
        try Task.checkCancellation()
        let records = try await database.fetchAll(type: P.recordType)
        try Task.checkCancellation()
        let remote = try singleRemote(records, expectedID: local?.id)

        switch (local, remote) {
        case (nil, nil):
            return .nothingYet
        case let (.some(localPayload), nil):
            try await pushWithinOperation(localPayload)
            return .pushedLocal
        case let (_, .some(remoteRecord)) where local == nil || remoteRecord.modifiedAt > localModifiedAt:
            let payload = try decodePayload(remoteRecord)
            return .adoptRemote(payload)
        case let (.some(localPayload), .some):
            try await pushWithinOperation(localPayload)
            return .pushedLocal
        default:
            return .nothingYet
        }
    }

    private func singleRemote(_ records: [SyncRecord], expectedID: String?) throws -> SyncRecord? {
        guard records.count <= 1 else { throw CloudSyncPayloadError.ambiguousProfiles }
        guard let remote = records.first else { return nil }
        guard remote.type.utf8.elementsEqual(P.recordType.utf8),
              remote.modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CloudSyncPayloadError.invalidRecord
        }
        if let expectedID, !remote.id.utf8.elementsEqual(expectedID.utf8) {
            throw CloudSyncPayloadError.inconsistentIdentity
        }
        return remote
    }
    private func decodePayload(_ record: SyncRecord) throws -> P {
        let payload = try decoder.decode(P.self, from: record.blob)
        guard payload.id.utf8.elementsEqual(record.id.utf8) else {
            throw CloudSyncPayloadError.inconsistentIdentity
        }
        return payload
    }
}

/// Outcome of a launch reconcile.
public enum Reconciliation<P: SyncablePayload>: Sendable {
    case offline          // no account → stay 100% local
    case nothingYet       // neither side has data
    case pushedLocal      // local seeded/leads the cloud
    case adoptRemote(P)   // the cloud is newer → overwrite local with this
}
