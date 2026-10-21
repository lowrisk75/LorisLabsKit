import Foundation

/// Opaque server version of one record (CloudKit: change tag + archived system
/// fields). Equality compares the record identity and the change tag. Persist it
/// next to the local copy and pass it back as the base of the next write; never
/// derived from device clocks.
public struct SyncRecordVersion: Sendable, Equatable, Codable, CustomStringConvertible,
                                 CustomDebugStringConvertible, CustomReflectable {
    /// UTF-8 bytes of the record ID this version belongs to.
    let identity: Data
    /// Server change identity (CloudKit change tag).
    let tag: Data
    /// Provider bytes needed to write against this version. Redacted from logs.
    let token: Data
    /// Server-assigned modification time, informational only (never used to order writes).
    public let serverModifiedAt: Date?

    static let maximumTokenBytes = 65_536
    static let maximumTagBytes = 1_024

    init(identity: Data, tag: Data, token: Data, serverModifiedAt: Date?) {
        self.identity = identity
        self.tag = tag
        self.token = token
        self.serverModifiedAt = serverModifiedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decode(Data.self, forKey: .identity)
        let tag = try container.decode(Data.self, forKey: .tag)
        let token = try container.decode(Data.self, forKey: .token)
        guard !identity.isEmpty, identity.count <= 4_096,
              !tag.isEmpty, tag.count <= Self.maximumTagBytes,
              !token.isEmpty, token.count <= Self.maximumTokenBytes,
              String(data: identity, encoding: .utf8) != nil else {
            throw CloudSyncReadError.invalidRecord
        }
        self.init(identity: identity, tag: tag, token: token,
                  serverModifiedAt: try container.decodeIfPresent(Date.self, forKey: .serverModifiedAt))
    }

    /// Record ID this version belongs to.
    var recordName: String { String(decoding: identity, as: UTF8.self) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.tag == rhs.tag
    }
    public var description: String { "SyncRecordVersion(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// A record together with the server version it was read at.
public struct VersionedSyncRecord: Sendable, Equatable {
    public let record: SyncRecord
    public let version: SyncRecordVersion
    public init(record: SyncRecord, version: SyncRecordVersion) {
        self.record = record
        self.version = version
    }
}

/// Strongly consistent single-record read.
public enum VersionedLookup: Sendable, Equatable {
    case missing
    case found(VersionedSyncRecord)
    /// The record exists at this version but its content cannot be mapped.
    case unreadable(SyncRecordVersion)
}

public enum CloudSyncConflictError: Error, Equatable, Sendable {
    /// The server copy changed since the expected version (or exists when
    /// creation was expected). `current` is nil when it could not be read safely.
    case serverRecordChanged(current: VersionedSyncRecord?)
    /// The database does not implement `VersionedCloudDatabase`.
    case versioningUnsupported
}

/// Compare-and-set storage: a write succeeds only if the server still holds the
/// expected version. Ordering comes from the server, never from client clocks.
public protocol VersionedCloudDatabase: CloudDatabase {
    /// Discovery: every record of `type` with its server version. Strict
    /// (complete-or-error). Query-backed: may lag recent writes on CloudKit.
    func fetchVersioned(type: String) async throws -> [VersionedSyncRecord]
    /// Strongly consistent read of one record by ID.
    func fetchVersioned(type: String, id: String) async throws -> VersionedLookup
    /// Discovery of record IDs only, tolerant of unreadable content (so a
    /// record written by a newer client can still be found and repaired).
    func discoverVersionedIDs(type: String) async throws -> [String]
    /// Write the record only if the server version still equals `expecting`
    /// (`nil` = create only; fails if the record already exists). Provided
    /// fields replace server values. With `replacingAllFields: false` fields not
    /// provided are PRESERVED (forward compatible with newer clients); with
    /// `true` every other field is removed (the way to clear a field, and to
    /// repair an unreadable record). Returns the new version; throws
    /// `CloudSyncConflictError.serverRecordChanged` otherwise.
    func save(_ record: SyncRecord, expecting version: SyncRecordVersion?,
              replacingAllFields: Bool) async throws -> SyncRecordVersion
}

extension VersionedCloudDatabase {
    /// Default discovery: strict listing. Adapters should override with an
    /// ID-only query that tolerates unreadable content.
    public func discoverVersionedIDs(type: String) async throws -> [String] {
        try await fetchVersioned(type: type).map(\.record.id)
    }

    /// Compare-and-set save that preserves fields not provided.
    public func save(_ record: SyncRecord, expecting version: SyncRecordVersion?) async throws -> SyncRecordVersion {
        try await save(record, expecting: version, replacingAllFields: false)
    }
}

/// Outcome of a clock-free, version-based synchronisation.
public enum VersionedReconciliation<P: SyncablePayload>: Sendable {
    /// No usable account; stay local.
    case offline
    /// Local and server agree at this version (nil: neither side has data).
    case upToDate(SyncRecordVersion?)
    /// Local changes were written; store this as the new base.
    case pushed(SyncRecordVersion)
    /// Server moved and the local copy had no changes: replace local, store
    /// version. Apply only if the host's copy did not change during the call.
    case adoptRemote(P, SyncRecordVersion)
    /// Both changed. Merge `remote` into the local edit, then synchronize again
    /// with `base: remoteVersion`. Nothing was written.
    case conflict(remote: P, remoteVersion: SyncRecordVersion)
    /// The record existed at `base` but is gone from the server (read by ID,
    /// strongly consistent). Host decides: recreate (synchronize with
    /// `base: nil`) or delete locally.
    case remoteDeleted
    /// The server record exists but cannot be read by this app version (e.g.
    /// written by a newer client, unsupported fields, or an undecodable
    /// payload). Nothing was written. To deliberately overwrite it (losing the
    /// unreadable content), synchronize with `base: remoteVersion,
    /// hasLocalChanges: true`: a compare-and-set full replacement. Keep this
    /// version only for that deliberate repair, not as the base of normal edits.
    case remoteUnreadable(remoteVersion: SyncRecordVersion)
}

extension CloudSyncEngine {
    /// Version-based reconcile (SOTA replacement for clock-based `reconcile`).
    /// Reads by ID whenever the record is known (strongly consistent); only a
    /// first sync with no local copy and no base uses discovery.
    /// - Parameters:
    ///   - local: the host's current payload, if any. Deleting the profile goes
    ///     through `delete`, not `local: nil`.
    ///   - base: server version the local copy was last synced at (nil: never synced).
    ///   - hasLocalChanges: whether `local` differs from what was synced at `base`.
    /// Do not mix with `push`/`save([SyncRecord])`: those overwrite without CAS.
    public func synchronize(local: P?, base: SyncRecordVersion?,
                            hasLocalChanges: Bool) async throws -> VersionedReconciliation<P> {
        try beginOperation()
        defer { endOperation() }
        guard let versioned = database as? any VersionedCloudDatabase else {
            throw CloudSyncConflictError.versioningUnsupported
        }
        // A local deletion is not expressible here; never report it as in sync.
        guard local != nil || !hasLocalChanges else { throw CloudSyncPayloadError.invalidRecord }
        if let local, let base, !base.identity.elementsEqual(local.id.utf8) {
            throw CloudSyncPayloadError.inconsistentIdentity
        }
        guard await isAvailable() else { return .offline }
        try Task.checkCancellation()

        let state: VersionedLookup
        if let id = local?.id ?? base?.recordName {
            if base == nil {
                // Never synced: refuse to create a second profile beside one
                // another device already created under a different ID.
                let existing = try await versioned.discoverVersionedIDs(type: P.recordType)
                guard existing.count <= 1 else { throw CloudSyncPayloadError.ambiguousProfiles }
                if let other = existing.first, !other.utf8.elementsEqual(id.utf8) {
                    throw CloudSyncPayloadError.inconsistentIdentity
                }
                try Task.checkCancellation()
            }
            state = try await versioned.fetchVersioned(type: P.recordType, id: id)
            if case .found(let remote) = state { _ = try validatedRemote(remote.record, expectedID: id) }
            if case .unreadable(let version) = state, !version.identity.elementsEqual(id.utf8) {
                throw CloudSyncPayloadError.inconsistentIdentity
            }
        } else {
            let ids = try await versioned.discoverVersionedIDs(type: P.recordType)
            guard ids.count <= 1 else { throw CloudSyncPayloadError.ambiguousProfiles }
            if let id = ids.first {
                try Task.checkCancellation()
                state = try await versioned.fetchVersioned(type: P.recordType, id: id)
                if case .found(let remote) = state { _ = try validatedRemote(remote.record, expectedID: id) }
                if case .unreadable(let version) = state, !version.identity.elementsEqual(id.utf8) {
                    throw CloudSyncPayloadError.inconsistentIdentity
                }
            } else {
                state = .missing
            }
        }
        try Task.checkCancellation()

        switch (state, base) {
        case (.missing, nil):
            guard let local else { return .upToDate(nil) }
            return try await write(local, expecting: nil, replacingAllFields: false, using: versioned)
        case (.missing, .some):
            return .remoteDeleted
        case let (.unreadable(version), base) where base == version:
            guard hasLocalChanges, let local else { return .remoteUnreadable(remoteVersion: version) }
            // Deliberate repair: full replacement so unreadable fields are removed.
            return try await write(local, expecting: version, replacingAllFields: true, using: versioned)
        case let (.unreadable(version), _):
            return .remoteUnreadable(remoteVersion: version)
        case let (.found(remote), base) where base == remote.version:
            guard hasLocalChanges, let local else { return .upToDate(remote.version) }
            // Overwriting a payload this version cannot decode is a repair: full replacement.
            let repair = try decodedOrNil(remote.record) == nil
            return try await write(local, expecting: remote.version, replacingAllFields: repair, using: versioned)
        case let (.found(remote), _):
            // A payload this app version cannot decode is unreadable, not fatal.
            guard let payload = try decodedOrNil(remote.record) else {
                return .remoteUnreadable(remoteVersion: remote.version)
            }
            if hasLocalChanges, local != nil {
                return .conflict(remote: payload, remoteVersion: remote.version)
            }
            return .adoptRemote(payload, remote.version)
        }
    }

    private func write(_ payload: P, expecting: SyncRecordVersion?, replacingAllFields: Bool,
                       using versioned: any VersionedCloudDatabase) async throws -> VersionedReconciliation<P> {
        let record = try outgoingRecord(payload)
        try Task.checkCancellation()
        do {
            return .pushed(try await versioned.save(record, expecting: expecting,
                                                    replacingAllFields: replacingAllFields))
        } catch CloudSyncConflictError.serverRecordChanged(let current?) {
            // Lost a race: report it; never retry or overwrite automatically.
            _ = try validatedRemote(current.record, expectedID: payload.id)
            guard let remote = try decodedOrNil(current.record) else {
                return .remoteUnreadable(remoteVersion: current.version)
            }
            return .conflict(remote: remote, remoteVersion: current.version)
        }
    }

    /// nil only for content this app version cannot decode; integrity errors
    /// (e.g. payload ID differs from record ID) stay fatal.
    private func decodedOrNil(_ record: SyncRecord) throws -> P? {
        do { return try decoded(record) }
        catch let integrity as CloudSyncPayloadError { throw integrity }
        catch { return nil }
    }
}
