import Foundation

/// A share as the app needs to see it — enough to present a share sheet and to
/// reason about ownership, without importing CloudKit.
public struct ShareInfo: Sendable, Equatable {
    /// The `CKShare` URL to hand to a share sheet or send in a message.
    public var url: URL
    /// Id of the shared root record.
    public var recordID: String
    /// `true` when the current user created the share. Owners can stop sharing;
    /// participants can only leave. Conflating the two produces a "Remove" button
    /// that fails for half the users.
    public var isOwner: Bool
    /// Participants including the owner.
    public var participantCount: Int

    public init(url: URL, recordID: String, isOwner: Bool, participantCount: Int) {
        self.url = url
        self.recordID = recordID
        self.isOwner = isOwner
        self.participantCount = participantCount
    }
}

/// Permission granted to people who open the share link.
public enum SharePermission: Sendable, Equatable {
    case readOnly
    case readWrite
}

/// Who may join a share.
public enum ShareAccess: Sendable, Equatable {
    /// Default. Only people the owner adds by name through Apple's sharing UI
    /// (`SyncShareItem` with SwiftUI `ShareLink`) can join; a forwarded link is
    /// useless to anyone else. Each invitee's permission is chosen in that UI.
    case invitedOnly
    /// Anyone holding the link joins with this permission. Explicit opt-in:
    /// a leaked link grants access and cannot be revoked per person.
    case anyoneWithLink(SharePermission)
}

/// A `CloudDatabase` that can also share records with other iCloud users.
///
/// Sharing lives in a *second* database (`sharedCloudDatabase`), not the private
/// one — records you participate in are never returned by a private-database
/// fetch. Apps that miss this silently show the owner's data and nothing else.
///
/// Refines `CloudDatabase` rather than replacing it, so non-sharing conformers
/// and test mocks are unaffected.
public protocol SharedCloudDatabase: CloudDatabase {
    /// Create a share for a record, or return the existing one. Idempotent:
    /// CloudKit rejects a second share on the same record, so callers must never
    /// have to check first.
    /// An existing share with a different access throws
    /// `CloudSyncSharePermissionError.existingPermissionMismatch`.
    func share(recordID: String,
               type: String,
               title: String?,
               access: ShareAccess) async throws -> ShareInfo

    /// The share for this record if one exists, `nil` otherwise.
    func existingShare(recordID: String, type: String) async throws -> ShareInfo?

    /// Accept a share the user opened. Safe to call twice — accepting an already
    /// accepted share is a no-op rather than an error.
    func acceptShare(at url: URL) async throws

    /// Records from the **shared** database. These never appear in `fetchAll`.
    /// Strict: one unreadable record fails the whole read.
    func fetchShared(type: String) async throws -> [SyncRecord]

    /// Shared records plus explicitly quarantined unreadable ones (per the
    /// database's read policy), so one sharer's bad record cannot block the rest.
    func fetchSharedReport(type: String) async throws -> SyncReadReport

    /// Legacy: owner revokes, participant leaves. Refuses (`ambiguousRecord`) when
    /// the name exists both privately and in a shared zone, which a participant
    /// can provoke. Use `revokeOwnedShare` / `leaveShare`.
    @available(*, deprecated, message: "Ambiguity can block revocation; use revokeOwnedShare(recordID:type:) or leaveShare(recordID:type:)")
    func stopSharing(recordID: String, type: String) async throws

    /// Owner: revoke the share of a private record for everyone. Never consults
    /// shared zones, so a colliding name there cannot block it.
    func revokeOwnedShare(recordID: String, type: String) async throws

    /// Participant: leave a share accepted from someone else. Never touches the
    /// caller's private records.
    func leaveShare(recordID: String, type: String) async throws

    /// Owner: change an existing share's access without revoking it, e.g.
    /// migrate a legacy public link (`share()` now throws
    /// `existingPermissionMismatch` for it) to `.invitedOnly`.
    func updateShareAccess(recordID: String, type: String, access: ShareAccess) async throws -> ShareInfo
}

extension SharedCloudDatabase {
    /// Invite-only share (the default). Add people with `SyncShareItem` + `ShareLink`.
    public func share(recordID: String, type: String, title: String?) async throws -> ShareInfo {
        try await share(recordID: recordID, type: type, title: title, access: .invitedOnly)
    }

    @available(*, deprecated, message: "Public links are opt-in: use access: .anyoneWithLink(permission), or the invite-only default")
    public func share(recordID: String, type: String, title: String?,
                      permission: SharePermission) async throws -> ShareInfo {
        try await share(recordID: recordID, type: type, title: title, access: .anyoneWithLink(permission))
    }
}

public enum ShareError: Error, Equatable {
    /// The link is malformed, revoked, or points at a container this app cannot read.
    case invalidShare
    /// The record to share does not exist in the private database.
    case recordNotFound
    /// Only the owner may perform this operation.
    case notOwner
}
