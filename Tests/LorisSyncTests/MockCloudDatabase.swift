import Foundation
@testable import LorisSync

/// In-memory `IncrementalCloudDatabase` for tests. CI never touches real iCloud,
/// so every behaviour worth asserting is asserted here.
///
/// Models the two server behaviours that matter and are easy to get wrong:
/// tokens advance monotonically, and a token the server no longer recognises
/// forces a full snapshot rather than a silent partial answer.
actor MockCloudDatabase: IncrementalCloudDatabase, SharedCloudDatabase, VersionedCloudDatabase {

    // MARK: State

    private var records: [String: SyncRecord] = [:]
    /// Ids deleted since the beginning, in deletion order.
    private var tombstones: [String] = []
    /// Monotonic clock standing in for a CKServerChangeToken.
    private var version = 0
    /// Version at or below which the server has forgotten history.
    private var expiredBefore = 0

    private(set) var status: SyncAccountStatus = .available
    private(set) var registeredSubscriptionIDs: [String] = []
    /// Version each record was last written at.
    private var writeVersion: [String: Int] = [:]

    // MARK: Test hooks

    func setStatus(_ s: SyncAccountStatus) { status = s }

    /// Simulate a server that has aged out every token issued so far — the
    /// `changeTokenExpired` path.
    func expireAllTokens() { expiredBefore = version }

    func seed(_ records: [SyncRecord]) {
        for r in records { put(r) }
    }

    private func put(_ r: SyncRecord) {
        version += 1
        records[r.id] = r
        writeVersion[r.id] = version
    }

    // MARK: CloudDatabase

    func accountStatus() async -> SyncAccountStatus { status }

    func save(_ newRecords: [SyncRecord]) async throws {
        guard status == .available else { throw SyncError.accountUnavailable }
        for r in newRecords { put(r) }
    }

    func fetchAll(type: String) async throws -> [SyncRecord] {
        guard status == .available else { throw SyncError.accountUnavailable }
        return records.values.filter { $0.type == type }.sorted { $0.id < $1.id }
    }

    func delete(ids: [String], type: String) async throws {
        guard status == .available else { throw SyncError.accountUnavailable }
        for id in ids where records[id] != nil {
            version += 1
            records.removeValue(forKey: id)
            writeVersion.removeValue(forKey: id)
            tombstones.append(id)
        }
    }

    // MARK: VersionedCloudDatabase (server compare-and-set)

    /// IDs whose server content this "app version" cannot read.
    private var unreadableIDs: Set<String> = []
    func markUnreadable(_ id: String) { unreadableIDs.insert(id) }

    func serverVersion(of id: String) -> SyncRecordVersion? {
        writeVersion[id].map {
            let tag = Data("v\($0)".utf8)
            return SyncRecordVersion(identity: Data(id.utf8), tag: tag, token: tag, serverModifiedAt: nil)
        }
    }

    func fetchVersioned(type: String) async throws -> [VersionedSyncRecord] {
        guard status == .available else { throw SyncError.accountUnavailable }
        let matching = records.values.filter { $0.type == type }
        guard matching.allSatisfy({ !unreadableIDs.contains($0.id) }) else { throw CloudSyncReadError.invalidRecord }
        return matching.sorted { $0.id < $1.id }.map {
            VersionedSyncRecord(record: $0, version: serverVersion(of: $0.id)!)
        }
    }

    func discoverVersionedIDs(type: String) async throws -> [String] {
        guard status == .available else { throw SyncError.accountUnavailable }
        return records.values.filter { $0.type == type }.map(\.id).sorted()
    }

    func fetchVersioned(type: String, id: String) async throws -> VersionedLookup {
        guard status == .available else { throw SyncError.accountUnavailable }
        guard let record = records[id] else { return .missing }
        guard record.type == type else { throw CloudSyncReadError.invalidRecord }
        if unreadableIDs.contains(id) { return .unreadable(serverVersion(of: id)!) }
        return .found(VersionedSyncRecord(record: record, version: serverVersion(of: id)!))
    }

    func save(_ record: SyncRecord, expecting expected: SyncRecordVersion?,
              replacingAllFields: Bool) async throws -> SyncRecordVersion {
        guard status == .available else { throw SyncError.accountUnavailable }
        if let existing = records[record.id], existing.type != record.type { throw CloudSyncValidationError.invalidRecord }
        guard serverVersion(of: record.id) == expected else {
            let current = records[record.id].flatMap { existing -> VersionedSyncRecord? in
                unreadableIDs.contains(existing.id) ? nil
                    : VersionedSyncRecord(record: existing, version: serverVersion(of: existing.id)!)
            }
            throw CloudSyncConflictError.serverRecordChanged(current: current)
        }
        // Like the native adapter: provided fields replace; unknown fields stay
        // unless this is a full replacement. Unreadable content only goes away
        // with a full replacement (mirrors unsupported native fields).
        var merged = record
        if let existing = records[record.id], !replacingAllFields {
            merged.fields = existing.fields.merging(record.fields) { _, new in new }
        }
        if replacingAllFields { unreadableIDs.remove(record.id) }
        put(merged)
        return serverVersion(of: record.id)!
    }

    // MARK: IncrementalCloudDatabase

    func registerChangeSubscription(id: String) async throws {
        guard status == .available else { throw SyncError.accountUnavailable }
        // Idempotent, like CloudKit: registering twice must not duplicate.
        if !registeredSubscriptionIDs.contains(id) {
            registeredSubscriptionIDs.append(id)
        }
    }

    func fetchChanges(type: String, since token: Data?) async throws -> ZoneChanges {
        guard status == .available else { throw SyncError.accountUnavailable }

        let since = Self.decode(token)
        // Server forgot this token → full snapshot, flagged.
        let reset = since != nil && since! <= expiredBefore

        let from = reset ? 0 : (since ?? 0)
        let changed = records.values
            .filter { $0.type == type && (writeVersion[$0.id] ?? 0) > from }
            .sorted { $0.id < $1.id }

        // A reset carries no deletions: the snapshot *is* the truth.
        let deleted = reset ? [] : tombstones

        return ZoneChanges(changed: changed,
                           deletedIDs: deleted,
                           token: Self.encode(version),
                           wasReset: reset)
    }

    // MARK: SharedCloudDatabase

    /// Records this user participates in. Deliberately a *separate* store from
    /// `records`: CloudKit keeps shared data in another database, and a mock that
    /// merged them would hide the bug it exists to catch.
    private var sharedRecords: [String: SyncRecord] = [:]
    private var shares: [String: ShareInfo] = [:]
    private(set) var acceptedShareURLs: [URL] = []

    /// Simulate another user having shared a record with us.
    func receiveShare(_ record: SyncRecord, from url: URL) {
        sharedRecords[record.id] = record
        shares[record.id] = ShareInfo(url: url,
                                      recordID: record.id,
                                      isOwner: false,
                                      participantCount: 2)
    }

    private var shareAccess: [String: ShareAccess] = [:]
    func access(of recordID: String) -> ShareAccess? { shareAccess[recordID] }

    func share(recordID: String,
               type: String,
               title: String?,
               access: ShareAccess) async throws -> ShareInfo {
        guard status == .available else { throw SyncError.accountUnavailable }
        if let existing = shares[recordID] {
            guard existing.isOwner else { throw ShareError.notOwner } // like ensureShare
            try SyncShareResolution.requireAccess(shareAccess[recordID], requested: access)
            return existing
        }
        guard records[recordID] != nil else { throw ShareError.recordNotFound }

        let info = ShareInfo(url: URL(string: "https://www.icloud.com/share/\(recordID)")!,
                             recordID: recordID,
                             isOwner: true,
                             participantCount: 1)
        shares[recordID] = info
        shareAccess[recordID] = access
        return info
    }

    func existingShare(recordID: String, type: String) async throws -> ShareInfo? {
        shares[recordID]
    }

    func acceptShare(at url: URL) async throws {
        guard status == .available else { throw SyncError.accountUnavailable }
        guard url.absoluteString.contains("/share/") else { throw ShareError.invalidShare }
        if !acceptedShareURLs.contains(url) { acceptedShareURLs.append(url) }
    }

    func fetchShared(type: String) async throws -> [SyncRecord] {
        guard status == .available else { throw SyncError.accountUnavailable }
        return sharedRecords.values.filter { $0.type == type }.sorted { $0.id < $1.id }
    }

    func fetchSharedReport(type: String) async throws -> SyncReadReport {
        SyncReadReport(records: try await fetchShared(type: type), quarantined: [])
    }

    func stopSharing(recordID: String, type: String) async throws {
        guard let info = shares[recordID] else { throw ShareError.recordNotFound }
        shares.removeValue(forKey: recordID)
        // A participant leaving loses access; an owner keeps the record.
        if !info.isOwner { sharedRecords.removeValue(forKey: recordID) }
    }

    func revokeOwnedShare(recordID: String, type: String) async throws {
        guard let info = shares[recordID], info.isOwner else { throw ShareError.recordNotFound }
        shares.removeValue(forKey: recordID)
        shareAccess.removeValue(forKey: recordID)
    }

    func updateShareAccess(recordID: String, type: String, access: ShareAccess) async throws -> ShareInfo {
        guard status == .available else { throw SyncError.accountUnavailable }
        guard let info = shares[recordID] else { throw ShareError.recordNotFound }
        guard info.isOwner else { throw ShareError.notOwner }
        shareAccess[recordID] = access
        return info
    }

    func leaveShare(recordID: String, type: String) async throws {
        guard let info = shares[recordID], !info.isOwner else { throw ShareError.recordNotFound }
        shares.removeValue(forKey: recordID)
        sharedRecords.removeValue(forKey: recordID)
    }

    // MARK: Token codec (an Int, encoded opaquely like the real one)

    private static func encode(_ v: Int) -> Data { withUnsafeBytes(of: v) { Data($0) } }

    private static func decode(_ d: Data?) -> Int? {
        guard let d, d.count == MemoryLayout<Int>.size else { return nil }
        return d.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }
}
