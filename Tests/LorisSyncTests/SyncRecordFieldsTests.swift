import XCTest
@testable import LorisSync

/// Covers the typed-field model.
///
/// The engine originally modelled a record as one JSON `blob`, which matched the
/// single app it was extracted from and no other: every other app in the portfolio
/// stores 8 to 168 typed CloudKit fields. Adopting the engine would have meant
/// rewriting their schema and migrating live user data — so records now carry
/// named, typed fields, and `blob` is one field among them.
final class SyncRecordFieldsTests: XCTestCase {

    // MARK: - Typed fields

    func testTypedFieldsRoundTripThroughTheirAccessors() {
        let record = SyncRecord(
            id: "alarm-1",
            type: "Alarm",
            fields: [
                "hour": .int(7),
                "minute": .int(30),
                "label": .string("Réveil"),
                "enabled": .bool(true),
                "volume": .double(0.8),
                "repeat_days": .intList([1, 2, 3, 4, 5]),
                "tags": .stringList(["work", "weekday"]),
                "sound": .data(Data([0xCA, 0xFE])),
                "lastFired": .date(Date(timeIntervalSince1970: 1_000_000)),
            ],
            modifiedAt: Date()
        )

        XCTAssertEqual(record.int("hour"), 7)
        XCTAssertEqual(record.string("label"), "Réveil")
        XCTAssertEqual(record.bool("enabled"), true)
        XCTAssertEqual(record.double("volume"), 0.8)
        XCTAssertEqual(record.intList("repeat_days"), [1, 2, 3, 4, 5])
        XCTAssertEqual(record.stringList("tags"), ["work", "weekday"])
        XCTAssertEqual(record.data("sound"), Data([0xCA, 0xFE]))
        XCTAssertEqual(record.date("lastFired"), Date(timeIntervalSince1970: 1_000_000))
    }

    func testAccessorsReturnNilOnTypeMismatchRatherThanGuessing() {
        let record = SyncRecord(id: "a", type: "T",
                                fields: ["hour": .int(7)], modifiedAt: Date())

        XCTAssertNil(record.string("hour"), "an Int field must not be read as a String")
        XCTAssertNil(record.int("missing"))
    }

    // MARK: - Backwards compatibility

    func testBlobInitStillWorksAndReadsBack() {
        let payload = Data(#"{"name":"x"}"#.utf8)
        let record = SyncRecord(id: "a", type: "T", blob: payload, modifiedAt: Date())

        XCTAssertEqual(record.blob, payload,
                       "the Codable path in CloudSyncEngine depends on this")
        XCTAssertEqual(record.data(SyncRecord.blobKey), payload,
                       "blob is just a field named 'blob'")
    }

    func testBlobIsEmptyOnATypedRecordRatherThanCrashing() {
        let record = SyncRecord(id: "a", type: "T",
                                fields: ["hour": .int(7)], modifiedAt: Date())

        XCTAssertTrue(record.blob.isEmpty,
                      "a schema-based record has no blob; reading it must be harmless")
    }

    func testSettingBlobOnATypedRecordLeavesOtherFieldsAlone() {
        var record = SyncRecord(id: "a", type: "T",
                                fields: ["hour": .int(7)], modifiedAt: Date())

        record.blob = Data([1, 2])

        XCTAssertEqual(record.int("hour"), 7)
        XCTAssertEqual(record.blob, Data([1, 2]))
    }

    // MARK: - Persistence through a database

    func testTypedFieldsSurviveSaveAndFetch() async throws {
        let db = MockCloudDatabase()
        let record = SyncRecord(id: "alarm-1", type: "Alarm",
                                fields: ["hour": .int(7), "label": .string("Réveil")],
                                modifiedAt: Date())

        try await db.save([record])
        let fetched = try await db.fetchAll(type: "Alarm")

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.int("hour"), 7)
        XCTAssertEqual(fetched.first?.string("label"), "Réveil")
    }

    // MARK: - Value semantics

    func testValuesAreCodableSoRecordsCanBeCachedOffline() throws {
        let values: [SyncValue] = [
            .string("a"), .int(1), .double(1.5), .bool(false),
            .date(Date(timeIntervalSince1970: 0)), .data(Data([9])),
            .stringList(["x"]), .intList([2]),
        ]

        let encoded = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([SyncValue].self, from: encoded)

        XCTAssertEqual(decoded, values)
    }
}
