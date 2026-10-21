#if canImport(CloudKit)
import CloudKit
import Foundation

/// `CloudDatabase` backed by the user's **private** CloudKit database in a custom
/// zone. Writes each record's typed fields (its existing CloudKit schema) plus a
/// `modifiedAt` date; a whole-payload JSON is simply a `blob` field.
///
/// NOTE: this concrete adapter is intentionally NOT unit-tested (CI never hits
/// real iCloud). It must be verified on a real device once the container is
/// registered in the Apple Developer portal and the iCloud + CloudKit
/// entitlements are enabled.
///
/// The *contract* it implements is tested against `MockCloudDatabase` in
/// `LorisSyncTests` — token advance, deletion propagation, expired-token reset,
/// idempotent subscription, account gating. This file is the thin mapping layer
/// on top of that contract.
public struct CloudKitDatabase: CloudDatabase {
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let physicalDeletionPolicy: CloudSyncPhysicalDeletionPolicy
    private static let modifiedKey = "modifiedAt"

    public init(containerIdentifier: String, zoneName: String = "MelaProfilesZone",
                physicalDeletionPolicy: CloudSyncPhysicalDeletionPolicy = .disabled) {
        container = CKContainer(identifier: containerIdentifier)
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.physicalDeletionPolicy = physicalDeletionPolicy
    }

    private var database: CKDatabase { container.privateCloudDatabase }

    public func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available:               return .available
            case .noAccount:               return .noAccount
            case .restricted:              return .restricted
            case .temporarilyUnavailable:  return .temporarilyUnavailable
            default:                       return .unknown
            }
        } catch {
            return .unknown
        }
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await SyncWriteAcknowledgements.perform(
            saving: [zoneID], deleting: [], matchesIdentity: { $0 == $1.zoneID }
        ) {
            let result = try await database.modifyRecordZones(saving: [zone], deleting: [])
            return SyncMutationResult(saves: result.saveResults, deletions: result.deleteResults)
        }
    }

    private static func modifyRecords(
        in database: CKDatabase, saving records: [CKRecord], deleting ids: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged
    ) async throws -> [CKRecord.ID: CKRecord] {
        try await SyncWriteAcknowledgements.perform(
            saving: records.map(\.recordID), deleting: ids,
            matchesIdentity: { $0 == $1.recordID }
        ) {
            let result = try await database.modifyRecords(saving: records, deleting: ids,
                                                         savePolicy: savePolicy)
            return SyncMutationResult(saves: result.saveResults, deletions: result.deleteResults)
        }
    }

    public func save(_ records: [SyncRecord]) async throws {
        try Task.checkCancellation()
        guard !records.isEmpty else { return }
        try SyncRecordValidation.validate(records)
        let ckRecords = records.map { r -> CKRecord in
            let record = CKRecord(recordType: r.type, recordID: .init(recordName: r.id, zoneID: zoneID))
            r.apply(to: record, modifiedKey: Self.modifiedKey)
            return record
        }
        try SyncWriteAcknowledgements.validateRequest(saving: ckRecords.map(\.recordID),
                                                     deleting: [])
        try await ensureZone()
        _ = try await Self.modifyRecords(in: database, saving: ckRecords, deleting: [],
                                         savePolicy: .allKeys)
    }

    public func fetchAll(type: String) async throws -> [SyncRecord] {
        try SyncRecordValidation.validateType(type)
        try await ensureZone()
        return try await Self.fetchRecords(type: type, in: database, zoneID: zoneID)
    }

    private static func decodeRecord(_ record: CKRecord, type: String) throws -> SyncRecord {
        guard record.recordType == type,
              let mapped = SyncRecord(from: record, type: type, modifiedKey: modifiedKey) else {
            throw CloudSyncReadError.invalidRecord
        }
        return mapped
    }

    private static func fetchRecords(type: String, in database: CKDatabase,
                                     zoneID: CKRecordZone.ID) async throws -> [SyncRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let collected = try await SyncPageCollector.collect { (cursor: CKQueryOperation.Cursor?) in
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(matching: query, inZoneWith: zoneID)
            }
            return SyncResultPage(results: page.matchResults.map { _, result in
                result.flatMap { record in Result { try decodeRecord(record, type: type) } }
            }, continuation: page.queryCursor)
        }
        return collected.values
    }

    public func delete(ids: [String], type: String) async throws {
        try Task.checkCancellation()
        guard !ids.isEmpty else { return }
        try physicalDeletionPolicy.requirePermission() // Before native ID creation or any provider call.
        try SyncRecordValidation.validateType(type)
        try ids.forEach { try SyncRecordValidation.validateID($0) }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        try await SyncDeletionPreflight.perform(
            ids: recordIDs, type: type, policy: physicalDeletionPolicy,
            lookup: { try await database.record(for: $0) },
            matchesIdentity: { $0 == $1.recordID }, recordType: { $0.recordType },
            remove: { ids in
                _ = try await Self.modifyRecords(in: database, saving: [], deleting: ids)
            })
    }
}

