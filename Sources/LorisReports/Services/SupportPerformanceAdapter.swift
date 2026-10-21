import Foundation
#if canImport(MetricKit) && os(iOS)
import MetricKit

/// Reads only diagnostic counts. It never exports call trees, exception text or payload JSON.
/// Event time is the receipt time of a MetricKit summary, not an invented crash timestamp.
@available(iOS 14, *)
public final class SupportMetricKitAdapter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let journal: SupportDiagnosticJournal
    private let lock = NSLock()
    private var registered = false
    public init(journal: SupportDiagnosticJournal) { self.journal = journal }
    public func startAfterConsent() async -> Bool {
        guard await journal.isEnabled else { return false }
        let start = lock.withLock { if registered { return false }; registered = true; return true }
        if start { MXMetricManager.shared.add(self) }
        return true
    }
    public func stop() {
        let stop = lock.withLock { let wasRegistered = registered; registered = false; return wasRegistered }
        if stop { MXMetricManager.shared.remove(self) }
    }
    public func didReceive(_ payloads: [MXMetricPayload]) {}
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        let hangs = payloads.reduce(0) { $0 + ($1.hangDiagnostics?.count ?? 0) }
        let journal = journal
        Task {
            if crashes > 0 { try? await journal.record(.init(correlationID: UUID(), component: .ui, operation: .crash, outcome: .crash, attemptCount: crashes)) }
            if hangs > 0 { try? await journal.record(.init(correlationID: UUID(), component: .ui, operation: .render, outcome: .hang, attemptCount: hangs)) }
        }
    }
}
#endif
