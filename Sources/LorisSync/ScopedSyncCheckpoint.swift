import Foundation

public enum CloudSyncCheckpointError: Error, Equatable, Sendable {
    case scopeMismatch, capacityExceeded, invalidLimits
}

/// Host-verified scope binding, NOT provider authentication, encryption or rollback protection.
/// Store encoded bytes with fetched domain state in ONE host transaction.
public struct ScopedSyncCheckpoint: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private struct Snapshot: Codable {
        let version: Int
        let scope: SyncOutboxScope
        let recordType: String
        let token: Data
    }
    public let scope: SyncOutboxScope
    public let recordType: String
    private let token: Data
    private let maximumEncodedBytes: Int
    public var description: String { "ScopedSyncCheckpoint(<redacted>)" }
    public var debugDescription: String { description }

    public init(scope: SyncOutboxScope, recordType: String, token: Data,
                maximumEncodedBytes: Int = 8_388_608) throws {
        try Self.validate(scope: scope, recordType: recordType, limit: maximumEncodedBytes)
        guard !token.isEmpty else { throw CloudSyncReadError.invalidCheckpoint }
        guard token.count <= maximumEncodedBytes else { throw CloudSyncCheckpointError.capacityExceeded }
        self.scope = scope; self.recordType = recordType; self.token = token
        self.maximumEncodedBytes = maximumEncodedBytes
        _ = try encoded()
    }
    public init(restoring data: Data, expectedScope: SyncOutboxScope, recordType: String,
                maximumEncodedBytes: Int = 8_388_608) throws {
        try Self.validate(scope: expectedScope, recordType: recordType, limit: maximumEncodedBytes)
        guard data.count <= maximumEncodedBytes else { throw CloudSyncCheckpointError.capacityExceeded }
        let snapshot: Snapshot
        do { snapshot = try JSONDecoder().decode(Snapshot.self, from: data) }
        catch { throw CloudSyncReadError.invalidCheckpoint }
        guard snapshot.version == 1 else { throw CloudSyncReadError.invalidCheckpoint }
        guard snapshot.scope == expectedScope,
              snapshot.recordType.utf8.elementsEqual(recordType.utf8) else {
            throw CloudSyncCheckpointError.scopeMismatch
        }
        try self.init(scope: snapshot.scope, recordType: snapshot.recordType, token: snapshot.token,
                      maximumEncodedBytes: maximumEncodedBytes)
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Snapshot(version: 1, scope: scope, recordType: recordType, token: token))
        guard data.count <= maximumEncodedBytes else { throw CloudSyncCheckpointError.capacityExceeded }
        return data
    }
    public func token(expectedScope: SyncOutboxScope, recordType: String) throws -> Data {
        guard scope == expectedScope, self.recordType.utf8.elementsEqual(recordType.utf8) else {
            throw CloudSyncCheckpointError.scopeMismatch
        }
        return token
    }
    static func validate(scope: SyncOutboxScope, recordType: String, limit: Int) throws {
        guard (256...134_217_728).contains(limit) else { throw CloudSyncCheckpointError.invalidLimits }
        try SyncRecordValidation.validateType(recordType)
        for field in [scope.accountID, scope.namespace] {
            guard field.utf8.count <= 4_096 else { throw CloudSyncCheckpointError.capacityExceeded }
            try SyncRecordValidation.validateID(field)
        }
    }
}

public struct ScopedSyncChanges: Sendable {
    public let changed: [SyncRecord]
    public let deletedIDs: [String]
    public let wasReset: Bool
    public let checkpoint: ScopedSyncCheckpoint
    /// Unreadable changed records; not deletions (see `ZoneChanges.quarantined`).
    public let quarantined: [QuarantinedRecord]
}

extension IncrementalCloudDatabase {
    /// Caller must verify the active provider account and a fully qualified
    /// provider/container/database/zone/owner namespace before starting, then stop
    /// dispatch/adoption on account change. This wrapper cannot authenticate it.
    public func fetchScopedChanges(type: String, since checkpoint: ScopedSyncCheckpoint?,
                                   scope: SyncOutboxScope, maximumCheckpointBytes: Int = 8_388_608) async throws -> ScopedSyncChanges {
        try Task.checkCancellation()
        try ScopedSyncCheckpoint.validate(scope: scope, recordType: type, limit: maximumCheckpointBytes)
        let raw = try checkpoint?.token(expectedScope: scope, recordType: type)
        if let checkpoint, try checkpoint.encoded().count > maximumCheckpointBytes {
            throw CloudSyncCheckpointError.capacityExceeded
        }
        let changes = try await fetchChanges(type: type, since: raw)
        try Task.checkCancellation()
        guard let token = changes.token else { throw CloudSyncReadError.invalidCheckpoint }
        let bound = try ScopedSyncCheckpoint(scope: scope, recordType: type, token: token,
                                            maximumEncodedBytes: maximumCheckpointBytes)
        return ScopedSyncChanges(changed: changes.changed, deletedIDs: changes.deletedIDs,
                                 wasReset: changes.wasReset, checkpoint: bound,
                                 quarantined: changes.quarantined)
    }
}
