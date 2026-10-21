/// Overlapping profile operations are rejected, never queued or replayed implicitly.
public enum CloudSyncOperationError: Error, Equatable, Sendable {
    case operationInProgress
}

public enum CloudSyncPayloadError: Error, Equatable, Sendable {
    case invalidRecord, inconsistentIdentity, ambiguousProfiles
}
