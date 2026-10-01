import Foundation
import XCTest
@testable import LorisReports

final class ReportEnvelopeTests: XCTestCase {
    private let app = ReportAppContext(
        appID: "lumen",
        appVersion: "4.2",
        appBuild: "4021",
        platform: .iOS,
        osVersion: "27.0",
        deviceModel: "iPhone",
        locale: "fr-FR"
    )

    func testConsentMustCoverDescription() {
        XCTAssertThrowsError(try ReportEnvelope(
            schemaVersion: 1,
            kind: .bug,
            title: "Black stream",
            description: "The stream stays black",
            app: app,
            consent: ConsentReceipt(noticeVersion: "v1", categories: [.appMetadata])
        )) { error in
            XCTAssertEqual(error as? ReportEnvelopeError, .missingConsent(.userDescription))
        }
    }

    func testArtifactMustHaveMatchingConsent() {
        let artifact = DiagnosticArtifact(
            filename: "connection.log",
            mediaType: "text/plain",
            sizeBytes: 10,
            sha256: String(repeating: "a", count: 64),
            category: .connectionLogs
        )
        XCTAssertThrowsError(try ReportEnvelope(
            schemaVersion: 1,
            kind: .bug,
            title: "Black stream",
            description: "The stream stays black",
            app: app,
            artifacts: [artifact],
            consent: ConsentReceipt(noticeVersion: "v1", categories: [.userDescription])
        ))
    }

    func testRedactionPreservesReporterButCleansDiagnosticText() throws {
        let envelope = try ReportEnvelope(
            schemaVersion: 1,
            kind: .bug,
            title: "Black stream",
            description: "Authorization: Bearer abcdefghijklmnop from me@example.com",
            app: app,
            consent: ConsentReceipt(
                noticeVersion: "v1",
                categories: [.userDescription, .contactEmail]
            ),
            reporter: ReporterIdentity(email: "me@example.com", emailConfirmed: true)
        )
        let redacted = try ReportRedactionPipeline().redact(envelope)
        XCTAssertTrue(redacted.description.contains("[SECRET REDACTED]"))
        XCTAssertTrue(redacted.description.contains("[EMAIL REDACTED]"))
        XCTAssertEqual(redacted.reporter?.email, "me@example.com")
    }

    func testWireKeysMatchServerContract() throws {
        let envelope = try ReportEnvelope(
            schemaVersion: 1,
            clientReportID: UUID(uuidString: "d9b8553b-bec9-438d-a1fd-e385a3c0322f")!,
            kind: .feedback,
            title: "More filters",
            description: "I would like more filters",
            app: app,
            consent: ConsentReceipt(noticeVersion: "v1", categories: [.userDescription])
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(envelope)) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["client_report_id"] as? String, "D9B8553B-BEC9-438D-A1FD-E385A3C0322F")
        XCTAssertNotNil(object["structured_context"])
    }

    func testPreviewSelectionRemovesEmailAndOptionalArtifact() throws {
        let artifact = DiagnosticArtifact(
            filename: "connection.log",
            mediaType: "text/plain",
            sizeBytes: 10,
            sha256: String(repeating: "a", count: 64),
            category: .connectionLogs
        )
        let envelope = try ReportEnvelope(
            schemaVersion: 1,
            kind: .bug,
            title: "Black stream",
            description: "The stream stays black",
            app: app,
            artifacts: [artifact],
            consent: ConsentReceipt(
                noticeVersion: "v1",
                categories: [.userDescription, .appMetadata, .deviceMetadata, .connectionLogs, .contactEmail]
            ),
            reporter: ReporterIdentity(email: "me@example.com", emailConfirmed: true)
        )
        let selected = try envelope.selecting(categories: [.userDescription, .appMetadata, .deviceMetadata])
        XCTAssertTrue(selected.artifacts.isEmpty)
        XCTAssertNil(selected.reporter)
    }
}
