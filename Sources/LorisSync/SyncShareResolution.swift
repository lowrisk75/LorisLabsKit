import Foundation

/// The legacy string-only sharing API cannot safely select a target.
public enum CloudSyncSharingError: Error, Equatable, Sendable {
    case ambiguousRecord
    case recordTypeMismatch
    case inconsistentMetadata
    case lookupLimitExceeded
}

enum SyncShareScope: Sendable { case privateDatabase, sharedDatabase }
enum SyncShareRole: Sendable { case owner, participant, unknown }

struct SyncShareCandidate<Root: Sendable>: Sendable {
    let scope: SyncShareScope
    let root: Root
}

enum SyncShareResolution {
    /// Only a provider's explicit missing-item result is absence. Cancellation,
    /// permissions, transport and malformed-data errors are never nil.
    static func optional<Value: Sendable>(
        isMissing: @Sendable (any Error) -> Bool,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value? {
        try Task.checkCancellation()
        do {
            let value = try await operation()
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            if isMissing(error) { return nil }
            throw error
        }
    }

    static func unique<Root: Sendable, Zone: Hashable & Sendable>(
        maxZones: Int = 1_000,
        privateRoot: @Sendable () async throws -> Root?,
        sharedZones: @Sendable () async throws -> [Zone],
        sharedRoot: @Sendable (Zone) async throws -> Root?
    ) async throws -> SyncShareCandidate<Root>? {
        try Task.checkCancellation()
        var candidate = try await privateRoot().map {
            SyncShareCandidate(scope: .privateDatabase, root: $0)
        }
        try Task.checkCancellation()
        let zones = try await sharedZones()
        try Task.checkCancellation()
        guard zones.count <= maxZones else { throw CloudSyncSharingError.lookupLimitExceeded }
        guard Set(zones).count == zones.count else {
            throw CloudSyncSharingError.inconsistentMetadata
        }
        for zone in zones {
            try Task.checkCancellation()
            let root = try await sharedRoot(zone)
            try Task.checkCancellation()
            if let root {
                guard candidate == nil else { throw CloudSyncSharingError.ambiguousRecord }
                candidate = SyncShareCandidate(scope: .sharedDatabase, root: root)
            }
        }
        return candidate
    }

    static func removeUnique<Root: Sendable, Zone: Hashable & Sendable>(
        maxZones: Int = 1_000,
        privateRoot: @Sendable () async throws -> Root?,
        sharedZones: @Sendable () async throws -> [Zone],
        sharedRoot: @Sendable (Zone) async throws -> Root?,
        remove: @Sendable (SyncShareCandidate<Root>) async throws -> Void
    ) async throws {
        guard let candidate = try await unique(
            maxZones: maxZones, privateRoot: privateRoot,
            sharedZones: sharedZones, sharedRoot: sharedRoot
        ) else { throw ShareError.recordNotFound }
        try Task.checkCancellation()
        try await remove(candidate)
    }

    static func isOwner(role: SyncShareRole) throws -> Bool {
        switch role {
        case .owner: return true
        case .participant: return false
        case .unknown: throw CloudSyncSharingError.inconsistentMetadata
        }
    }

    static func requireRemovalRole(scope: SyncShareScope, role: SyncShareRole,
                                   accepted: Bool) throws {
        switch scope {
        case .privateDatabase:
            guard role == .owner else { throw ShareError.notOwner }
        case .sharedDatabase:
            guard role == .participant, accepted else {
                throw CloudSyncSharingError.inconsistentMetadata
            }
        }
    }

    static func ensureUniqueIDs<Key: Hashable>(_ ids: [Key]) throws {
        guard Set(ids).count == ids.count else { throw CloudSyncSharingError.ambiguousRecord }
    }
}
