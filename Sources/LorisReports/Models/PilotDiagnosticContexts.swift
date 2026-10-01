import Foundation

/// Snapshots are supplied by the host after its critical work completes.
/// These adapters cannot inspect health data, camera content, addresses, vehicles or credentials.
public struct VelyaDiagnosticContext: DiagnosticContextProvider {
    public enum Scheduler: String, Sendable { case confirmed, unconfirmed, unavailable, unknown }
    public enum Permission: String, Sendable { case authorized, denied, notDetermined = "not_determined", unknown }
    public let scheduler: Scheduler
    public let permission: Permission
    public init(scheduler: Scheduler, permission: Permission) { self.scheduler = scheduler; self.permission = permission }
    public func context() async -> [FeedbackContextValue] {
        [.init(field: .schedulerState, code: scheduler.rawValue, category: .systemDiagnostics),
         .init(field: .permissionState, code: permission.rawValue, category: .systemDiagnostics)]
    }
}

public struct LumenDiagnosticContext: DiagnosticContextProvider {
    public enum Stream: String, Sendable { case playing, buffering, disconnected, failed, unknown }
    public let stream: Stream
    public init(stream: Stream) { self.stream = stream }
    public func context() async -> [FeedbackContextValue] {
        [.init(field: .streamState, code: stream.rawValue, category: .systemDiagnostics)]
    }
}

public struct EclairDiagnosticContext: DiagnosticContextProvider {
    public enum OBD: String, Sendable { case connected, disconnected, unsupported, unknown }
    public enum Sync: String, Sendable { case idle, syncing, failed, unknown }
    public let obd: OBD
    public let sync: Sync
    public init(obd: OBD, sync: Sync) { self.obd = obd; self.sync = sync }
    public func context() async -> [FeedbackContextValue] {
        [.init(field: .obdState, code: obd.rawValue, category: .systemDiagnostics),
         .init(field: .syncState, code: sync.rawValue, category: .systemDiagnostics)]
    }
}
