import Foundation

/// The result of an incremental fetch: what changed since the caller's last token.
///
/// `token` is opaque on purpose — the engine and the app persist it without knowing
/// it is a `CKServerChangeToken`, which keeps this layer testable and CloudKit-free.
public struct ZoneChanges: Sendable, Equatable {
    /// Records created or modified since `token`.
    public var changed: [SyncRecord]
    /// Ids deleted server-side since `token`. Without these, deletions never
    /// propagate and a record resurrects on the next upload.
    public var deletedIDs: [String]
    /// Token to persist and pass to the next call. `nil` means "start over".
    public var token: Data?
    /// `true` when the server rejected the token as expired and this payload is a
    /// full snapshot rather than a delta. Callers must treat `changed` PLUS
    /// `quarantined` as the whole truth: never delete local copies of
    /// quarantined IDs, and never merge the snapshot into stale local state.
    public var wasReset: Bool
    /// Records that changed but could not be mapped (unsupported/malformed
    /// content, e.g. written by a newer app version). They are NOT deletions:
    /// keep any local copy and flag it. Reported once: the checkpoint advances,
    /// so persist this list (or refetch from scratch) to keep track of them.
    /// Always empty under `CloudSyncReadPolicy.strict` (the read throws instead).
    public var quarantined: [QuarantinedRecord]

    public init(changed: [SyncRecord] = [],
                deletedIDs: [String] = [],
                token: Data? = nil,
                wasReset: Bool = false,
                quarantined: [QuarantinedRecord] = []) {
        self.changed = changed
        self.deletedIDs = deletedIDs
        self.token = token
        self.wasReset = wasReset
        self.quarantined = quarantined
    }
}

/// How a read treats a record whose content cannot be mapped.
public enum CloudSyncReadPolicy: Sendable, Equatable {
    /// Default. Deliver valid records, report unreadable ones in `quarantined`
    /// and advance the checkpoint, so one bad record cannot stall the type.
    case quarantineUnreadable
    /// Any unreadable record fails the whole read; the checkpoint never advances.
    case strict
}

/// A changed record that could not be mapped. Carries no content.
public struct QuarantinedRecord: Sendable, Equatable, CustomStringConvertible,
                                 CustomDebugStringConvertible, CustomReflectable {
    public enum Reason: Sendable, Equatable {
        /// Unsupported field type, missing/invalid `modifiedAt`, or other content
        /// this adapter refuses to map partially.
        case unsupportedContent
    }
    public let id: String
    public let reason: Reason
    public init(id: String, reason: Reason) {
        self.id = id
        self.reason = reason
    }
    public var description: String { "QuarantinedRecord(<redacted>, \(reason))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Complete read with explicit quarantine.
public struct SyncReadReport: Sendable, Equatable {
    public let records: [SyncRecord]
    public let quarantined: [QuarantinedRecord]
    public init(records: [SyncRecord], quarantined: [QuarantinedRecord]) {
        self.records = records
        self.quarantined = quarantined
    }
}

/// A `CloudDatabase` that can also sync *incrementally* and be woken by push.
///
/// `CloudDatabase` alone re-downloads everything on every sync. That is correct
/// and simple for one small profile — the case it was written for — but it does
/// not scale: seven apps in the portfolio need push (`CKSubscription`) and four
/// need change tokens. This protocol refines rather than replaces it, so existing
/// conformers (including test mocks) keep compiling untouched.
public protocol IncrementalCloudDatabase: CloudDatabase {
    /// Register a zone subscription so the server pushes a silent notification on
    /// change. Idempotent: safe to call at every launch.
    func registerChangeSubscription(id: String) async throws

    /// Records changed since `token`. Pass `nil` for a first full snapshot.
    func fetchChanges(type: String, since token: Data?) async throws -> ZoneChanges
}

/// Where change tokens are persisted between launches.
///
/// Behind a protocol because the right home differs per app: `UserDefaults` for a
/// single app or a host transaction containing fetched domain state + checkpoint.
/// A token alone does not authenticate an account, scope, freshness or progress.
public protocol ChangeTokenStore: Sendable {
    func token(for key: String) -> Data?
    func setToken(_ token: Data?, for key: String)
}

/// Legacy convenience only, not atomic with domain data and not a writer lock.
/// An App Group shares bytes, not transaction ownership or process coordination.
/// Prefer host transactions and ScopedSyncCheckpoint for new integrations.
public struct UserDefaultsChangeTokenStore: ChangeTokenStore {
    // The suite *name* is stored rather than the `UserDefaults` instance:
    // `UserDefaults` is not Sendable, and holding one would make this struct
    // unusable from an actor under Swift 6 strict concurrency.
    private let suiteName: String?
    private let prefix: String

    public init(suiteName: String? = nil, prefix: String = "lorissync.token.") {
        self.suiteName = suiteName
        self.prefix = prefix
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func token(for key: String) -> Data? {
        defaults.data(forKey: prefix + key)
    }

    public func setToken(_ token: Data?, for key: String) {
        if let token {
            defaults.set(token, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }
}
