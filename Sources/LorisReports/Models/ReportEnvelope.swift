import Foundation

public enum ReportSource: String, Codable, CaseIterable, Sendable {
    case appAPI = "app_api"
    case email
    case appStoreReview = "app_store_review"
    case testflight
    case playReview = "play_review"
    case playVitals = "play_vitals"
    case appStoreDiagnostic = "app_store_diagnostic"
}

public enum ReportKind: String, Codable, CaseIterable, Sendable {
    case bug, feedback, question, crash, billing, privacy
    case featureRequest = "feature_request"
}

public enum ReportPlatform: String, Codable, Sendable {
    case iOS = "ios"
    case iPadOS = "ipados"
    case macOS = "macos"
    case visionOS = "visionos"
    case android
    case other
}

public enum ReportDataCategory: String, Codable, CaseIterable, Sendable {
    case userDescription = "user_description"
    case appMetadata = "app_metadata"
    case deviceMetadata = "device_metadata"
    case connectionLogs = "connection_logs"
    case systemDiagnostics = "system_diagnostics"
    case screenshot
    case contactEmail = "contact_email"
    case remoteAI = "remote_ai"
}

public struct ConsentReceipt: Codable, Equatable, Sendable {
    public let noticeVersion: String
    public let grantedAt: Date
    public let categories: Set<ReportDataCategory>
    public let remoteAIAllowed: Bool

    public init(
        noticeVersion: String,
        grantedAt: Date = Date(),
        categories: Set<ReportDataCategory>,
        remoteAIAllowed: Bool = false
    ) {
        self.noticeVersion = noticeVersion
        self.grantedAt = grantedAt
        self.categories = categories
        self.remoteAIAllowed = remoteAIAllowed
    }

    enum CodingKeys: String, CodingKey {
        case noticeVersion = "notice_version"
        case grantedAt = "granted_at"
        case categories
        case remoteAIAllowed = "remote_ai_allowed"
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(noticeVersion, forKey: .noticeVersion)
        try values.encode(grantedAt, forKey: .grantedAt)
        try values.encode(categories.sorted { $0.rawValue < $1.rawValue }, forKey: .categories)
        try values.encode(remoteAIAllowed, forKey: .remoteAIAllowed)
    }
}

public struct DiagnosticArtifact: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let filename: String
    public let mediaType: String
    public let sizeBytes: Int
    public let sha256: String
    public let category: ReportDataCategory
    public let retentionDays: Int

    public init(
        id: UUID = UUID(),
        filename: String,
        mediaType: String,
        sizeBytes: Int,
        sha256: String,
        category: ReportDataCategory,
        retentionDays: Int = 90
    ) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.category = category
        self.retentionDays = retentionDays
    }

    enum CodingKeys: String, CodingKey {
        case id = "artifact_id"
        case filename
        case mediaType = "media_type"
        case sizeBytes = "size_bytes"
        case sha256, category
        case retentionDays = "retention_days"
    }
}

public struct ReportAppContext: Codable, Equatable, Sendable {
    public let appID: String
    public let appVersion: String
    public let appBuild: String
    public let platform: ReportPlatform
    public let osVersion: String
    public let deviceModel: String?
    public let locale: String?

    public init(
        appID: String,
        appVersion: String,
        appBuild: String,
        platform: ReportPlatform,
        osVersion: String,
        deviceModel: String? = nil,
        locale: String? = nil
    ) {
        self.appID = appID
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.platform = platform
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case locale
    }
}

public struct ReporterIdentity: Codable, Equatable, Sendable {
    public let email: String
    public let emailConfirmed: Bool

    public init(email: String, emailConfirmed: Bool) {
        self.email = email
        self.emailConfirmed = emailConfirmed
    }

    enum CodingKeys: String, CodingKey {
        case email
        case emailConfirmed = "email_confirmed"
    }
}

