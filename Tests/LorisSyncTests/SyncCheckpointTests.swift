#if canImport(CloudKit)
import CloudKit
import Foundation
import Testing
@testable import LorisSync

@Suite("Checkpoint archive integrity, no container or account")
struct SyncCheckpointTests {
    @Test func absentCheckpointIsTheOnlyImplicitFirstFetch() throws {
        #expect(try CloudKitDatabase.decode(nil) == nil)
    }

    @Test func emptyPresentCheckpointIsNotAbsence() {
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            _ = try CloudKitDatabase.decode(Data())
        }
    }

    @Test(arguments: [Data("fixture-not-an-archive".utf8), Data([0, 1, 2, 255])])
    func malformedCheckpointIsNotAbsence(bytes: Data) {
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            _ = try CloudKitDatabase.decode(bytes)
        }
    }

    @Test func secureArchiveOfAnotherRootClassIsRejected() throws {
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: "fixture-root" as NSString,
                                                    requiringSecureCoding: true)
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            _ = try CloudKitDatabase.decode(bytes)
        }
    }

    @Test func secureArchiveWithNilRootIsNotAbsence() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(nil, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let bytes = archiver.encodedData
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            _ = try CloudKitDatabase.decode(bytes)
        }
    }
}
#endif
