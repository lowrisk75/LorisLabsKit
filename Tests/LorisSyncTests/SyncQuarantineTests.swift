import Foundation
import Testing
@testable import LorisSync
#if canImport(CloudKit)
import CloudKit
#endif

@Suite("Unreadable-record quarantine, synthetic pages and native records")
struct SyncQuarantineTests {
    private func record(_ id: String) -> SyncRecord {
        SyncRecord(id: id, type: "Item", fields: [:], modifiedAt: .distantPast)
    }
    private func bad(_ id: String) -> QuarantinedRecord { .init(id: id, reason: .unsupportedContent) }

    @Test func quarantineIsReportedSeparatelyAndNeverAsDeletion() throws {
        let combined = try SyncZoneAccumulator.combine(
            [ZoneChanges(changed: [record("ok")], quarantined: [bad("broken")])],
            token: Data("t".utf8), wasReset: false)
        #expect(combined.changed.map(\.id) == ["ok"])
        #expect(combined.quarantined.map(\.id) == ["broken"])
        #expect(combined.deletedIDs.isEmpty)
        #expect(combined.token == Data("t".utf8)) // checkpoint advances
    }

    @Test func laterPageStateWinsForEachIdentity() throws {
        let repaired = try SyncZoneAccumulator.combine(
            [ZoneChanges(quarantined: [bad("a")]), ZoneChanges(changed: [record("a")])],
            token: nil, wasReset: false)
        #expect(repaired.changed.map(\.id) == ["a"] && repaired.quarantined.isEmpty)
        let broken = try SyncZoneAccumulator.combine(
            [ZoneChanges(changed: [record("a")]), ZoneChanges(quarantined: [bad("a")])],
            token: nil, wasReset: false)
        #expect(broken.changed.isEmpty && broken.quarantined.map(\.id) == ["a"])
        let deleted = try SyncZoneAccumulator.combine(
            [ZoneChanges(quarantined: [bad("a")]), ZoneChanges(deletedIDs: ["a"])],
            token: nil, wasReset: false)
        #expect(deleted.deletedIDs == ["a"] && deleted.quarantined.isEmpty)
    }

    @Test func contradictoryEventsInOnePageStillFail() {
        #expect(throws: CloudSyncReadError.conflictingChanges) {
            _ = try SyncZoneAccumulator.combine(
                [ZoneChanges(changed: [record("a")], quarantined: [bad("a")])], token: nil, wasReset: false)
        }
        #expect(throws: CloudSyncReadError.conflictingChanges) {
            _ = try SyncZoneAccumulator.combine(
                [ZoneChanges(deletedIDs: ["a"], quarantined: [bad("a")])], token: nil, wasReset: false)
        }
    }

    @Test func quarantineEntriesCarryNoContentInLogs() {
        var dumped = ""
        dump(bad("secret-id"), to: &dumped)
        #expect(!dumped.contains("secret-id") && !"\(bad("secret-id"))".contains("secret-id"))
    }

    #if canImport(CloudKit)
    private func native(_ configure: (CKRecord) -> Void) -> CKRecord {
        let record = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: "n",
                              zoneID: CKRecordZone.ID(zoneName: "Z", ownerName: CKCurrentUserDefaultName)))
        configure(record)
        return record
    }

    @Test func unsupportedNativeContentIsQuarantinedByDefaultAndThrowsWhenStrict() throws {
        let unsupported = native {
            $0["modifiedAt"] = Date() as CKRecordValue
            $0["link"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: "x"), action: .none)
        }
        let missingDate = native { $0["title"] = "t" as CKRecordValue }
        for record in [unsupported, missingDate] {
            guard case .quarantined(let entry) = try CloudKitDatabase.mapOrQuarantine(
                record, type: "Item", policy: .quarantineUnreadable) else {
                Issue.record("unreadable content must be quarantined"); continue
            }
            #expect(entry.id == "n")
            #expect(throws: CloudSyncReadError.invalidRecord) {
                _ = try CloudKitDatabase.mapOrQuarantine(record, type: "Item", policy: .strict)
            }
        }
    }

    @Test func wrongTypeIsNeverQuarantined() {
        let other = native { $0["modifiedAt"] = Date() as CKRecordValue }
        #expect(throws: CloudSyncReadError.invalidRecord) {
            _ = try CloudKitDatabase.mapOrQuarantine(other, type: "Other", policy: .quarantineUnreadable)
        }
    }

    @Test func readableNativeRecordMapsNormally() throws {
        let good = native {
            $0["modifiedAt"] = Date(timeIntervalSince1970: 5) as CKRecordValue
            $0["title"] = "t" as CKRecordValue
        }
        guard case .record(let mapped) = try CloudKitDatabase.mapOrQuarantine(
            good, type: "Item", policy: .quarantineUnreadable) else {
            Issue.record("readable record must map"); return
        }
        #expect(mapped.string("title") == "t")
    }
    #endif
}
