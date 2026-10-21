import XCTest
import Security
@testable import LorisReports

private final class MemoryTickets: FeedbackTicketStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FeedbackTicket] = []
    func load() throws -> [FeedbackTicket] { lock.withLock { items } }
    func save(_ tickets: [FeedbackTicket]) throws { lock.withLock { items = tickets } }
}

private actor SyntheticSupportHTTP: FeedbackHTTPTransport {
    var paths: [String] = []
    var diagnostics: [Data] = []
    var failDelivery = true
    func allowDelivery() { failDelivery = false }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        let path = request.url!.path; paths.append(path)
        if path == "/v2/apps" { return .init(data: Data(#"{"apps":["lumen"]}"#.utf8), statusCode: 200) }
        if path == "/v2/capabilities" {
            return .init(data: Data(#"{"diagnostic_bundle_versions":[1],"notifications":true,"automatic_erasure":true}"#.utf8), statusCode: 200)
        }
        if path.hasSuffix("/diagnostics") {
            diagnostics.append(request.httpBody!)
            if failDelivery { throw URLError(.notConnectedToInternet) }
        }
        return .init(data: Data("{}".utf8), statusCode: 200)
    }
}

private struct FabricatingAssistant: SupportAssistantEngine {
    func respond(description: String, evidence: [SupportDiagnosticEvent]) async throws -> SupportAssistantReply {
        SupportAssistantReply(question: "Invented?", hypothesis: "Invented cause", citedEventIDs: [UUID()], usedLocalModel: true)
    }
}

final class SupportFeaturesTests: XCTestCase {
    func testExplicitSupportKeychainGroupRejectsVaultNamespace() throws {
        let query = try DeviceOnlyFeedbackTicketStorage(accessGroup: "TESTTEAM.com.lorislab.siliconpass.support", service: "synthetic").query()
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "TESTTEAM.com.lorislab.siliconpass.support")
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertThrowsError(try DeviceOnlyFeedbackTicketStorage(accessGroup: "TESTTEAM.com.lorislab.siliconpass", service: "synthetic").query())
    }
    func testJournalRequiresOptInAndErasesOnRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = SupportDiagnosticJournal(appID: "lumen", directory: root, qualified: true)
        let event = SupportDiagnosticEvent(correlationID: UUID(), component: .stream, operation: .decode, outcome: .timeout)
        try await journal.record(event)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try await journal.setEnabled(true)
        try await journal.record(event)
        let observed = try await journal.snapshot()
        XCTAssertEqual(observed.map(\.id), [event.id])
        try await journal.setEnabled(false)
        let disabled = try await journal.snapshot()
        XCTAssertTrue(disabled.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("local-journal.json").path))
    }
    func testJournalRejectsWrongAppComponentsAndExpiresEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let journal = SupportDiagnosticJournal(appID: "siliconpass", directory: root, qualified: true)
        try await journal.setEnabled(true)
        try await journal.record(.init(correlationID: UUID(), component: .stream, operation: .decode, outcome: .failed))
        try await journal.record(.init(occurredAt: now.addingTimeInterval(-86_401), correlationID: UUID(), component: .unlock, operation: .unlock, outcome: .failed))
        let observed = try await journal.snapshot(now: now)
        XCTAssertTrue(observed.isEmpty)
    }
    func testAssistantRejectsInventedEvidence() async throws {
        let assistant = SupportAssistant(engine: FabricatingAssistant())
        let result = try await assistant.respond(description: "A synthetic operation failed", evidence: [])
        XCTAssertFalse(result.usedLocalModel)
        XCTAssertTrue(result.citedEventIDs.isEmpty)
    }
    func testConstructionDisabledGateHasNoHTTPOrDiskSideEffect() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let http = SyntheticSupportHTTP()
        let client = FeedbackClient(profile: .lumen, configuration: .init(directory: root), transport: http, ticketStorage: MemoryTickets())
        let ticket = FeedbackTicket(reference: "LUMEN-2026-0123456789ABCDEF", trackingToken: "synthetic-only", lastReadMessageID: 0)
        do { _ = try await client.conversation(ticket); XCTFail("Disabled delivery accepted") }
        catch FeedbackClientError.deliveryDisabled {}
        let paths = await http.paths
        XCTAssertTrue(paths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testConsentedDiagnosticRetryKeepsIdentityAndExactPayload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let http = SyntheticSupportHTTP(), storage = MemoryTickets()
        let ticket = FeedbackTicket(reference: "LUMEN-2026-0123456789ABCDEF", trackingToken: "synthetic-only", lastReadMessageID: 0)
        try storage.save([ticket])
        let configuration = FeedbackConfiguration(directory: root, serverAuthorizationApproved: true,
            nativeQualificationApproved: true, features: .init(diagnostics: true))
        let client = FeedbackClient(profile: .lumen, configuration: configuration, transport: http, ticketStorage: storage)
        let bundle = try SupportDiagnosticBundle(appID: "lumen", reviewedEvents: [.init(correlationID: UUID(), component: .stream, operation: .decode, outcome: .timeout)])
        do { try await client.submitReviewedDiagnostics(bundle, to: ticket); XCTFail("Offline delivery accepted") }
        catch is URLError {}
        await http.allowDelivery()
        let relaunched = FeedbackClient(profile: .lumen, configuration: configuration, transport: http, ticketStorage: storage)
        try await relaunched.retryReviewedDiagnostics()
        let bodies = await http.diagnostics
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0], bodies[1])
        try await relaunched.retryReviewedDiagnostics()
        let final = await http.diagnostics
        XCTAssertEqual(final.count, 2)
    }
}
