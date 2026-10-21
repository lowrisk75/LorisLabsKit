import Foundation

public enum SyncOutboxError: Error, Equatable, Sendable {
    case invalidLimits, invalidIdentifier, invalidState, unsupportedVersion
    case capacityExceeded, revisionExhausted, scopeMismatch, inactiveSession
    case invalidReceipt, invalidLimit
}

/// Opaque authenticated account and fully qualified provider/container/database/zone/owner namespace.
/// This value does not verify the currently signed-in provider account.
public struct SyncOutboxScope: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accountID: String
    public let namespace: String
    public init(accountID: String, namespace: String) {
        self.accountID = accountID
        self.namespace = namespace
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID.utf8.elementsEqual(rhs.accountID.utf8)
            && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)
    }
    public func hash(into hasher: inout Hasher) {
        hashOutboxIdentifier(accountID, into: &hasher)
        hashOutboxIdentifier(namespace, into: &hasher)
    }
    public var description: String { "SyncOutboxScope(<redacted>)" }
    public var debugDescription: String { description }
}

public struct SyncOutboxKey: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let recordType: String
    public let recordID: String
    public init(recordType: String, recordID: String) {
        self.recordType = recordType
        self.recordID = recordID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.recordType.utf8.elementsEqual(rhs.recordType.utf8)
            && lhs.recordID.utf8.elementsEqual(rhs.recordID.utf8)
    }
    public func hash(into hasher: inout Hasher) {
        hashOutboxIdentifier(recordType, into: &hasher)
        hashOutboxIdentifier(recordID, into: &hasher)
    }
    public var description: String { "SyncOutboxKey(<redacted>)" }
    public var debugDescription: String { description }
}

// Opaque provider identifiers are byte identities, not Swift's canonically equivalent Strings.
// Prefix lengths delimit fields; hash the bytes with the same semantics as equality.
private func hashOutboxIdentifier(_ value: String, into hasher: inout Hasher) {
    hasher.combine(value.utf8.count)
    for byte in value.utf8 { hasher.combine(byte) }
}

public enum SyncOutboxOperation: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Host supplies protected/presealed bytes where the domain requires it.
    case save(Data)
    /// Transport intent, not an authenticated domain tombstone.
    case delete
    public var description: String {
        switch self {
        case .save(let data): return "SyncOutboxOperation.save(\(data.count) bytes)"
        case .delete: return "SyncOutboxOperation.delete"
        }
    }
    public var debugDescription: String { description }
}

public struct SyncOutboxLimits: Sendable {
    public let maximumPendingMutations: Int
    public let maximumPayloadBytes: Int
    public let maximumEncodedBytes: Int
    public let maximumIdentifierBytes: Int
    public init(maximumPendingMutations: Int = 1_024,
                maximumPayloadBytes: Int = 1_048_576,
                maximumEncodedBytes: Int = 8_388_608,
                maximumIdentifierBytes: Int = 1_024) {
        self.maximumPendingMutations = maximumPendingMutations
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumIdentifierBytes = maximumIdentifierBytes
    }
}

/// Runtime token, intentionally not Codable or publicly constructible.
public struct SyncOutboxSession: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let scope: SyncOutboxScope
    fileprivate let journalID: UUID
    fileprivate let generation: UUID
    public var description: String { "SyncOutboxSession(<redacted>)" }
    public var debugDescription: String { description }
}

/// Capture the delivery BEFORE dispatch. Never synthesize an ACK from a later pending lookup.
public struct SyncOutboxReceipt: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let scope: SyncOutboxScope
    public let key: SyncOutboxKey
    public let revision: UInt64
    public let mutationID: UUID
    fileprivate let journalID: UUID
    fileprivate let sessionID: UUID
    public var description: String { "SyncOutboxReceipt(revision: \(revision))" }
    public var debugDescription: String { description }
}

public struct SyncOutboxDelivery: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let receipt: SyncOutboxReceipt
    public let operation: SyncOutboxOperation
    fileprivate init(receipt: SyncOutboxReceipt, operation: SyncOutboxOperation) {
        self.receipt = receipt
        self.operation = operation
    }
    public var description: String { "SyncOutboxDelivery(revision: \(receipt.revision))" }
    public var debugDescription: String { description }
}

