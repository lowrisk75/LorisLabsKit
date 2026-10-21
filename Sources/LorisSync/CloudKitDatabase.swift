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
    private let readPolicy: CloudSyncReadPolicy
    private static let modifiedKey = "modifiedAt"

    public init(containerIdentifier: String, zoneName: String = "MelaProfilesZone",
                physicalDeletionPolicy: CloudSyncPhysicalDeletionPolicy = .disabled,
                readPolicy: CloudSyncReadPolicy = .quarantineUnreadable) {
        container = CKContainer(identifier: containerIdentifier)
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.physicalDeletionPolicy = physicalDeletionPolicy
        self.readPolicy = readPolicy
    }

    /// Strict mapping, or a quarantine entry under `.quarantineUnreadable`.
    /// Only content-mapping failures are quarantined; transport/permission
    /// errors always fail the read.
    enum MappedRecord: Sendable {
        case record(SyncRecord)
        case quarantined(QuarantinedRecord)
    }

    static func mapOrQuarantine(_ record: CKRecord, type: String,
                                policy: CloudSyncReadPolicy) throws -> MappedRecord {
        do {
            return .record(try decodeRecord(record, type: type))
        } catch CloudSyncReadError.invalidRecord where policy == .quarantineUnreadable
                    && record.recordType.utf8.elementsEqual(type.utf8) {
            return .quarantined(QuarantinedRecord(id: record.recordID.recordName, reason: .unsupportedContent))
        }
    }

    static func split(_ mapped: [MappedRecord]) -> SyncReadReport {
        var records: [SyncRecord] = [], quarantined: [QuarantinedRecord] = []
        for item in mapped {
            switch item {
            case .record(let record): records.append(record)
            case .quarantined(let entry): quarantined.append(entry)
            }
        }
        return SyncReadReport(records: records, quarantined: quarantined)
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
        guard record.recordType.utf8.elementsEqual(type.utf8),
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
            let mapped = Self.split(try modifications.filter { $0.recordType.utf8.elementsEqual(type.utf8) }.map {
                try Self.mapOrQuarantine($0, type: type, policy: readPolicy)
            })
            let deletions = result.deletions.filter { $0.recordType.utf8.elementsEqual(type.utf8) }
                .map(\.recordID.recordName)
            return SyncResultPage(
                results: [.success(ZoneChanges(changed: mapped.records, deletedIDs: deletions,
                                               quarantined: mapped.quarantined))],
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
        guard root.recordType.utf8.elementsEqual(type.utf8) else { throw CloudSyncSharingError.recordTypeMismatch }
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
        default:
            // OS 26 administrators are non-owner participants who may invite others.
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *),
               participant.role == .administrator {
                return .participant
            }
            return .unknown // Other new roles require an explicit compatibility decision.
        }
    }

    public func share(recordID: String,
                      type: String,
                      title: String?,
                      access: ShareAccess) async throws -> ShareInfo {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        let share = try await Self.ensureShare(rootID: rootID, type: type, title: title,
                                               access: access, in: database)
        guard let url = share.url else { throw ShareError.invalidShare }
        return ShareInfo(url: url, recordID: recordID,
                         isOwner: try SyncShareResolution.isOwner(role: Self.participantRole(in: share)),
                         participantCount: share.participants.count)
    }

    /// Existing owned share with the requested access, or a newly saved one.
    /// Access and ownership are verified on the acknowledged share.
    static func ensureShare(rootID: CKRecord.ID, type: String, title: String?,
                            access: ShareAccess, in database: CKDatabase) async throws -> CKShare {
        guard let root = try await lookupRoot(rootID, type: type, in: database) else {
            throw ShareError.recordNotFound
        }
        if let existing = try await readShare(for: root, in: database) {
            try SyncShareResolution.requireAccess(effectiveAccess(existing.publicPermission), requested: access)
            guard try SyncShareResolution.isOwner(role: participantRole(in: existing)) else {
                throw ShareError.notOwner
            }
            return existing
        }
        let share = makeShare(root: root, title: title, access: access)
        let confirmed = try await modifyRecords(in: database, saving: [root, share], deleting: [])
        guard let savedShare = confirmed[share.recordID] as? CKShare,
              savedShare.url != nil else { throw ShareError.invalidShare }
        try SyncShareResolution.requireAccess(effectiveAccess(savedShare.publicPermission), requested: access)
        guard try SyncShareResolution.isOwner(role: participantRole(in: savedShare)) else {
            throw ShareError.notOwner
        }
        return savedShare
    }

    static func makeShare(root: CKRecord, title: String?, access: ShareAccess) -> CKShare {
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue?
        apply(access, to: share)
        return share
    }

    static func apply(_ access: ShareAccess, to share: CKShare) {
        switch access {
        case .invitedOnly: share.publicPermission = .none
        case .anyoneWithLink(.readOnly): share.publicPermission = .readOnly
        case .anyoneWithLink(.readWrite): share.publicPermission = .readWrite
        }
    }

    /// Owner: change who may join an existing share (e.g. migrate a legacy
    /// public link to `.invitedOnly`) without revoking it. Compare-and-set on
    /// the share; the acknowledged access is verified. CloudKit decides what
    /// happens to people who already joined through the link (not verified here).
    public func updateShareAccess(recordID: String, type: String,
                                  access: ShareAccess) async throws -> ShareInfo {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        guard let root = try await Self.lookupRoot(rootID, type: type, in: database),
              let share = try await Self.readShare(for: root, in: database) else {
            throw ShareError.recordNotFound
        }
        guard try SyncShareResolution.isOwner(role: Self.participantRole(in: share)) else {
            throw ShareError.notOwner
        }
        var current = share
        if Self.effectiveAccess(share.publicPermission) != access {
            Self.apply(access, to: share)
            let confirmed = try await Self.modifyRecords(in: database, saving: [share], deleting: [],
                                                         savePolicy: .ifServerRecordUnchanged)
            guard let saved = confirmed[share.recordID] as? CKShare else { throw ShareError.invalidShare }
            current = saved
        }
        try SyncShareResolution.requireAccess(Self.effectiveAccess(current.publicPermission), requested: access)
        guard let url = current.url else { throw ShareError.invalidShare }
        return ShareInfo(url: url, recordID: recordID, isOwner: true,
                         participantCount: current.participants.count)
    }

    static func effectiveAccess(_ permission: CKShare.ParticipantPermission) -> ShareAccess? {
        switch permission {
        case .none: return .invitedOnly
        case .readOnly: return .anyoneWithLink(.readOnly)
        case .readWrite: return .anyoneWithLink(.readWrite)
        default: return nil // unknown never satisfies a request.
        }
    }

    /// Validated existing owned share, `nil` when the root has none yet.
    static func existingOwnedShare(rootID: CKRecord.ID, type: String, access: ShareAccess,
                                   in database: CKDatabase) async throws -> CKShare? {
        guard let root = try await lookupRoot(rootID, type: type, in: database) else {
            throw ShareError.recordNotFound
        }
        guard let existing = try await readShare(for: root, in: database) else { return nil }
        try SyncShareResolution.requireAccess(effectiveAccess(existing.publicPermission), requested: access)
        guard try SyncShareResolution.isOwner(role: participantRole(in: existing)) else {
            throw ShareError.notOwner
        }
        return existing
    }

    var shareContainer: CKContainer { container }
    var shareZoneID: CKRecordZone.ID { zoneID }
    var sharePrivateDatabase: CKDatabase { database }

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
        // Byte identity: canonically equivalent but distinct IDs are not one record.
        try SyncShareResolution.ensureUniqueIDs(out.map { Data($0.id.utf8) })
        return out.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }
    }

    public func fetchSharedReport(type: String) async throws -> SyncReadReport {
        try SyncRecordValidation.validateType(type)
        let zones = try await sharedDatabase.allRecordZones()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let database = sharedDatabase, policy = readPolicy
        var mapped: [MappedRecord] = []
        for zone in zones {
            let zoneID = zone.zoneID
            let collected = try await SyncPageCollector.collect { (cursor: CKQueryOperation.Cursor?) in
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                           queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor)
                } else {
                    page = try await database.records(matching: query, inZoneWith: zoneID)
                }
                return SyncResultPage(results: page.matchResults.map { _, result in
                    result.flatMap { record in Result { try Self.mapOrQuarantine(record, type: type, policy: policy) } }
                }, continuation: page.queryCursor)
            }
            mapped.append(contentsOf: collected.values)
        }
        let report = Self.split(mapped)
        try SyncShareResolution.ensureUniqueIDs(
            (report.records.map(\.id) + report.quarantined.map(\.id)).map { Data($0.utf8) })
        return SyncReadReport(
            records: report.records.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) },
            quarantined: report.quarantined.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) })
    }

    /// Legacy string-only API: refuses (`ambiguousRecord`) when the name exists both
    /// privately and in a shared zone. Prefer `revokeOwnedShare` / `leaveShare`.
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
            remove: removeShare)
    }

    /// Owner: revoke the share of a record in this database's private zone for
    /// everyone. Never looks at shared zones, so a colliding name a participant
    /// planted there cannot block revocation. Throws `notOwner` otherwise.
    public func revokeOwnedShare(recordID: String, type: String) async throws {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        try await SyncShareResolution.removeOwned(
            privateRoot: { try await Self.lookupRoot(rootID, type: type, in: database) },
            remove: removeShare)
    }

    /// Participant: leave a share accepted from someone else. Never touches the
    /// caller's own private records. Same-name roots in several shared zones
    /// still fail closed with `ambiguousRecord`.
    public func leaveShare(recordID: String, type: String) async throws {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        try await SyncShareResolution.removeParticipating(
            sharedZones: { try await sharedDatabase.allRecordZones().map(\.zoneID) },
            sharedRoot: { zone in
                try await Self.lookupRoot(CKRecord.ID(recordName: recordID, zoneID: zone),
                                          type: type, in: sharedDatabase)
            },
            remove: removeShare)
    }

    private var removeShare: @Sendable (SyncShareCandidate<CKRecord>) async throws -> Void {
        { [database, sharedDatabase] candidate in
            let target = candidate.scope == .privateDatabase ? database : sharedDatabase
            guard let share = try await Self.readShare(for: candidate.root, in: target) else {
                throw ShareError.recordNotFound
            }
            try SyncShareResolution.requireRemovalRole(
                scope: candidate.scope, role: Self.participantRole(in: share),
                accepted: share.currentUserParticipant?.acceptanceStatus == .accepted)
            _ = try await Self.modifyRecords(in: target, saving: [], deleting: [share.recordID])
        }
    }
}

