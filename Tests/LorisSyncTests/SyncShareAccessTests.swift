#if canImport(CloudKit)
import CloudKit
import Foundation
import Testing
@testable import LorisSync

@Suite("Invite-only share access, native objects without a container")
struct SyncShareAccessTests {
    private func root() -> CKRecord {
        CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: "a",
                 zoneID: CKRecordZone.ID(zoneName: "Fixture", ownerName: CKCurrentUserDefaultName)))
    }

    @Test func inviteOnlyShareHasNoPublicPermission() {
        let share = CloudKitDatabase.makeShare(root: root(), title: "Liste", access: .invitedOnly)
        #expect(share.publicPermission == .none)
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Liste")
    }

    @Test(arguments: [SharePermission.readOnly, .readWrite])
    func publicLinkIsOnlyCreatedWhenExplicit(permission: SharePermission) {
        let share = CloudKitDatabase.makeShare(root: root(), title: nil, access: .anyoneWithLink(permission))
        #expect(share.publicPermission == (permission == .readOnly ? .readOnly : .readWrite))
    }

    @Test func nativePermissionMapsBackExactly() {
        #expect(CloudKitDatabase.effectiveAccess(.none) == .invitedOnly)
        #expect(CloudKitDatabase.effectiveAccess(.readOnly) == .anyoneWithLink(.readOnly))
        #expect(CloudKitDatabase.effectiveAccess(.readWrite) == .anyoneWithLink(.readWrite))
        #expect(CloudKitDatabase.effectiveAccess(.unknown) == nil)
    }

    @Test(arguments: [ShareAccess.invitedOnly, .anyoneWithLink(.readOnly), .anyoneWithLink(.readWrite)])
    func createdShareRoundTripsItsAccess(access: ShareAccess) {
        let share = CloudKitDatabase.makeShare(root: root(), title: nil, access: access)
        #expect(CloudKitDatabase.effectiveAccess(share.publicPermission) == access)
    }

    #if canImport(CoreTransferable) && (os(iOS) || os(macOS) || os(visionOS))
    @Test func systemSheetOffersOnlyNamedRecipientsForInviteOnly() {
        let options = SyncShareItem.allowedSharingOptions(for: .invitedOnly)
        #expect(options.allowedParticipantAccessOptions == .specifiedRecipientsOnly)
        #expect(options.allowedParticipantPermissionOptions == .any)
    }

    @Test func osTwentySixOptionsAreOffByDefaultAndOptIn() {
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return }
        let standard = SyncShareItem.allowedSharingOptions(for: .invitedOnly)
        #expect(!standard.allowsParticipantsToInviteOthers && !standard.allowsAccessRequests)
        let opted = SyncShareItem.allowedSharingOptions(
            for: .invitedOnly,
            options: SyncShareOptions(allowsParticipantsToInviteOthers: true, allowsAccessRequests: true))
        #expect(opted.allowsParticipantsToInviteOthers && opted.allowsAccessRequests)
        #expect(opted.allowedParticipantAccessOptions == .specifiedRecipientsOnly)
    }

    @Test func publicLinkSheetCannotWidenThePermission() {
        let options = SyncShareItem.allowedSharingOptions(for: .anyoneWithLink(.readOnly))
        #expect(options.allowedParticipantAccessOptions == .anyoneWithLink)
        #expect(options.allowedParticipantPermissionOptions == .readOnly)
    }
    #endif
}
#endif