/// Synchronous transaction-owned journal, NOT an independent durable store or transport.
/// Persist a candidate with domain state in one host transaction, then publish it only
/// after commit. All writers must serialize/reload current state; no cross-process CAS.
/// Encoding contains payloads/identifiers and is not encryption or rollback protection.
public struct RevisionedSyncOutbox: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private struct Mutation: Codable, Sendable {
        let key: SyncOutboxKey
        let revision: UInt64
        let mutationID: UUID
        let kind: String
        let payload: Data?
        func operation() throws -> SyncOutboxOperation {
            switch (kind, payload) {
            case ("save", .some(let data)): return .save(data)
            case ("delete", .none): return .delete
            default: throw SyncOutboxError.invalidState
            }
        }
    }
    private struct Snapshot: Codable {
        let version: Int
        let journalID: UUID
        let scope: SyncOutboxScope
        var sessionID: UUID?
        var lastRevision: UInt64
        var mutations: [Mutation]
    }

    public let scope: SyncOutboxScope
    private let journalID: UUID
    private let limits: SyncOutboxLimits
    private var sessionID: UUID?
    private var lastRevision: UInt64
    private var mutations: [Mutation]

    public var pendingCount: Int { mutations.count }
    public var description: String { "RevisionedSyncOutbox(pending: \(pendingCount))" }
    public var debugDescription: String { description }

    public init(scope: SyncOutboxScope, limits: SyncOutboxLimits = .init()) throws {
        try Self.validateLimits(limits)
        try Self.validateScope(scope, limits: limits)
        self.scope = scope
        self.journalID = UUID()
        self.limits = limits
        self.sessionID = nil
        self.lastRevision = 0
        self.mutations = []
        _ = try encoded()
    }

    /// Restore inside the serialized host transaction. On owner/process start,
    /// begin a NEW verified session and persist it before any dispatch.
    /// Same-process transaction reload may retain its existing runtime token.
    public init(restoring data: Data, expectedScope: SyncOutboxScope,
                limits: SyncOutboxLimits = .init()) throws {
        try Self.validateLimits(limits)
        try Self.validateScope(expectedScope, limits: limits)
        guard data.count <= limits.maximumEncodedBytes else { throw SyncOutboxError.capacityExceeded }
        let snapshot: Snapshot
        do { snapshot = try JSONDecoder().decode(Snapshot.self, from: data) }
        catch { throw SyncOutboxError.invalidState }
        guard snapshot.version == 1 else { throw SyncOutboxError.unsupportedVersion }
        guard snapshot.scope == expectedScope else { throw SyncOutboxError.scopeMismatch }
        try Self.validateSnapshot(snapshot, limits: limits)
        self.scope = snapshot.scope
        self.journalID = snapshot.journalID
        self.limits = limits
        self.sessionID = snapshot.sessionID
        self.lastRevision = snapshot.lastRevision
        self.mutations = snapshot.mutations
        _ = try encoded() // Validate canonical encoding and reserve future session activation.
    }

    /// Stable versioned bytes; store alongside domain changes, never in a parallel
    /// independently committed file. Limits bound accepted data, not decoder RSS.
    public func encoded() throws -> Data {
        var snapshot = Snapshot(version: 1, journalID: journalID, scope: scope,
                                sessionID: sessionID, lastRevision: lastRevision, mutations: mutations)
        try Self.validateSnapshot(snapshot, limits: limits)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(snapshot)
            if snapshot.sessionID == nil {
                // Reserve the real encoded field, not a magic JSON byte allowance.
                // Offline enqueue/restore must never accept a state that cannot activate.
                snapshot.sessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                guard try encoder.encode(snapshot).count <= limits.maximumEncodedBytes else {
                    throw SyncOutboxError.capacityExceeded
                }
            }
        }
        catch let error as SyncOutboxError { throw error }
        catch { throw SyncOutboxError.invalidState }
        guard data.count <= limits.maximumEncodedBytes else { throw SyncOutboxError.capacityExceeded }
        return data
    }

    /// Offline intent is allowed only for this fixed scope. Coalescing preserves
    /// the newest local intent; remote ordering/conflicts remain provider-owned.
    @discardableResult
    public mutating func enqueue(_ operation: SyncOutboxOperation, for key: SyncOutboxKey,
                                 scope expectedScope: SyncOutboxScope) throws -> UInt64 {
        guard expectedScope == scope else { throw SyncOutboxError.scopeMismatch }
        try Self.validateKey(key, limits: limits)
        guard lastRevision < UInt64.max else { throw SyncOutboxError.revisionExhausted }
        let payload: Data?
        let kind: String
        switch operation {
        case .save(let data):
            guard data.count <= limits.maximumPayloadBytes else { throw SyncOutboxError.capacityExceeded }
            payload = data
            kind = "save"
        case .delete:
            payload = nil
            kind = "delete"
        }
        var candidate = self
        let mutation = Mutation(key: key, revision: lastRevision + 1, mutationID: UUID(),
                                kind: kind, payload: payload)
        if let index = candidate.mutations.firstIndex(where: { $0.key == key }) {
            candidate.mutations[index] = mutation
        } else {
            guard candidate.mutations.count < limits.maximumPendingMutations else {
                throw SyncOutboxError.capacityExceeded
            }
            candidate.mutations.append(mutation)
        }
        candidate.lastRevision = mutation.revision
        _ = try candidate.encoded() // Failure leaves self untouched, including revision.
        self = candidate
        return mutation.revision
    }

    /// Host must verify the provider account and persist this transition before dispatch.
    public mutating func beginSession(for expectedScope: SyncOutboxScope) throws -> SyncOutboxSession {
        guard expectedScope == scope else { throw SyncOutboxError.scopeMismatch }
        var candidate = self
        let generation = UUID()
        candidate.sessionID = generation
        _ = try candidate.encoded()
        self = candidate
        return SyncOutboxSession(scope: scope, journalID: journalID, generation: generation)
    }

    /// Persist before accepting callbacks for a changed/unavailable account.
    /// Intent is retained, never moved to another account or silently erased.
    public mutating func suspend() { sessionID = nil }

    public func pending(using session: SyncOutboxSession, limit: Int = 100) throws -> [SyncOutboxDelivery] {
        try requireSession(session)
        guard limit > 0 else { throw SyncOutboxError.invalidLimit }
        return try mutations.sorted { $0.revision < $1.revision }.prefix(limit).map { mutation in
            SyncOutboxDelivery(receipt: SyncOutboxReceipt(
                scope: scope, key: mutation.key, revision: mutation.revision,
                mutationID: mutation.mutationID, journalID: journalID, sessionID: session.generation),
                operation: try mutation.operation())
        }
    }

    /// Call only after an actual successful response for THIS captured delivery.
    /// Persist ACK + related domain/server metadata in the same host transaction.
    /// false means duplicate/stale revision, not permission to clear by record ID.
    @discardableResult
    public mutating func acknowledge(_ receipt: SyncOutboxReceipt,
                                     using session: SyncOutboxSession) throws -> Bool {
        try requireSession(session)
        guard receipt.scope == scope else { throw SyncOutboxError.scopeMismatch }
        guard receipt.journalID == journalID, receipt.sessionID == session.generation else {
            throw SyncOutboxError.invalidReceipt
        }
        guard let index = mutations.firstIndex(where: {
            $0.key == receipt.key && $0.revision == receipt.revision && $0.mutationID == receipt.mutationID
        }) else { return false }
        mutations.remove(at: index)
        return true
    }

    private func requireSession(_ session: SyncOutboxSession) throws {
        guard session.scope == scope else { throw SyncOutboxError.scopeMismatch }
        guard session.journalID == journalID, sessionID == session.generation else {
            throw SyncOutboxError.inactiveSession
        }
    }

    private static func validateLimits(_ limits: SyncOutboxLimits) throws {
        guard (1...100_000).contains(limits.maximumPendingMutations),
              (1...67_108_864).contains(limits.maximumPayloadBytes),
              (256...134_217_728).contains(limits.maximumEncodedBytes),
              (1...4_096).contains(limits.maximumIdentifierBytes) else {
            throw SyncOutboxError.invalidLimits
        }
    }
    private static func validateIdentifier(_ value: String, limits: SyncOutboxLimits) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= limits.maximumIdentifierBytes,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SyncOutboxError.invalidIdentifier
        }
    }
    private static func validateScope(_ scope: SyncOutboxScope, limits: SyncOutboxLimits) throws {
        try validateIdentifier(scope.accountID, limits: limits)
        try validateIdentifier(scope.namespace, limits: limits)
    }
    private static func validateKey(_ key: SyncOutboxKey, limits: SyncOutboxLimits) throws {
        try validateIdentifier(key.recordType, limits: limits)
        try validateIdentifier(key.recordID, limits: limits)
    }
    private static func validateSnapshot(_ snapshot: Snapshot, limits: SyncOutboxLimits) throws {
        try validateScope(snapshot.scope, limits: limits)
        guard snapshot.mutations.count <= limits.maximumPendingMutations else {
            throw SyncOutboxError.capacityExceeded
        }
        var keys = Set<SyncOutboxKey>()
        var revisions = Set<UInt64>()
        var ids = Set<UUID>()
        for mutation in snapshot.mutations {
            try validateKey(mutation.key, limits: limits)
            guard mutation.revision > 0, mutation.revision <= snapshot.lastRevision,
                  keys.insert(mutation.key).inserted,
                  revisions.insert(mutation.revision).inserted,
                  ids.insert(mutation.mutationID).inserted else { throw SyncOutboxError.invalidState }
            switch (mutation.kind, mutation.payload) {
            case ("save", .some(let data)):
                guard data.count <= limits.maximumPayloadBytes else { throw SyncOutboxError.capacityExceeded }
            case ("delete", .none): break
            default: throw SyncOutboxError.invalidState
            }
        }
    }
}
