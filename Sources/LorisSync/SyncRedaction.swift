import Foundation

// `dump`/`Mirror` bypass `description`; these types carry tokens, share URLs
// (bearer capabilities) or payloads, so reflection exposes no children.

extension ScopedSyncCheckpoint: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxScope: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxKey: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxOperation: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxSession: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxReceipt: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension SyncOutboxDelivery: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
extension RevisionedSyncOutbox: CustomReflectable {
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension ShareInfo: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ShareInfo(<redacted>, isOwner: \(isOwner))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension ZoneChanges: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ZoneChanges(changed: \(changed.count), deleted: \(deletedIDs.count), quarantined: \(quarantined.count), wasReset: \(wasReset))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension ScopedSyncChanges: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ScopedSyncChanges(changed: \(changed.count), deleted: \(deletedIDs.count), quarantined: \(quarantined.count), wasReset: \(wasReset))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension SyncRecord: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "SyncRecord(<redacted>, fields: \(fields.count))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
