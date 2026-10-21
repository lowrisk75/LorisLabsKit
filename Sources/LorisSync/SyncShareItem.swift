#if canImport(CloudKit) && canImport(CoreTransferable) && (os(iOS) || os(macOS) || os(visionOS))
import CloudKit
import CoreTransferable
import Foundation

/// Hand to SwiftUI `ShareLink(item:preview:)`. Apple's sharing UI then lets the
/// owner add people by name and choose each one's permission; with
/// `.invitedOnly` it offers specified recipients only. Create it with
/// `CloudKitDatabase.shareItem(recordID:type:title:access:)`.
/// Not available on tvOS/watchOS (no system sharing UI there).
public struct SyncShareItem: Transferable, Sendable, CustomStringConvertible,
                             CustomDebugStringConvertible, CustomReflectable {
    enum Source: Sendable {
        case existing(CKShare)
        case prepare(@Sendable () async throws -> CKShare)
    }

    // The share carries its URL (a capability for public links) and participant
    // identities: never print or reflect it.
    public var description: String { "SyncShareItem(<redacted>, access: \(access))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    let source: Source
    let container: CKContainer
    public let access: ShareAccess
    public let options: SyncShareOptions

    init(source: Source, container: CKContainer, access: ShareAccess, options: SyncShareOptions) {
        self.source = source
        self.container = container
        self.access = access
        self.options = options
    }

    var allowedSharingOptions: CKAllowedSharingOptions {
        Self.allowedSharingOptions(for: access, options: options)
    }

    static func allowedSharingOptions(for access: ShareAccess,
                                      options: SyncShareOptions = .init()) -> CKAllowedSharingOptions {
        let allowed: CKAllowedSharingOptions
        switch access {
        case .invitedOnly:
            allowed = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .any,
                                              allowedParticipantAccessOptions: .specifiedRecipientsOnly)
        case .anyoneWithLink(.readOnly):
            allowed = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readOnly,
                                              allowedParticipantAccessOptions: .anyoneWithLink)
        case .anyoneWithLink(.readWrite):
            allowed = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                              allowedParticipantAccessOptions: .anyoneWithLink)
        }
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            allowed.allowsParticipantsToInviteOthers = options.allowsParticipantsToInviteOthers
            allowed.allowsAccessRequests = options.allowsAccessRequests
        }
        return allowed
    }

    public static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            switch item.source {
            case .existing(let share):
                return .existing(share, container: item.container,
                                 allowedSharingOptions: item.allowedSharingOptions)
            case .prepare(let prepare):
                return .prepareShare(container: item.container,
                                     allowedSharingOptions: item.allowedSharingOptions,
                                     preparationHandler: prepare)
            }
        }
    }
}

extension CloudKitDatabase {
    /// System-UI sharing item for a private record. Reuses an existing owned
    /// share (its access must match); otherwise the share is created only when
    /// the user confirms in Apple's sheet.
    public func shareItem(recordID: String, type: String, title: String?,
                          access: ShareAccess = .invitedOnly,
                          options: SyncShareOptions = .init()) async throws -> SyncShareItem {
        try SyncRecordValidation.validateID(recordID)
        try SyncRecordValidation.validateType(type)
        let rootID = CKRecord.ID(recordName: recordID, zoneID: shareZoneID)
        let database = sharePrivateDatabase
        if let existing = try await Self.existingOwnedShare(rootID: rootID, type: type, access: access, in: database) {
            return SyncShareItem(source: .existing(existing), container: shareContainer,
                                 access: access, options: options)
        }
        return SyncShareItem(source: .prepare {
            try await Self.ensureShare(rootID: rootID, type: type, title: title, access: access, in: database)
        }, container: shareContainer, access: access, options: options)
    }
}
#endif

/// Optional system share-sheet capabilities (iOS/macOS/visionOS 26+). Both off by
/// default; ignored on older OS versions. On older OS, CloudKit presents
/// administrators as read-only private participants.
public struct SyncShareOptions: Sendable, Equatable {
    /// Let the owner make chosen participants administrators who can invite others.
    public var allowsParticipantsToInviteOthers: Bool
    /// Let the owner allow people to request access to the share.
    public var allowsAccessRequests: Bool
    public init(allowsParticipantsToInviteOthers: Bool = false, allowsAccessRequests: Bool = false) {
        self.allowsParticipantsToInviteOthers = allowsParticipantsToInviteOthers
        self.allowsAccessRequests = allowsAccessRequests
    }
}
