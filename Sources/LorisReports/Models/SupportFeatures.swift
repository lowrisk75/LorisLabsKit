import Foundation

/// Each capability has its own native qualification gate. Existing messaging is independent.
public struct SupportFeatureConfiguration: Sendable {
    public let diagnostics: Bool
    public let assistant: Bool
    public let notifications: Bool
    public static let disabled = Self()
    public static func forBuild(_ bundle: Bundle = .main) -> Self {
        Self(diagnostics: bundle.object(forInfoDictionaryKey: "LorisReportsDiagnosticsVerified") as? Bool ?? false,
             assistant: bundle.object(forInfoDictionaryKey: "LorisReportsAssistantVerified") as? Bool ?? false,
             notifications: bundle.object(forInfoDictionaryKey: "LorisReportsPushVerified") as? Bool ?? false)
    }
    public init(diagnostics: Bool = false, assistant: Bool = false, notifications: Bool = false) {
        self.diagnostics = diagnostics; self.assistant = assistant; self.notifications = notifications
    }
}

public struct SupportCapabilities: Decodable, Sendable {
    public let diagnosticBundleVersions: [Int]
    public let notifications: Bool
    public let automaticErasure: Bool
    enum CodingKeys: String, CodingKey {
        case diagnosticBundleVersions = "diagnostic_bundle_versions"
        case notifications, automaticErasure = "automatic_erasure"
    }
    public static let unavailable = Self(diagnosticBundleVersions: [], notifications: false, automaticErasure: false)
}

public enum SupportComponent: String, Codable, CaseIterable, Sendable {
    case support, network, permissions, stream, cache, scheduler, sync, autofill, unlock, ui, transfer, pairing, mqtt, engine
}
public enum SupportOperation: String, Codable, CaseIterable, Sendable {
    case connect, discover, pair, transfer, decode, buffer, cache, authorize, schedule, sync, autofill, unlock
    case render, submit, read, retry, delete, crash, launch
}
public enum SupportOutcome: String, Codable, CaseIterable, Sendable {
    case success, failed, timeout, cancelled, unknown, denied, unavailable, conflict, decode, storage, disconnected, crash, hang
}

public struct SupportDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let correlationID: UUID
    public let component: SupportComponent
    public let operation: SupportOperation
    public let outcome: SupportOutcome
    public let durationMilliseconds: Int
    public let attemptCount: Int
    public init(id: UUID = UUID(), occurredAt: Date = Date(), correlationID: UUID, component: SupportComponent,
                operation: SupportOperation, outcome: SupportOutcome, durationMilliseconds: Int = 0, attemptCount: Int = 0) {
        self.id = id; self.occurredAt = occurredAt; self.correlationID = correlationID; self.component = component
        self.operation = operation; self.outcome = outcome
        self.durationMilliseconds = min(3_600_000, max(0, durationMilliseconds)); self.attemptCount = min(100, max(0, attemptCount))
    }
    enum CodingKeys: String, CodingKey {
        case id, component, operation, outcome
        case occurredAt = "occurred_at", correlationID = "correlation_id"
        case durationMilliseconds = "duration_ms", attemptCount = "attempt_count"
    }
}

public enum SupportDiagnosticPolicy {
    public static func components(appID: String) -> Set<SupportComponent> {
        if appID.hasPrefix("com.lorislab.weave.") { return [.support, .network, .permissions, .transfer, .pairing, .ui] }
        switch appID {
        case "lumen": return [.support, .network, .permissions, .stream, .cache, .ui]
        case "velya": return [.support, .permissions, .scheduler, .ui]
        case "siliconpass": return [.support, .permissions, .autofill, .unlock, .sync, .ui]
        case "filova": return [.support, .permissions, .engine, .sync, .ui]
        case "vif": return [.support, .network, .permissions, .transfer, .pairing, .ui]
        case "lumen-bridge": return [.support, .network, .mqtt, .pairing, .ui]
        case "clasp": return [.support, .sync, .ui]
        case "404": return [.support, .network, .permissions, .ui]
        case "typemetrics": return [.support, .engine, .ui]
        case "kernel", "kiosk", "millrace": return [.support, .ui]
        default: return []
        }
    }
}

public struct SupportDiagnosticBundle: Codable, Sendable {
    public let schemaVersion: Int
    public let bundleID: UUID
    public let appID: String
    public let consent: ConsentReceipt
    public let events: [SupportDiagnosticEvent]
    /// Call only after the user has reviewed this exact immutable selection.
    public init(appID: String, reviewedEvents: [SupportDiagnosticEvent], now: Date = Date(), bundleID: UUID = UUID()) throws {
        guard !reviewedEvents.isEmpty, reviewedEvents.count <= 150,
              Set(reviewedEvents.map(\.id)).count == reviewedEvents.count,
              reviewedEvents.allSatisfy({ SupportDiagnosticPolicy.components(appID: appID).contains($0.component)
                  && $0.occurredAt >= now.addingTimeInterval(-86_400) && $0.occurredAt <= now.addingTimeInterval(300) }) else {
            throw FeedbackClientError.invalidReport
        }
        self.schemaVersion = 1; self.bundleID = bundleID; self.appID = appID; self.events = reviewedEvents
        self.consent = ConsentReceipt(noticeVersion: "support-diagnostics-20261005", grantedAt: now,
            categories: [.appMetadata, .systemDiagnostics])
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", bundleID = "bundle_id", appID = "app_id", consent, events
    }
}
