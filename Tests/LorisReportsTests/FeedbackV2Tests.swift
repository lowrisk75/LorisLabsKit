import XCTest
@testable import LorisReports
final class FeedbackV2Tests: XCTestCase {
    private func envelope() throws -> ReportEnvelope {
        try ReportEnvelope(schemaVersion: 2, kind: .bug, title: "Alarm stopped", description: "Unexpected state",
            app: ReportAppContext(appID: "velya", appVersion: "1", appBuild: "1", platform: .iOS, osVersion: "26"),
            structuredContext: ["scheduler_state": "armed"], contextCategories: ["scheduler_state": .systemDiagnostics],
            consent: ConsentReceipt(noticeVersion: "test", categories: [.userDescription, .appMetadata, .systemDiagnostics]))
    }
    func testCategoryRemovalActuallyRemovesContext() throws {
        let selected = try envelope().selecting(categories: [.userDescription, .appMetadata])
        XCTAssertEqual(selected.version, 2)
        XCTAssertTrue(selected.structuredContext.isEmpty)
        XCTAssertTrue(selected.contextCategories.isEmpty)
        XCTAssertEqual(try ReportRedactionPipeline().redact(selected).version, 2)
    }
    func testOutboxSurvivesRecreationAndExpires() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try envelope()
        try await FeedbackOutbox(directory: dir).enqueue(report)
        let restored = FeedbackOutbox(directory: dir)
        let pending = try await restored.pending()
        XCTAssertEqual(pending.map(\.clientReportID), [report.clientReportID])
        let expired = try await restored.pending(now: report.consent.grantedAt.addingTimeInterval(8 * 86_400))
        XCTAssertTrue(expired.isEmpty)
    }
    func testOutboxPreservesIndependentReceiptRecoveryCapability() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try envelope()
        let first = FeedbackOutbox(directory: dir)
        let token = try await first.enqueue(report)
        let second = FeedbackOutbox(directory: dir)
        let restored = try await second.pendingDeliveries()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].envelope, report)
        XCTAssertEqual(restored[0].recoveryToken, token)
        XCTAssertGreaterThanOrEqual(token.utf8.count, 32)
    }
    func testOutboxCancel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let box = FeedbackOutbox(directory: dir), report = try envelope()
        try await box.enqueue(report); try await box.remove(report.clientReportID)
        let pending = try await box.pending(); XCTAssertTrue(pending.isEmpty)
    }
    func testCorruptOutboxEntryIsQuarantinedWithoutBlockingHealthyReports() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try envelope()
        let box = FeedbackOutbox(directory: dir)
        try await box.enqueue(report)
        let corruptID = UUID()
        let corruptURL = dir.appendingPathComponent(corruptID.uuidString.lowercased() + ".json")
        try Data("not-json".utf8).write(to: corruptURL, options: .atomic)

        let pending = try await box.pending()

        XCTAssertEqual(pending.map(\.clientReportID), [report.clientReportID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("corrupt").appendingPathComponent(corruptURL.lastPathComponent).path
        ))
    }
    func testLegacyEnvelopeDecodesWithoutCategoryMap() throws {
        let legacy = try ReportEnvelope(schemaVersion: 1, kind: .question, title: "Help", description: "How does this work?",
            app: ReportAppContext(appID: "lumen", appVersion: "1", appBuild: "1", platform: .iOS, osVersion: "26"),
            consent: ConsentReceipt(noticeVersion: "legacy", categories: [.userDescription, .appMetadata]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "context_categories")
        let decoded = try JSONDecoder().decode(ReportEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, legacy)
    }
    func testDecodedV2CannotBypassConsentValidation() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope())) as? [String: Any])
        json["context_categories"] = [:] as [String: String]
        XCTAssertThrowsError(try JSONDecoder().decode(ReportEnvelope.self, from: JSONSerialization.data(withJSONObject: json)))
    }

}
