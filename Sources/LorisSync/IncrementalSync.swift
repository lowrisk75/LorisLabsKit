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
    /// full snapshot rather than a delta. Callers must treat `changed` as the whole
    /// truth and not merge it into stale local state.
    public var wasReset: Bool

    public init(changed: [SyncRecord] = [],
                deletedIDs: [String] = [],
                token: Data? = nil,
                wasReset: Bool = false) {
        self.changed = changed
        self.deletedIDs = deletedIDs
        self.token = token
        self.wasReset = wasReset
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
/// single app, an App Group for an app + extension, the Keychain when the token
/// must survive a reinstall.
public protocol ChangeTokenStore: Sendable {
    func token(for key: String) -> Data?
    func setToken(_ token: Data?, for key: String)
}

/// `UserDefaults`-backed store. Pass an App Group suite when a widget or extension
/// syncs too — otherwise each process keeps its own token and they fight.
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
