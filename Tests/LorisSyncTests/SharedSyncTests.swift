import XCTest
@testable import LorisSync

/// Covers sharing. The trap this locks down: shared records live in a **separate**
/// CloudKit database, so a private-database fetch never returns them. An app that
/// assumes otherwise shows the owner their own data and participants nothing.
final class SharedSyncTests: XCTestCase {

    private func record(_ id: String, _ text: String = "x") -> SyncRecord {
        SyncRecord(id: id, type: "Item", blob: Data(text.utf8), modifiedAt: Date())
    }

    // MARK: - Creating a share

    func testSharingReturnsAUsableLinkAndMarksOwnership() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a")])

        let info = try await db.share(recordID: "a", type: "Item",
                                      title: "Ma liste", permission: .readWrite)

        XCTAssertTrue(info.isOwner)
        XCTAssertEqual(info.recordID, "a")
        XCTAssertFalse(info.url.absoluteString.isEmpty)
    }

    func testSharingTwiceReturnsTheSameShare() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a")])

        let first = try await db.share(recordID: "a", type: "Item", title: nil, permission: .readWrite)
        let second = try await db.share(recordID: "a", type: "Item", title: nil, permission: .readWrite)

        XCTAssertEqual(first.url, second.url,
                       "CloudKit rejects a second share on one record — reuse must be silent")
    }

    func testSharingAnUnknownRecordThrows() async {
        let db = MockCloudDatabase()
        do {
            _ = try await db.share(recordID: "ghost", type: "Item", title: nil, permission: .readOnly)
            XCTFail("sharing a record that does not exist must fail loudly")
        } catch {
            XCTAssertEqual(error as? ShareError, .recordNotFound)
        }
    }

    func testExistingShareIsNilBeforeSharing() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a")])

        let existing = try await db.existingShare(recordID: "a", type: "Item")

        XCTAssertNil(existing)
    }

    // MARK: - The separate-database trap

    func testSharedRecordsNeverAppearInThePrivateFetch() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("mine")])
        await db.receiveShare(record("theirs"),
                              from: URL(string: "https://www.icloud.com/share/theirs")!)

        let priv = try await db.fetchAll(type: "Item")
        let shared = try await db.fetchShared(type: "Item")

        XCTAssertEqual(priv.map(\.id), ["mine"],
                       "the private database must not leak shared records")
        XCTAssertEqual(shared.map(\.id), ["theirs"],
                       "participants' records are only reachable via fetchShared")
    }

    // MARK: - Accepting

    func testAcceptingTwiceIsANoOp() async throws {
        let db = MockCloudDatabase()
        let url = URL(string: "https://www.icloud.com/share/abc")!

        try await db.acceptShare(at: url)
        try await db.acceptShare(at: url)

        let accepted = await db.acceptedShareURLs
        XCTAssertEqual(accepted, [url],
                       "re-opening a link the user already accepted must not error")
    }

    func testAcceptingAMalformedLinkThrows() async {
        let db = MockCloudDatabase()
        do {
            try await db.acceptShare(at: URL(string: "https://example.com/nope")!)
            XCTFail("a link that is not a share must be rejected")
        } catch {
            XCTAssertEqual(error as? ShareError, .invalidShare)
        }
    }

    // MARK: - Stopping

    func testOwnerStopsSharingButKeepsTheRecord() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a")])
        _ = try await db.share(recordID: "a", type: "Item", title: nil, permission: .readWrite)

        try await db.stopSharing(recordID: "a", type: "Item")

        let existing = try await db.existingShare(recordID: "a", type: "Item")
        let priv = try await db.fetchAll(type: "Item")
        XCTAssertNil(existing, "revoking must remove the share")
        XCTAssertEqual(priv.map(\.id), ["a"], "the owner keeps their own record")
    }

    func testParticipantLeavingLosesAccess() async throws {
        let db = MockCloudDatabase()
        await db.receiveShare(record("theirs"),
                              from: URL(string: "https://www.icloud.com/share/theirs")!)

        try await db.stopSharing(recordID: "theirs", type: "Item")

        let shared = try await db.fetchShared(type: "Item")
        XCTAssertTrue(shared.isEmpty, "leaving a share must drop the record")
    }

    func testStoppingAnUnsharedRecordThrows() async {
        let db = MockCloudDatabase()
        do {
            try await db.stopSharing(recordID: "a", type: "Item")
            XCTFail("nothing to stop — must not fail silently")
        } catch {
            XCTAssertEqual(error as? ShareError, .recordNotFound)
        }
    }
}
