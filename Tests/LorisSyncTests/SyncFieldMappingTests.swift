#if canImport(CloudKit)
import CloudKit
import Foundation
import Testing
@testable import LorisSync

@Suite("Native field mapping, synthetic records without a container")
struct SyncFieldMappingTests {
    let date = Date(timeIntervalSince1970: 1_000)

    @Test(arguments: [Int64.min, Int64.max, 9_007_199_254_740_993])
    func signedIntegersNeverPassThroughDouble(value: Int64) {
        let expected = Int(exactly: value).map(SyncValue.int)
        #expect(SyncValue.from(NSNumber(value: value)) == expected)
    }

    @Test func unsignedOverflowIsRejectedInsteadOfRounded() {
        #expect(SyncValue.from(NSNumber(value: UInt64.max)) == nil)
    }

    @Test(arguments: [1.25, -0.0, 9_007_199_254_740_992.0])
    func floatingRepresentationIsNotInferredFromFractionalness(value: Double) throws {
        let number = NSNumber(value: value)
        // Assert the observable native representation, not an erased source-language type.
        let type = String(cString: number.objCType)
        #expect(type == "d" || type == "f")
        let mapped = try #require(SyncValue.from(number))
        guard case .double(let actual) = mapped else {
            Issue.record("Native floating representation was changed into an integer")
            return
        }
        #expect(actual == value)
        #expect(actual.sign == value.sign)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func nonFiniteNumbersAreRejected(value: Double) {
        #expect(SyncValue.from(NSNumber(value: value)) == nil)
    }

    @Test func unsupportedNumericRepresentationsAndListsAreRejected() {
        #expect(SyncValue.from(NSDecimalNumber(string: "1.234567890123456789")) == nil)
        #expect(SyncValue.from([NSNumber(value: 1.5)]) == nil)
        #expect(SyncValue.from([NSNumber(value: UInt64.max)]) == nil)
        #expect(SyncValue.from([NSNumber(value: 1), NSNumber(value: 1.5)]) == nil)
    }

    @Test func unsupportedFieldRejectsWholeRecordWithoutMutatingIt() {
        let record = nativeRecord()
        record["label"] = "fixture" as CKRecordValue
        let reference = CKRecord.Reference(recordID: .init(recordName: "other-fixture"), action: .none)
        record["unsupportedReference"] = reference
        #expect(SyncRecord(from: record, type: "Fixture", modifiedKey: "modifiedAt") == nil)
        #expect(record["unsupportedReference"] as? CKRecord.Reference == reference)
        #expect(record["label"] as? String == "fixture")
    }

    @Test func callerCannotRelabelNativeRecordType() {
        let record = nativeRecord()
        #expect(SyncRecord(from: record, type: "Other", modifiedKey: "modifiedAt") == nil)
    }

    @Test func supportedProfileAndTypedFieldsSurviveNativeRoundTrip() throws {
        let expected: [String: SyncValue] = [
            "blob": .data(Data("{}".utf8)), "label": .string("fixture"),
            "large": .int(Int.max), "fraction": .double(1.25),
            "when": .date(date), "tags": .stringList(["a", "b"]),
            "counts": .intList([Int.min, 0, Int.max])
        ]
        let source = SyncRecord(id: "fixture", type: "Fixture", fields: expected, modifiedAt: date)
        let native = nativeRecord()
        source.apply(to: native, modifiedKey: "modifiedAt")
        let mapped = try #require(SyncRecord(from: native, type: "Fixture", modifiedKey: "modifiedAt"))
        #expect(mapped.fields == expected)
        #expect(mapped.modifiedAt == date)
        #expect(mapped.id == "fixture")
    }

    private func nativeRecord() -> CKRecord {
        let record = CKRecord(recordType: "Fixture", recordID: .init(recordName: "fixture"))
        record["modifiedAt"] = date as CKRecordValue
        return record
    }
}
#endif