// MARK: - Incremental sync

extension CloudKitDatabase: IncrementalCloudDatabase {

    /// Silent push on zone change. `shouldSendContentAvailable` keeps it invisible
    /// to the user. Repeated saves use the same identity; only an explicit
    /// successful result confirms registration (never a generic rejection).
    public func registerChangeSubscription(id: String) async throws {
        try SyncRecordValidation.validateID(id)
        try await ensureZone()
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await SyncWriteAcknowledgements.perform(
            saving: [id], deleting: [], matchesIdentity: { $0 == $1.subscriptionID }
        ) {
            let result = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            return SyncMutationResult(saves: result.saveResults, deletions: result.deleteResults)
        }
    }

    public func fetchChanges(type: String, since token: Data?) async throws -> ZoneChanges {
        try Task.checkCancellation()
        try SyncRecordValidation.validateType(type)
        // Present but corrupt bytes are not an implicit first fetch. Decode before
        // zone setup; no recovery/reset is authorized by a local archive failure.
        let checkpoint = try Self.decode(token)
        try Task.checkCancellation()
        try await ensureZone()
        do {
            return try await fetchDelta(type: type, since: checkpoint, wasReset: false)
        } catch let error as CKError where error.code == .changeTokenExpired {
            // The server no longer knows our token (too old, or the zone was
            // re-created). Anything less than a full refetch silently loses
            // records, so start over and tell the caller this is a snapshot.
            return try await fetchDelta(type: type, since: nil, wasReset: true)
        }
    }

    private func fetchDelta(type: String,
                            since token: CKServerChangeToken?,
                            wasReset: Bool) async throws -> ZoneChanges {
        let collected = try await SyncPageCollector.collect(startingAt: token) { cursor in
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: cursor)
            // Check every Result before filtering types. An error has no trustworthy
            // recordType and must not allow the zone-wide token to advance.
            let modifications = try result.modificationResultsByID.values.map { try $0.get().record }
            let changed = try modifications.filter { $0.recordType == type }.map {
                try Self.decodeRecord($0, type: type)
            }
            let deletions = result.deletions.filter { $0.recordType == type }.map(\.recordID.recordName)
            return SyncResultPage(
                results: [.success(ZoneChanges(changed: changed, deletedIDs: deletions))],
                continuation: result.moreComing ? result.changeToken : nil,
                checkpoint: result.changeToken)
        }
        guard let checkpoint = collected.checkpoint,
              let encoded = Self.encode(checkpoint) else {
            throw CloudSyncReadError.invalidCheckpoint
        }
        return try SyncZoneAccumulator.combine(collected.values, token: encoded, wasReset: wasReset)
    }

    // Tokens cross the protocol boundary as opaque `Data` so nothing above this
    // file needs to import CloudKit.
    private static func encode(_ token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token,
                                                 requiringSecureCoding: true)
    }

    // Internal seam: no container/account/network required for archive regressions.
    static func decode(_ data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        do {
            guard let checkpoint = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self, from: data
            ) else { throw CloudSyncReadError.invalidCheckpoint }
            return checkpoint
        } catch {
            // Preserve original bytes in the host; do not expose archive contents
            // through diagnostics or treat decode failure as provider expiry.
            throw CloudSyncReadError.invalidCheckpoint
        }
    }
}

// MARK: - Sharing