// MARK: - Server compare-and-set

extension CloudKitDatabase: VersionedCloudDatabase {
    public func discoverVersionedIDs(type: String) async throws -> [String] {
        try SyncRecordValidation.validateType(type)
        try await ensureZone()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let zoneID = zoneID, database = database
        // System fields only: content this version cannot map cannot block discovery.
        let collected = try await SyncPageCollector.collect { (cursor: CKQueryOperation.Cursor?) in
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [])
            } else {
                page = try await database.records(matching: query, inZoneWith: zoneID, desiredKeys: [])
            }
            return SyncResultPage(results: page.matchResults.map { _, result in
                result.flatMap { record in
                    Result {
                        guard record.recordType.utf8.elementsEqual(type.utf8) else {
                            throw CloudSyncReadError.invalidRecord
                        }
                        return record.recordID.recordName
                    }
                }
            }, continuation: page.queryCursor)
        }
        try SyncShareResolution.ensureUniqueIDs(collected.values.map { Data($0.utf8) })
        return collected.values
    }

    public func fetchVersioned(type: String, id: String) async throws -> VersionedLookup {
        try SyncRecordValidation.validateType(type)
        try SyncRecordValidation.validateID(id)
        try Task.checkCancellation()
        try await ensureZone()
        // Fetch by ID is strongly consistent, unlike index-backed queries.
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        guard let native = try await Self.lookupRecord(recordID, in: database) else { return .missing }
        guard native.recordType.utf8.elementsEqual(type.utf8) else { throw CloudSyncReadError.invalidRecord }
        let version = try Self.version(of: native)
        switch try Self.mapOrQuarantine(native, type: type, policy: .quarantineUnreadable) {
        case .record(let record): return .found(VersionedSyncRecord(record: record, version: version))
        case .quarantined: return .unreadable(version)
        }
    }

    public func fetchVersioned(type: String) async throws -> [VersionedSyncRecord] {
        try SyncRecordValidation.validateType(type)
        try await ensureZone()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let zoneID = zoneID, database = database
        let collected = try await SyncPageCollector.collect { (cursor: CKQueryOperation.Cursor?) in
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(matching: query, inZoneWith: zoneID)
            }
            return SyncResultPage(results: page.matchResults.map { _, result in
                result.flatMap { record in Result { try Self.versioned(record, type: type) } }
            }, continuation: page.queryCursor)
        }
        try SyncShareResolution.ensureUniqueIDs(collected.values.map { Data($0.record.id.utf8) })
        return collected.values
    }

    public func save(_ record: SyncRecord, expecting version: SyncRecordVersion?,
                     replacingAllFields: Bool) async throws -> SyncRecordVersion {
        try Task.checkCancellation()
        try SyncRecordValidation.validate([record])
        let recordID = CKRecord.ID(recordName: record.id, zoneID: zoneID)
        let native: CKRecord
        if let version {
            guard version.identity.elementsEqual(record.id.utf8) else { throw CloudSyncValidationError.invalidRecord }
            let base = try Self.decodeVersion(version)
            guard base.recordID == recordID,
                  base.recordType.utf8.elementsEqual(record.type.utf8) else {
                throw CloudSyncValidationError.invalidRecord
            }
            if replacingAllFields {
                // Full replacement needs the server's key set: read the record and
                // require it to still be exactly the expected version.
                try await ensureZone()
                guard let server = try await Self.lookupRecord(recordID, in: database) else {
                    throw CloudSyncConflictError.serverRecordChanged(current: nil)
                }
                guard let tag = server.recordChangeTag, Data(tag.utf8) == version.tag else {
                    throw CloudSyncConflictError.serverRecordChanged(
                        current: try? Self.versioned(server, type: record.type))
                }
                for key in server.allKeys() where key != Self.modifiedKey && record.fields[key] == nil {
                    server[key] = nil
                }
                native = server
            } else {
                // Only provided fields are sent; unknown server fields are preserved.
                native = base
            }
        } else {
            native = CKRecord(recordType: record.type, recordID: recordID)
        }
        record.apply(to: native, modifiedKey: Self.modifiedKey)
        try await ensureZone()
        do {
            let confirmed = try await Self.modifyRecords(in: database, saving: [native], deleting: [],
                                                         savePolicy: .ifServerRecordUnchanged)
            guard let saved = confirmed[recordID] else { throw CloudSyncWriteError.incompleteAcknowledgement }
            return try Self.version(of: saved)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Unreadable server copies are reported without content, never guessed.
            let current = error.serverRecord.flatMap { try? Self.versioned($0, type: record.type) }
            throw CloudSyncConflictError.serverRecordChanged(current: current)
        }
    }

    static func versioned(_ record: CKRecord, type: String) throws -> VersionedSyncRecord {
        VersionedSyncRecord(record: try decodeRecord(record, type: type), version: try version(of: record))
    }

    static func version(of record: CKRecord) throws -> SyncRecordVersion {
        // Compare-and-set does not support hierarchies: refuse at read time so a
        // record is never "found" and then impossible to save.
        guard record.parent == nil else { throw CloudSyncValidationError.invalidRecord }
        guard let tag = record.recordChangeTag, !tag.isEmpty,
              tag.utf8.count <= SyncRecordVersion.maximumTagBytes else { throw CloudSyncReadError.invalidRecord }
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        let token = coder.encodedData
        guard !token.isEmpty, token.count <= SyncRecordVersion.maximumTokenBytes else {
            throw CloudSyncReadError.invalidRecord
        }
        return SyncRecordVersion(identity: Data(record.recordID.recordName.utf8), tag: Data(tag.utf8),
                                 token: token, serverModifiedAt: record.modificationDate)
    }

    /// Rebuilds the system-fields record. A stored version is host data: it must
    /// live in protected storage. Decoding uses secure coding; the result must
    /// match the version's identity and tag and carry no parent reference (this
    /// adapter never writes hierarchies, so a parent would be injected).
    static func decodeVersion(_ version: SyncRecordVersion) throws -> CKRecord {
        guard version.token.count <= SyncRecordVersion.maximumTokenBytes,
              let coder = try? NSKeyedUnarchiver(forReadingFrom: version.token) else {
            throw CloudSyncReadError.invalidRecord
        }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        guard let record = CKRecord(coder: coder),
              let tag = record.recordChangeTag, Data(tag.utf8) == version.tag,
              record.recordID.recordName.utf8.elementsEqual(version.identity),
              record.parent == nil else {
            throw CloudSyncReadError.invalidRecord
        }
        return record
    }
}
#endif
