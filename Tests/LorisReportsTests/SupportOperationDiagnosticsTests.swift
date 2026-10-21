import XCTest
@testable import LorisReports

private actor OperationHTTP: FeedbackHTTPTransport {
    var failure: URLError.Code?
    func fail(_ code: URLError.Code?) { failure = code }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        if let failure { throw URLError(failure) }
        return .init(data: Data("{}".utf8), statusCode: 200)
    }
}
private struct OperationTickets: FeedbackTicketStorage {
    func load() -> [FeedbackTicket] { [] }
    func save(_ tickets: [FeedbackTicket]) {}
}

final class SupportOperationDiagnosticsTests: XCTestCase {
    func testSupportOutcomesRequireConsentAndNeverIncludeRequestContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let http = OperationHTTP()
        let client = FeedbackClient(profile: .init(appID: "kernel", displayName: "Kernel", allowedFields: []),
            configuration: .init(directory: root, serverAuthorizationApproved: true, nativeQualificationApproved: true,
                features: .init(diagnostics: true), requiresExactAppAuthorization: false),
            transport: http, ticketStorage: OperationTickets())
        let ticket = FeedbackTicket(reference: "KERNEL-2026-SYNTHETIC", trackingToken: "PRIVATE-TRACKING-TOKEN", lastReadMessageID: 0)
        _ = try await client.request(ticket, suffix: "messages", body: Data("PRIVATE-MESSAGE".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try await client.journal.setEnabled(true)
        _ = try await client.request(ticket, suffix: "messages", body: Data("PRIVATE-MESSAGE".utf8))
        await http.fail(.timedOut)
        do { _ = try await client.request(ticket, suffix: "conversation") ; XCTFail("Timeout must propagate") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        let events = try await client.journal.snapshot()
        XCTAssertEqual(events.map(\.component), [.support, .support])
        XCTAssertEqual(events.map(\.operation), [.submit, .read])
        XCTAssertEqual(events.map(\.outcome), [.success, .timeout])
        XCTAssertEqual(Set(events.map(\.correlationID)).count, 2)
        let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        for secret in [ticket.reference, ticket.trackingToken, "PRIVATE-MESSAGE", "https:", "conversation"] {
            XCTAssertFalse(encoded.contains(secret))
        }
        try await client.journal.setEnabled(false)
        await http.fail(nil)
        _ = try await client.request(ticket, suffix: "activity")
        let revoked = try await client.journal.snapshot()
        XCTAssertTrue(revoked.isEmpty)
    }
}