public struct ReportEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 2

    public let version: Int
    public let clientReportID: UUID
    public let occurredAt: Date?
    public let source: ReportSource
    public let kind: ReportKind
    public let title: String
    public let description: String
    public let expectedResult: String?
    public let actualResult: String?
    public let reproductionSteps: [String]
    public let app: ReportAppContext
    public let structuredContext: [String: String]
    public let contextCategories: [String: ReportDataCategory]
    public let artifacts: [DiagnosticArtifact]
    public let consent: ConsentReceipt
    public let reporter: ReporterIdentity?

    public init(
        schemaVersion: Int = ReportEnvelope.schemaVersion,
        clientReportID: UUID = UUID(),
        occurredAt: Date? = nil,
        source: ReportSource = .appAPI,
        kind: ReportKind,
        title: String,
        description: String,
        expectedResult: String? = nil,
        actualResult: String? = nil,
        reproductionSteps: [String] = [],
        app: ReportAppContext,
        structuredContext: [String: String] = [:],
        contextCategories: [String: ReportDataCategory] = [:],
        artifacts: [DiagnosticArtifact] = [],
        consent: ConsentReceipt,
        reporter: ReporterIdentity? = nil
    ) throws {
        guard consent.categories.contains(.userDescription) else {
            throw ReportEnvelopeError.missingConsent(.userDescription)
        }
        if reporter != nil && !consent.categories.contains(.contactEmail) {
            throw ReportEnvelopeError.missingConsent(.contactEmail)
        }
        if reporter?.emailConfirmed == false {
            throw ReportEnvelopeError.unconfirmedEmail
        }
        for artifact in artifacts where !consent.categories.contains(artifact.category) {
            throw ReportEnvelopeError.missingConsent(artifact.category)
        }
        if consent.remoteAIAllowed && !consent.categories.contains(.remoteAI) {
            throw ReportEnvelopeError.missingConsent(.remoteAI)
        }
        guard (1...2).contains(schemaVersion) else { throw ReportEnvelopeError.invalidSchema }
        if schemaVersion == 2 {
            guard consent.categories.contains(.appMetadata) else { throw ReportEnvelopeError.missingConsent(.appMetadata) }
            guard Set(structuredContext.keys) == Set(contextCategories.keys) else { throw ReportEnvelopeError.unclassifiedContext }
            for (key, category) in contextCategories {
                guard consent.categories.contains(category), [.connectionLogs, .systemDiagnostics].contains(category),
                      FeedbackContextField.allCases.map(\.rawValue).contains(key),
                      let value = structuredContext[key],
                      value.range(of: "^[a-zA-Z0-9_.-]{1,64}$", options: .regularExpression) != nil
                else { throw ReportEnvelopeError.unclassifiedContext }
            }
            guard reporter == nil else { throw ReportEnvelopeError.unverifiedContact }
            if app.deviceModel != nil && !consent.categories.contains(.deviceMetadata) { throw ReportEnvelopeError.missingConsent(.deviceMetadata) }
        }
        self.version = schemaVersion
        self.clientReportID = clientReportID
        self.occurredAt = occurredAt
        self.source = source
        self.kind = kind
        self.title = title
        self.description = description
        self.expectedResult = expectedResult
        self.actualResult = actualResult
        self.reproductionSteps = reproductionSteps
        self.app = app
        self.structuredContext = structuredContext
        self.contextCategories = contextCategories
        self.artifacts = artifacts
        self.consent = consent
        self.reporter = reporter
    }

    enum CodingKeys: String, CodingKey {
        case version = "schema_version"
        case clientReportID = "client_report_id"
        case occurredAt = "occurred_at"
        case source, kind, title, description
        case expectedResult = "expected_result"
        case actualResult = "actual_result"
        case reproductionSteps = "reproduction_steps"
        case app
        case structuredContext = "structured_context"
        case contextCategories = "context_categories"
        case artifacts, consent, reporter
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: values.decode(Int.self, forKey: .version),
            clientReportID: values.decode(UUID.self, forKey: .clientReportID),
            occurredAt: values.decodeIfPresent(Date.self, forKey: .occurredAt),
            source: values.decode(ReportSource.self, forKey: .source),
            kind: values.decode(ReportKind.self, forKey: .kind),
            title: values.decode(String.self, forKey: .title),
            description: values.decode(String.self, forKey: .description),
            expectedResult: values.decodeIfPresent(String.self, forKey: .expectedResult),
            actualResult: values.decodeIfPresent(String.self, forKey: .actualResult),
            reproductionSteps: values.decodeIfPresent([String].self, forKey: .reproductionSteps) ?? [],
            app: values.decode(ReportAppContext.self, forKey: .app),
            structuredContext: values.decodeIfPresent([String: String].self, forKey: .structuredContext) ?? [:],
            contextCategories: values.decodeIfPresent([String: ReportDataCategory].self, forKey: .contextCategories) ?? [:],
            artifacts: values.decodeIfPresent([DiagnosticArtifact].self, forKey: .artifacts) ?? [],
            consent: values.decode(ConsentReceipt.self, forKey: .consent),
            reporter: values.decodeIfPresent(ReporterIdentity.self, forKey: .reporter)
        )
    }

    /// Rebuilds the immutable envelope from the exact categories selected in the preview.
    /// Mandatory narrative/app fields remain present; optional artifacts and email are removed.
    public func selecting(categories: Set<ReportDataCategory>, at date: Date = Date()) throws -> ReportEnvelope {
        try ReportEnvelope(
            schemaVersion: version,
            clientReportID: clientReportID,
            occurredAt: occurredAt,
            source: source,
            kind: kind,
            title: title,
            description: description,
            expectedResult: expectedResult,
            actualResult: actualResult,
            reproductionSteps: reproductionSteps,
            app: ReportAppContext(appID: app.appID, appVersion: app.appVersion, appBuild: app.appBuild,
                platform: app.platform, osVersion: app.osVersion,
                deviceModel: categories.contains(.deviceMetadata) ? app.deviceModel : nil, locale: app.locale),
            structuredContext: structuredContext.filter { categories.contains(contextCategories[$0.key] ?? .connectionLogs) },
            contextCategories: contextCategories.filter { categories.contains($0.value) },
            artifacts: artifacts.filter { categories.contains($0.category) },
            consent: ConsentReceipt(
                noticeVersion: consent.noticeVersion,
                grantedAt: date,
                categories: categories,
                remoteAIAllowed: consent.remoteAIAllowed && categories.contains(.remoteAI)
            ),
            reporter: categories.contains(.contactEmail) ? reporter : nil
        )
    }
}

public enum ReportEnvelopeError: Error, Equatable, Sendable {
    case missingConsent(ReportDataCategory)
    case invalidSchema, unclassifiedContext, unverifiedContact
    case unconfirmedEmail
}
