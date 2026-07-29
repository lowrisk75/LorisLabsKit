import Foundation
@testable import LorisSync

/// In-memory `IncrementalCloudDatabase` for tests. CI never touches real iCloud,
/// so every behaviour worth asserting is asserted here.
///
/// Models the two server behaviours that matter and are easy to get wrong:
/// tokens advance monotonically, and a token the server no longer recognises
/// forces a full snapshot rather than a silent partial answer.
actor MockCloudDatabase: IncrementalCloudDatabase {

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

    // MARK: Token codec (an Int, encoded opaquely like the real one)

    private static func encode(_ v: Int) -> Data { withUnsafeBytes(of: v) { Data($0) } }

    private static func decode(_ d: Data?) -> Int? {
        guard let d, d.count == MemoryLayout<Int>.size else { return nil }
        return d.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    }
}
