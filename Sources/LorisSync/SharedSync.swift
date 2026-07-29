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
    func share(recordID: String,
               type: String,
               title: String?,
               permission: SharePermission) async throws -> ShareInfo

    /// The share for this record if one exists, `nil` otherwise.
    func existingShare(recordID: String, type: String) async throws -> ShareInfo?

    /// Accept a share the user opened. Safe to call twice — accepting an already
    /// accepted share is a no-op rather than an error.
    func acceptShare(at url: URL) async throws

    /// Records from the **shared** database. These never appear in `fetchAll`.
    func fetchShared(type: String) async throws -> [SyncRecord]

    /// Owner: revoke the share for everyone. Participant: leave it.
    /// `ShareInfo.isOwner` tells the caller which of the two will happen.
    func stopSharing(recordID: String, type: String) async throws
}

public enum ShareError: Error, Equatable {
    /// The link is malformed, revoked, or points at a container this app cannot read.
    case invalidShare
    /// The record to share does not exist in the private database.
    case recordNotFound
    /// Only the owner may perform this operation.
    case notOwner
}
