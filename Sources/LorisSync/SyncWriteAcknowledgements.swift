import Foundation

/// Confirmation was incomplete or inconsistent. An error does NOT imply that
/// CloudKit rolled back every effect. Reconcile before retrying a mutation.
public enum CloudSyncWriteError: Error, Equatable, Sendable {
    case invalidMutation
    case incompleteAcknowledgement
    case mismatchedSavedIdentity
}

struct SyncMutationResult<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    var saves: [Key: Result<Value, any Error>]
    var deletions: [Key: Result<Void, any Error>]
}

enum SyncWriteAcknowledgements {
    static func validateRequest<Key: Hashable>(saving: [Key], deleting: [Key]) throws {
        let saves = Set(saving)
        let deletes = Set(deleting)
        guard saves.count == saving.count, deletes.count == deleting.count,
              saves.isDisjoint(with: deletes) else {
            throw CloudSyncWriteError.invalidMutation
        }
    }

    /// Exactly one dispatch; no partial success is exposed through the legacy
    /// Void contract. This is transport confirmation, not a durable local ACK.
    static func perform<Key: Hashable & Sendable, Value: Sendable>(
        saving: [Key], deleting: [Key],
        matchesIdentity: @Sendable (Key, Value) -> Bool = { _, _ in true },
        operation: @Sendable () async throws -> SyncMutationResult<Key, Value>
    ) async throws -> [Key: Value] {
        try validateRequest(saving: saving, deleting: deleting)
        try Task.checkCancellation()
        guard !saving.isEmpty || !deleting.isEmpty else { return [:] }
        let result = try await operation()
        // Do not throw solely for late cancellation after a committed mutation.
        // Still verify every confirmation; a success callback alone is not ACK.
        guard Set(result.saves.keys) == Set(saving),
              Set(result.deletions.keys) == Set(deleting) else {
            throw CloudSyncWriteError.incompleteAcknowledgement
        }
        var confirmed: [Key: Value] = [:]
        for key in saving {
            guard let outcome = result.saves[key] else {
                throw CloudSyncWriteError.incompleteAcknowledgement
            }
            let value = try outcome.get()
            guard matchesIdentity(key, value) else {
                throw CloudSyncWriteError.mismatchedSavedIdentity
            }
            confirmed[key] = value
        }
        for key in deleting {
            guard let outcome = result.deletions[key] else {
                throw CloudSyncWriteError.incompleteAcknowledgement
            }
            try outcome.get()
        }
        return confirmed
    }
}
