import Foundation

public struct ReportRedactionPipeline: Sendable {
    // Mirror the service's canonical text policy so acknowledgement matching
    // includes its second redaction pass and Unicode compatibility normalization.
    private let rules: [(String, String)] = [
        (#"(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#, "[SECRET REDACTED]"),
        (#"(?im)\b(?:cookie|set-cookie)\s*:\s*[^\r\n]+"#, "[SECRET REDACTED]"),
        (#"(?i)\b(?:authorization\s*:\s*)?bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "[SECRET REDACTED]"),
        (#"(?i)\b(?:authorization|x[-_ ]?api[-_ ]?key|api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|id[-_ ]?token|token|password|passwd|client[-_ ]?secret|secret)\s*[\"']?\s*[:=]\s*[\"']?\s*[^\s,;\"'}\]]{6,}"#, "[SECRET REDACTED]"),
        (#"(?i)\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})\b"#, "[SECRET REDACTED]"),
        (#"\bAKIA[A-Z0-9]{16}\b"#, "[SECRET REDACTED]"),
        (#"\bsk-[A-Za-z0-9_-]{20,}\b"#, "[SECRET REDACTED]"),
        (#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#, "[SECRET REDACTED]"),
        (#"(?i)\b(https?://)[^/\s:@]+:[^@\s/]+@"#, "$1[USERINFO REDACTED]@"),
        (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[EMAIL REDACTED]"),
        (#"(?i)(https?://[^\s?#]+)\?[^\s#]+"#, "$1?[QUERY REDACTED]"),
        (#"/Users/[^/\s]+"#, "/Users/[USER REDACTED]"),
        (#"(?<![0-9])[-+]?\d{1,2}\.\d{4,}\s*[,;]\s*[-+]?\d{1,3}\.\d{4,}(?![0-9])"#, "[LOCATION REDACTED]")
    ]

    public init() {}

    public func redact(_ input: String) -> String {
        rules.reduce(input.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "\0", with: "")) { value, rule in
            value.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
    }

    public func redact(_ envelope: ReportEnvelope) throws -> ReportEnvelope {
        try ReportEnvelope(
            schemaVersion: envelope.version,
            clientReportID: envelope.clientReportID,
            occurredAt: envelope.occurredAt,
            source: envelope.source,
            kind: envelope.kind,
            title: redact(envelope.title),
            description: redact(envelope.description),
            expectedResult: envelope.expectedResult.map(redact),
            actualResult: envelope.actualResult.map(redact),
            reproductionSteps: envelope.reproductionSteps.map(redact),
            app: envelope.app,
            structuredContext: envelope.structuredContext.mapValues(redact),
            contextCategories: envelope.contextCategories,
            artifacts: envelope.artifacts,
            consent: envelope.consent,
            reporter: envelope.reporter
        )
    }
}
