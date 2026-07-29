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
#endif
