#if canImport(CloudKit)
import CloudKit
import Foundation

/// `CloudDatabase` backed by the user's **private** CloudKit database in a custom
/// zone. Stores each payload as a JSON `blob` + a `modifiedAt` date.
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
    private static let blobKey = "blob"
    private static let modifiedKey = "modifiedAt"

    public init(containerIdentifier: String, zoneName: String = "MelaProfilesZone") {
        container = CKContainer(identifier: containerIdentifier)
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
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

    private func ensureZone() async {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try? await database.modifyRecordZones(saving: [zone], deleting: [])
    }

    public func save(_ records: [SyncRecord]) async throws {
        await ensureZone()
        let ckRecords = records.map { r -> CKRecord in
            let record = CKRecord(recordType: r.type, recordID: .init(recordName: r.id, zoneID: zoneID))
            record[Self.blobKey] = r.blob as CKRecordValue
            record[Self.modifiedKey] = r.modifiedAt as CKRecordValue
            return record
        }
        _ = try await database.modifyRecords(saving: ckRecords, deleting: [], savePolicy: .allKeys)
    }

    public func fetchAll(type: String) async throws -> [SyncRecord] {
        await ensureZone()
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        return matches.compactMap { _, result in
            guard case .success(let record) = result,
                  let blob = record[Self.blobKey] as? Data,
                  let modified = record[Self.modifiedKey] as? Date else { return nil }
            return SyncRecord(id: record.recordID.recordName, type: type, blob: blob, modifiedAt: modified)
        }
    }

    public func delete(ids: [String], type: String) async throws {
        let recordIDs = ids.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
    }
}

// MARK: - Incremental sync

extension CloudKitDatabase: IncrementalCloudDatabase {

    /// Silent push on zone change. `shouldSendContentAvailable` keeps it invisible
    /// to the user; saving an existing subscription id is a no-op server-side, so
    /// calling this at every launch is safe.
    public func registerChangeSubscription(id: String) async throws {
        await ensureZone()
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already registered — CloudKit rejects the duplicate rather than
            // treating it as an update.
            return
        }
    }

    public func fetchChanges(type: String, since token: Data?) async throws -> ZoneChanges {
        await ensureZone()
        do {
            return try await fetchDelta(type: type, since: Self.decode(token), wasReset: false)
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
        let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)

        let modifications = result.modificationResultsByID.values.compactMap { r -> CKRecord? in
            guard case .success(let modification) = r else { return nil }
            return modification.record
        }
        let deletions = result.deletions.map(\.recordID.recordName)
        let newToken = result.changeToken

        let changed = modifications.compactMap { record -> SyncRecord? in
            guard record.recordType == type,
                  let blob = record[Self.blobKey] as? Data,
                  let modified = record[Self.modifiedKey] as? Date else { return nil }
            return SyncRecord(id: record.recordID.recordName,
                              type: type,
                              blob: blob,
                              modifiedAt: modified)
        }

        return ZoneChanges(changed: changed,
                           deletedIDs: deletions,
                           token: Self.encode(newToken),
                           wasReset: wasReset)
    }

    // Tokens cross the protocol boundary as opaque `Data` so nothing above this
    // file needs to import CloudKit.
    private static func encode(_ token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token,
                                                 requiringSecureCoding: true)
    }

    private static func decode(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self,
                                                       from: data)
    }
}

// MARK: - Sharing

extension CloudKitDatabase: SharedCloudDatabase {

    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    public func share(recordID: String,
                      type: String,
                      title: String?,
                      permission: SharePermission = .readWrite) async throws -> ShareInfo {
        // CloudKit refuses a second share on the same record, so reuse silently
        // rather than making every caller check first.
        if let existing = try await existingShare(recordID: recordID, type: type) {
            return existing
        }

        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        guard let root = try? await database.record(for: rootID) else {
            throw ShareError.recordNotFound
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue?
        share.publicPermission = permission == .readWrite ? .readWrite : .readOnly

        _ = try await database.modifyRecords(saving: [root, share], deleting: [])

        guard let url = share.url else { throw ShareError.invalidShare }
        return ShareInfo(url: url,
                         recordID: recordID,
                         isOwner: true,
                         participantCount: share.participants.count)
    }

    public func existingShare(recordID: String, type: String) async throws -> ShareInfo? {
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)
        guard let root = try? await database.record(for: rootID),
              let shareRef = root.share else { return nil }
        guard let share = try? await database.record(for: shareRef.recordID) as? CKShare,
              let url = share.url else { return nil }

        return ShareInfo(url: url,
                         recordID: recordID,
                         isOwner: share.owner.userIdentity.userRecordID == share.currentUserParticipant?.userIdentity.userRecordID,
                         participantCount: share.participants.count)
    }

    public func acceptShare(at url: URL) async throws {
        let metadata: CKShare.Metadata
        do {
            metadata = try await container.shareMetadata(for: url)
        } catch {
            throw ShareError.invalidShare
        }
        try await accept(metadata: metadata)
    }

    /// Accept from metadata handed over by the system (`userDidAcceptCloudKitShareWith`).
    /// This is the path iOS and macOS actually use when the user taps a share link;
    /// `acceptShare(at:)` exists for links the app resolves itself.
    public func accept(metadata: CKShare.Metadata) async throws {
        // Already a participant: CloudKit reports .alreadyShared, which is a
        // success from the user's point of view.
        do {
            _ = try await container.accept([metadata])
        } catch let error as CKError where error.code == .alreadyShared {
            return
        }
    }

    public func fetchShared(type: String) async throws -> [SyncRecord] {
        // Shared records live in their owners' zones, so enumerate zones first —
        // there is no single zone to query.
        let zones = try await sharedDatabase.allRecordZones()
        var out: [SyncRecord] = []

        for zone in zones {
            let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            guard let (matches, _) = try? await sharedDatabase.records(matching: query,
                                                                       inZoneWith: zone.zoneID)
            else { continue }
            for (_, result) in matches {
                guard case .success(let record) = result,
                      let blob = record[Self.blobKey] as? Data,
                      let modified = record[Self.modifiedKey] as? Date else { continue }
                out.append(SyncRecord(id: record.recordID.recordName,
                                      type: type,
                                      blob: blob,
                                      modifiedAt: modified))
            }
        }
        return out.sorted { $0.id < $1.id }
    }

    public func stopSharing(recordID: String, type: String) async throws {
        let rootID = CKRecord.ID(recordName: recordID, zoneID: zoneID)

        // Owner: delete the CKShare, which revokes access for everyone.
        if let root = try? await database.record(for: rootID), let shareRef = root.share {
            _ = try await database.modifyRecords(saving: [], deleting: [shareRef.recordID])
            return
        }

        // Participant: the record is not in our private database. Leaving means
        // deleting the share from the *shared* database.
        let zones = try await sharedDatabase.allRecordZones()
        for zone in zones {
            let id = CKRecord.ID(recordName: recordID, zoneID: zone.zoneID)
            guard let record = try? await sharedDatabase.record(for: id),
                  let shareRef = record.share else { continue }
            _ = try await sharedDatabase.modifyRecords(saving: [], deleting: [shareRef.recordID])
            return
        }
        throw ShareError.recordNotFound
    }
}
#endif