extension CloudKitDatabase: SharedCloudDatabase {

    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    static func isMissingRecord(_ error: any Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func lookupRecord(_ id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        let record = try await SyncShareResolution.optional(
            isMissing: { isMissingRecord($0) }
        ) { try await database.record(for: id) }
        if let record, record.recordID != id {
            throw CloudSyncSharingError.inconsistentMetadata
        }
        return record
    }

    private static func lookupRoot(_ id: CKRecord.ID, type: String,
                                   in database: CKDatabase) async throws -> CKRecord? {
        guard let root = try await lookupRecord(id, in: database) else { return nil }
        guard root.recordType == type else { throw CloudSyncSharingError.recordTypeMismatch }
        return root
    }

    private static func readShare(for root: CKRecord, in database: CKDatabase) async throws -> CKShare? {
        guard let reference = root.share else { return nil }
        guard reference.recordID.zoneID == root.recordID.zoneID,
              let record = try await lookupRecord(reference.recordID, in: database),
              let share = record as? CKShare, share.url != nil else {
            throw CloudSyncSharingError.inconsistentMetadata
        }
        return share
    }

    private static func participantRole(in share: CKShare) -> SyncShareRole {
        guard let participant = share.currentUserParticipant else { return .unknown }
        switch participant.role {
        case .owner: return .owner
        case .privateUser, .publicUser: return .participant
        default: return .unknown // New roles require an explicit compatibility decision.
        }
    }

    public func share(recordID: String,
                      type: String,
                      title: String?,
                      permission: SharePermission = .readWrite) async throws -> ShareInfo {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        guard let root = try await Self.lookupRoot(rootID, type: type, in: database) else {
            throw ShareError.recordNotFound
        }
        if let existing = try await Self.readShare(for: root, in: database) {
            try Self.requirePermission(existing.publicPermission, requested: permission)
            guard let url = existing.url else { throw ShareError.invalidShare }
            return ShareInfo(url: url, recordID: recordID,
                             isOwner: try SyncShareResolution.isOwner(role: Self.participantRole(in: existing)),
                             participantCount: existing.participants.count)
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue?
        share.publicPermission = permission == .readWrite ? .readWrite : .readOnly

        let confirmed = try await Self.modifyRecords(in: database, saving: [root, share], deleting: [])
        guard let savedShare = confirmed[share.recordID] as? CKShare,
              let url = savedShare.url else { throw ShareError.invalidShare }
        try Self.requirePermission(savedShare.publicPermission, requested: permission)
        guard try SyncShareResolution.isOwner(role: Self.participantRole(in: savedShare)) else {
            throw ShareError.notOwner
        }
        return ShareInfo(url: url,
                         recordID: recordID,
                         isOwner: true,
                         participantCount: savedShare.participants.count)
    }

    private static func requirePermission(_ permission: CKShare.ParticipantPermission,
                                          requested: SharePermission) throws {
        let effective: SharePermission?
        switch permission {
        case .readOnly: effective = .readOnly
        case .readWrite: effective = .readWrite
        default: effective = nil // none/unknown cannot satisfy a requested public grant.
        }
        try SyncShareResolution.requirePermission(effective, requested: requested)
    }

    public func existingShare(recordID: String, type: String) async throws -> ShareInfo? {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        guard let root = try await Self.lookupRoot(rootID, type: type, in: database),
              let share = try await Self.readShare(for: root, in: database) else { return nil }
        guard let url = share.url else { throw CloudSyncSharingError.inconsistentMetadata }
        return ShareInfo(url: url,
                         recordID: recordID,
                         isOwner: try SyncShareResolution.isOwner(role: Self.participantRole(in: share)),
                         participantCount: share.participants.count)
    }

    public func acceptShare(at url: URL) async throws {
        try Task.checkCancellation()
        let metadata = try await container.shareMetadata(for: url)
        try Task.checkCancellation()
        try await accept(metadata: metadata)
    }

    /// Accept from metadata handed over by the system (`userDidAcceptCloudKitShareWith`).
    /// This is the path iOS and macOS actually use when the user taps a share link;
    /// `acceptShare(at:)` exists for links the app resolves itself.
    public func accept(metadata: CKShare.Metadata) async throws {
        try Task.checkCancellation()
        // The provided metadata explicitly says no acceptance is needed.
        // alreadyShared describes sharing conflicts, not acceptance success.
        guard metadata.participantStatus != .accepted else { return }
        _ = try await SyncWriteAcknowledgements.perform(
            saving: [metadata], deleting: [],
            matchesIdentity: { $0.share.recordID == $1.recordID }
        ) {
            let result = try await container.accept([metadata])
            return SyncMutationResult(saves: result, deletions: [:])
        }
    }

    public func fetchShared(type: String) async throws -> [SyncRecord] {
        try SyncRecordValidation.validateType(type)
        // Shared records live in their owners' zones, so enumerate zones first —
        // there is no single zone to query.
        let zones = try await sharedDatabase.allRecordZones()
        var out: [SyncRecord] = []

        for zone in zones {
            let records = try await Self.fetchRecords(type: type, in: sharedDatabase, zoneID: zone.zoneID)
            out.append(contentsOf: records)
        }
        // This API cannot represent zone/owner-qualified IDs. Do not conflate them.
        try SyncShareResolution.ensureUniqueIDs(out.map(\.id))
        return out.sorted { $0.id < $1.id }
    }

    public func stopSharing(recordID: String, type: String) async throws {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        try await SyncShareResolution.removeUnique(
            privateRoot: { try await Self.lookupRoot(rootID, type: type, in: database) },
            sharedZones: { try await sharedDatabase.allRecordZones().map(\.zoneID) },
            sharedRoot: { zone in
                try await Self.lookupRoot(CKRecord.ID(recordName: recordID, zoneID: zone),
                                          type: type, in: sharedDatabase)
            },
            remove: { candidate in
                let target = candidate.scope == .privateDatabase ? database : sharedDatabase
                guard let share = try await Self.readShare(for: candidate.root, in: target) else {
                    throw ShareError.recordNotFound
                }
                try SyncShareResolution.requireRemovalRole(
                    scope: candidate.scope, role: Self.participantRole(in: share),
                    accepted: share.currentUserParticipant?.acceptanceStatus == .accepted)
                _ = try await Self.modifyRecords(in: target, saving: [], deleting: [share.recordID])
            })
    }
}
#endif
