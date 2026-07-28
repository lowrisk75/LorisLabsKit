import Foundation

/// A value that can be synced as a single CloudKit record. For Mela this is a
/// child's `Profile` (board + voice + settings) — small, Codable, one per user.
///
/// The engine serializes the payload to a JSON blob in one record field; the
/// data shape is a few KB, so a whole-record write/read is correct and simple
/// (no per-field shredding or change tokens needed for a single profile).
public protocol SyncablePayload: Codable, Sendable, Identifiable where ID == String {
    /// CloudKit record type, e.g. `"Profile"`.
    static var recordType: String { get }
}

/// A backing image/file that travels with a payload (e.g. a per-cell photo or a
/// scene image), uploaded as a `CKAsset`. The `key` is stable (e.g. the vocab
/// item id) so it maps back deterministically on the other device.
public struct SyncableAsset: Sendable, Equatable {
    public let key: String
    public let fileURL: URL
    public init(key: String, fileURL: URL) {
        self.key = key
        self.fileURL = fileURL
    }
}
