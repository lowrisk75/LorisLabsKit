import Foundation
import Testing
@testable import LorisSync

@Suite("Outgoing and share policy validation, no provider")
struct SyncOutgoingValidationTests {
    @Test func supportedProfileAndTypedShapesAreAccepted() throws {
        try SyncRecordValidation.validate([
            .init(id: "profile", type: "Profile", blob: Data("{}".utf8), modifiedAt: .distantPast),
            .init(id: "typed", type: "Item", fields: ["enabled": .bool(true), "labels": .stringList([]),
                 "count": .int(Int.max), "value": .double(1.25)], modifiedAt: .distantPast)
        ])
    }
    @Test(arguments: ["", "bad type", "_system", "1Type"])
    func invalidNativeNamesAreRejected(type: String) {
        #expect(throws: CloudSyncValidationError.invalidRecord) {
            try SyncRecordValidation.validate([record(type: type)])
        }
    }
    @Test(arguments: ["", "bad key", "1key", "_key", "modifiedAt", "recordID"])
    func unsupportedOrReservedFieldNamesAreRejected(key: String) {
        #expect(throws: CloudSyncValidationError.invalidRecord) {
            try SyncRecordValidation.validate([record(fields: [key: .string("fixture")])])
        }
    }
    @Test func emptyOrControlIdentityIsRejected() {
        for id in ["", " \n", "bad\u{0000}id"] {
            #expect(throws: CloudSyncValidationError.invalidRecord) {
                try SyncRecordValidation.validate([record(id: id)])
            }
        }
    }
    @Test func nonFiniteOutgoingNumbersAndDatesAreRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: CloudSyncValidationError.invalidRecord) {
                try SyncRecordValidation.validate([record(fields: ["value": .double(value)])])
            }
            #expect(throws: CloudSyncValidationError.invalidRecord) {
                try SyncRecordValidation.validate([record(fields: ["when": .date(Date(timeIntervalSince1970: value))])])
            }
            #expect(throws: CloudSyncValidationError.invalidRecord) {
                try SyncRecordValidation.validate([.init(id: "id", type: "Item", fields: [:],
                                                       modifiedAt: Date(timeIntervalSince1970: value))])
            }
        }
    }
    @Test func duplicateNativeIdentityIsRejectedAcrossTypes() {
        #expect(throws: CloudSyncWriteError.invalidMutation) {
            try SyncRecordValidation.validate([record(type: "One"), record(type: "Two")])
        }
    }
    @Test func permissionMismatchNeverReturnsAnUnchangedBroaderShareAsRequested() {
        #expect(throws: CloudSyncSharePermissionError.existingPermissionMismatch) {
            try SyncShareResolution.requireAccess(.anyoneWithLink(.readWrite), requested: .anyoneWithLink(.readOnly))
        }
        #expect(throws: CloudSyncSharePermissionError.existingPermissionMismatch) {
            try SyncShareResolution.requireAccess(nil, requested: .anyoneWithLink(.readOnly))
        }
        // A public link never satisfies an invite-only request, and vice versa.
        #expect(throws: CloudSyncSharePermissionError.existingPermissionMismatch) {
            try SyncShareResolution.requireAccess(.anyoneWithLink(.readOnly), requested: .invitedOnly)
        }
        #expect(throws: CloudSyncSharePermissionError.existingPermissionMismatch) {
            try SyncShareResolution.requireAccess(.invitedOnly, requested: .anyoneWithLink(.readOnly))
        }
    }
    @Test(arguments: [ShareAccess.invitedOnly, .anyoneWithLink(.readOnly), .anyoneWithLink(.readWrite)])
    func equalAccessIsAccepted(access: ShareAccess) throws {
        try SyncShareResolution.requireAccess(access, requested: access)
    }
    private func record(id: String = "fixture", type: String = "Item", fields: [String: SyncValue] = [:]) -> SyncRecord {
        .init(id: id, type: type, fields: fields, modifiedAt: .distantPast)
    }
}
