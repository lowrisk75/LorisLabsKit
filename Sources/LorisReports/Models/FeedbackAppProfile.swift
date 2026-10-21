import Foundation

/// Bounded technical codes. User content must never be stored in these fields.
public enum FeedbackContextField: String, CaseIterable, Codable, Sendable {
    case component, operation
    case errorCode = "error_code", durationMilliseconds = "duration_ms", attemptCount = "attempt_count"
    case schedulerState = "scheduler_state", permissionState = "permission_state"
    case streamState = "stream_state", syncState = "sync_state", obdState = "obd_state"
}

public struct FeedbackAppProfile: Sendable {
    public let appID: String
    public let displayName: String
    public let allowedFields: Set<FeedbackContextField>
    public let endpoint: URL

    public init(appID: String, displayName: String, allowedFields: Set<FeedbackContextField>,
                endpoint: URL = URL(string: "https://help.lorislab.fr/")!) {
        self.appID = appID; self.displayName = displayName
        self.allowedFields = allowedFields; self.endpoint = endpoint
    }
    public static let velya = Self(appID: "velya", displayName: "Velya", allowedFields: [.component, .operation, .errorCode, .durationMilliseconds, .attemptCount, .schedulerState, .permissionState])
    public static let lumen = Self(appID: "lumen", displayName: "Lumen", allowedFields: [.component, .operation, .errorCode, .durationMilliseconds, .attemptCount, .streamState])
    public static let eclair = Self(appID: "eclair", displayName: "Éclair", allowedFields: [.component, .operation, .errorCode, .durationMilliseconds, .attemptCount, .syncState, .obdState])
    /// Vif's transfer diagnostics use bounded technical codes, never file or peer metadata.
    /// The host must confirm server enablement before offering report submission.
    public static let vif = Self(appID: "vif", displayName: "Vif", allowedFields: [.component, .operation, .errorCode, .durationMilliseconds, .attemptCount, .permissionState])
}

public struct FeedbackContextValue: Codable, Sendable {
    public let field: FeedbackContextField
    public let code: String
    public let category: ReportDataCategory
    public init(field: FeedbackContextField, code: String, category: ReportDataCategory) {
        self.field = field; self.code = code; self.category = category
    }
}

public protocol DiagnosticContextProvider: Sendable {
    func context() async -> [FeedbackContextValue]
}
