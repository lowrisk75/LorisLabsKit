#if canImport(CloudKit)
import CloudKit
import Foundation

/// `CloudDatabase` backed by the user's **private** CloudKit database in a custom
/// zone. Stores each payload as a JSON `blob` + a `modifiedAt` date.
///
/// NOTE: this concrete adapter is intentionally NOT unit-tested (CI never hits
/// real iCloud). It must be verified on a real device once the container
/// `iCloud.com.lorislab.mela` is registered in the Apple Developer portal and
/// the iCloud + CloudKit entitlements are enabled. The engine's logic is fully
/// tested against `MockCloudDatabase`; this is the thin mapping layer.
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
#endif
