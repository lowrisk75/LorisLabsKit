import XCTest
@testable import LorisReports

private actor RetryReportHTTP: FeedbackHTTPTransport {
    var offline = true
    var submissions: [URLRequest] = []
    func setOnline() { offline = false }
    func captured() -> [URLRequest] { submissions }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        if request.url?.path == "/v2/apps" { return .init(data: Data(#"{"apps":["filova"]}"#.utf8), statusCode: 200) }
        if request.url?.path == "/v2/challenges" { return .init(data: Data(#"{"challenge":"synthetic-only"}"#.utf8), statusCode: 200) }
        submissions.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        return .init(data: Data(#"{"public_reference":"FILOV-2026-SYNTHETIC","tracking_token":"synthetic-only","received_at":"2026-10-06T10:00:00Z","duplicate":false,"raw_expires_at":"2026-12-06T10:00:00Z"}"#.utf8), statusCode: 201)
    }
}
private final class RetryReportTickets: FeedbackTicketStorage, @unchecked Sendable {
    let lock = NSLock(); var tickets: [FeedbackTicket] = []
    func load() -> [FeedbackTicket] { lock.withLock { tickets } }
    func save(_ tickets: [FeedbackTicket]) { lock.withLock { self.tickets = tickets } }
}
final class ConfirmedReportRetryTests: XCTestCase, @unchecked Sendable {
    private func check(_ description: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FilovaReportRetry-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RetryReportHTTP(), tickets = RetryReportTickets()
        let profile = FeedbackAppProfile(appID: "filova", displayName: "Synthetic", allowedFields: [])
        let config = FeedbackConfiguration(directory: directory, serverAuthorizationApproved: true, nativeQualificationApproved: true)
        let report = try ReportEnvelope(schemaVersion: 2, kind: .question, title: "Synthetic only", description: description,
            app: .init(appID: "filova", appVersion: "test", appBuild: "0", platform: .macOS, osVersion: "test"),
            consent: .init(noticeVersion: "synthetic", categories: [.userDescription, .appMetadata]))
        let first = FeedbackClient(profile: profile, configuration: config, transport: transport, ticketStorage: tickets)
        do { _ = try await first.submit(report); XCTFail("Offline") } catch is URLError { }
        let restored = FeedbackClient(profile: profile, configuration: config, transport: transport, ticketStorage: tickets)
        await transport.setOnline(); try await restored.retryPending()
        let submissions = await transport.captured(); XCTAssertEqual(submissions.count, 2)
        XCTAssertEqual(submissions[0].httpBody, submissions[1].httpBody)
        XCTAssertEqual(submissions[0].value(forHTTPHeaderField: "X-Receipt-Recovery-Token"), submissions[1].value(forHTTPHeaderField: "X-Receipt-Recovery-Token"))
        XCTAssertEqual(submissions[0].value(forHTTPHeaderField: "Idempotency-Key"), submissions[1].value(forHTTPHeaderField: "Idempotency-Key"))
        let pending = try await restored.pendingReports(); XCTAssertTrue(pending.isEmpty)
    }
    func testConfirmedReportRetainsPayloadAfterOfflineRelaunch() async throws { try await check("Synthetic password=synthetic-only") }
    func testConfirmedURLReportRetainsPayloadAfterOfflineRelaunch() async throws { try await check("Synthetic https://synthetic.invalid/path?key=synthetic-only") }
}
