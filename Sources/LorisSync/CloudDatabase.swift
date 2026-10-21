import Foundation

/// A value a record field can hold. Mirrors the CloudKit types apps actually use;
/// anything richer belongs in a `Data` field the app encodes itself.
public enum SyncValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case stringList([String])
    case intList([Int])
}

/// One synced record, engine-facing and CloudKit-agnostic.
///
/// Fields are typed and named, mirroring the `CKRecord` schema an app already has
/// (`hour`, `label`, `repeat_days`…). The original model stored a single JSON
/// `blob`, which fitted the one app it was extracted from and **no other** — every
/// other app in the portfolio uses 8 to 168 typed fields, so adopting the engine
/// would have meant rewriting their CloudKit schema and migrating live user data.
///
/// `blob` survives as a computed field so `CloudSyncEngine`'s `Codable` path keeps
/// working: a whole-payload JSON is just one field among others.
///
/// `modifiedAt` drives last-writer-wins.
public struct SyncRecord: Sendable, Equatable {
    /// Field name used by the `Codable` convenience path.
    public static let blobKey = "blob"

    public let id: String
    public let type: String
    public var fields: [String: SyncValue]
    public var modifiedAt: Date

    /// Typed-field record — the shape that matches an existing CloudKit schema.
    public init(id: String, type: String, fields: [String: SyncValue], modifiedAt: Date) {
        self.id = id
        self.type = type
        self.fields = fields
        self.modifiedAt = modifiedAt
    }

    /// Whole-payload JSON record, for apps with no schema of their own.
    public init(id: String, type: String, blob: Data, modifiedAt: Date) {
        self.init(id: id, type: type, fields: [Self.blobKey: .data(blob)], modifiedAt: modifiedAt)
    }

    /// The `blob` field, or empty when this record carries typed fields instead.
    public var blob: Data {
        get {
            if case .data(let d)? = fields[Self.blobKey] { return d }
            return Data()
        }
        set { fields[Self.blobKey] = .data(newValue) }
    }

    // MARK: Typed accessors — read a field without unwrapping the enum by hand.

    public func string(_ key: String) -> String? {
        if case .string(let v)? = fields[key] { return v }
        return nil
    }

    public func int(_ key: String) -> Int? {
        if case .int(let v)? = fields[key] { return v }
        return nil
    }

    public func double(_ key: String) -> Double? {
        if case .double(let v)? = fields[key] { return v }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let v)? = fields[key] { return v }
        return nil
    }

    public func date(_ key: String) -> Date? {
        if case .date(let v)? = fields[key] { return v }
        return nil
    }

    public func data(_ key: String) -> Data? {
        if case .data(let v)? = fields[key] { return v }
        return nil
    }

    public func stringList(_ key: String) -> [String]? {
        if case .stringList(let v)? = fields[key] { return v }
        return nil
    }

    public func intList(_ key: String) -> [Int]? {
        if case .intList(let v)? = fields[key] { return v }
        return nil
    }
}

/// Whether the user's iCloud account can currently be used.
public enum SyncAccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, temporarilyUnavailable, unknown
}

/// The minimal CloudKit surface the engine needs, behind a protocol so it can be
/// mocked in tests (CI never touches real iCloud). A single small profile makes
/// a full fetch/save correct and simple — no change-token bookkeeping required.
public protocol CloudDatabase: Sendable {
    func accountStatus() async -> SyncAccountStatus
    /// Save (insert-or-replace) records in the user's private zone.
    /// An error may follow partial remote effects. Preserve local intent and
    /// reconcile before retrying; this Void API is not a durable revision ACK.
    func save(_ records: [SyncRecord]) async throws
    /// Every record of `type` in the zone (one profile → a tiny set).
    func fetchAll(type: String) async throws -> [SyncRecord]
    /// Delete records by id (GDPR erasure — wiping the synced profile).
    /// Failure does not imply that nothing was deleted; do not blindly replay.
    /// Native CloudKit prechecks type/identity but cannot atomically bind that read
    /// to ID-only deletion. Replacement races/cascades need a host/provider policy.
    func delete(ids: [String], type: String) async throws
}

public enum SyncError: Error, Equatable {
    case accountUnavailable
    case encodingFailed
}
