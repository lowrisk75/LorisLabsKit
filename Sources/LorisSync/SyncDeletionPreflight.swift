import Foundation

/// A preflight failed before deletion dispatch. This is NOT a server CAS policy.
public enum CloudSyncDeletionError: Error, Equatable, Sendable {
    case recordTypeMismatch, inconsistentIdentity, physicalDeletionDisabled
}

/// Physical data deletion has no native expected-type/generation precondition.
/// The non-atomic option is an explicit compatibility decision, not a safe CAS.
public enum CloudSyncPhysicalDeletionPolicy: Sendable {
    case disabled
    case allowNonAtomicPreflight

    func requirePermission() throws {
        guard case .allowNonAtomicPreflight = self else {
            throw CloudSyncDeletionError.physicalDeletionDisabled
        }
    }
}

enum SyncDeletionPreflight {
    static func perform<Key: Hashable & Sendable, Record: Sendable>(
        ids: [Key], type: String, policy: CloudSyncPhysicalDeletionPolicy = .disabled,
        lookup: @Sendable (Key) async throws -> Record,
        matchesIdentity: @Sendable (Key, Record) -> Bool,
        recordType: @Sendable (Record) -> String,
        remove: @Sendable ([Key]) async throws -> Void
    ) async throws {
        try SyncWriteAcknowledgements.validateRequest(saving: [], deleting: ids)
        try Task.checkCancellation()
        guard !ids.isEmpty else { return }
        try policy.requirePermission()
        guard !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudSyncWriteError.invalidMutation
        }
        // Read/validate the whole request before ANY mutation, never a prefix.
        // This read is not atomic with the later provider ID-only deletion:
        // replacement races and account transitions require host/server policy.
        for id in ids {
            try Task.checkCancellation()
            let record = try await lookup(id)
            try Task.checkCancellation()
            guard matchesIdentity(id, record) else {
                throw CloudSyncDeletionError.inconsistentIdentity
            }
            guard recordType(record).utf8.elementsEqual(type.utf8) else {
                throw CloudSyncDeletionError.recordTypeMismatch
            }
        }
        try Task.checkCancellation()
        try await remove(ids)
        // No late cancellation error implying rollback of committed deletions.
    }
}
