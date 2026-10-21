import Foundation
import XCTest
@testable import LorisReports

/// Records every request; answers challenges and uploads with configurable bodies.
private actor RecordingTransport: FeedbackHTTPTransport {
    var requests: [URLRequest] = []
    var challenge = "synthetic-challenge-0123456789"
    func setChallenge(_ value: String) { challenge = value }
    func captured() -> [URLRequest] { requests }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        requests.append(request)
        XCTAssertLessThanOrEqual(maximumBytes, 64 * 1024, "diagnostic uploads must stay bounded")
        switch request.url?.path {
        case "/v2/challenges": return .init(data: try JSONEncoder().encode(["challenge": challenge]), statusCode: 200)
        case "/v2/diagnostics": return .init(data: Data("{}".utf8), statusCode: 202)
        case "/v2/diagnostics/deletion-requests": return .init(data: Data(#"{"status":"completed"}"#.utf8), statusCode: 202)
        default: return .init(data: Data(), statusCode: 404)
        }
    }
}

/// Covers the FeedbackV2.md guarantees that previously had no executable proof.
final class SecurityContractTests: XCTestCase, @unchecked Sendable {
    private let profile = FeedbackAppProfile.velya
    private let app = ReportAppContext(appID: "velya", appVersion: "1.0", appBuild: "1", platform: .macOS, osVersion: "test")

    private func temporaryDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SecurityContract-\(name)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func journal(_ directory: URL, transport: RecordingTransport) async -> DiagnosticJournal {
        let journal = DiagnosticJournal(profile: profile, directory: directory, transport: transport)
        await journal.useSyntheticDeletionToken("synthetic-deletion-token")
        return journal
    }
    private func message(_ url: String?) throws -> FeedbackMessage {
        let beta = url.map { #", "beta_url": "\#($0)""# } ?? ""
        let json = #"{"id":1,"client_message_id":"00000000-0000-0000-0000-000000000001","author":"team","kind":"beta","body":"","created_at":"2026-10-07T00:00:00Z"\#(beta)}"#
        return try JSONDecoder().decode(FeedbackMessage.self, from: Data(json.utf8))
    }

    // MARK: Beta invitation URL

    func testBetaURLAcceptsOnlyApplePublicInvitationFormat() throws {
        XCTAssertEqual(try message("https://testflight.apple.com/join/AbC123xyz").validatedBetaURL?.absoluteString,
                       "https://testflight.apple.com/join/AbC123xyz")
        let rejected = [
            "http://testflight.apple.com/join/AbC123",
            "https://testflight.apple.com.evil.invalid/join/AbC123",
            "https://evil.invalid/testflight.apple.com/join/AbC123",
            "https://user:pass@testflight.apple.com/join/AbC123",
            "https://testflight.apple.com:8443/join/AbC123",
            "https://testflight.apple.com/join/AbC123?ref=x",
            "https://testflight.apple.com/join/AbC123#frag",
            "https://testflight.apple.com/join/",
            "https://testflight.apple.com/join/../AbC123",
            "https://testflight.apple.com/join/AbC-123",
            "https://testflight.apple.com/v1/invite/AbC123",
            "https://TESTFLIGHT.APPLE.COM/join/AbC123",
        ]
        for candidate in rejected {
            XCTAssertNil(try message(candidate).validatedBetaURL, candidate)
        }
        XCTAssertNil(try message(nil).validatedBetaURL)
    }

    // MARK: Diagnostic journal

    func testRecordNeverTouchesNetworkAndEnforcesBounds() async throws {
        let transport = RecordingTransport()
        let journal = await journal(temporaryDirectory("record"), transport: transport)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await journal.setEnabled(true, now: start)
        try await journal.record(field: .schedulerState, code: "stale", now: start)
        let fresh = start.addingTimeInterval(2 * 86_400)
        for index in 0..<1_200 {
            try await journal.record(field: .schedulerState, code: "confirmed_\(index)", now: fresh.addingTimeInterval(Double(index)))
        }
        let last = fresh.addingTimeInterval(1_199)
        try await journal.record(field: .streamState, code: "not-allowed-for-velya", now: last)
        try await journal.record(field: .schedulerState, code: "bad code with spaces", now: last)
        try await journal.record(field: .schedulerState, code: "/Users/someone/secret", now: last)
        let afterRecording = await transport.captured()
        XCTAssertTrue(afterRecording.isEmpty, "record() must have no network side effect")

        try await journal.flush(app: app, now: last)
        let requests = await transport.captured()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v2/challenges", "/v2/diagnostics"])
        let upload = requests[1]
        XCTAssertEqual(upload.value(forHTTPHeaderField: "X-Diagnostic-Deletion-Token"), "synthetic-deletion-token")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "X-Feedback-Challenge"), "synthetic-challenge-0123456789")
        XCTAssertNil(upload.url?.query, "secrets and identifiers never travel in the URL")
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(upload.httpBody)) as? [String: Any])
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        let codes = Set(events.compactMap { $0["code"] as? String })
        XCTAssertEqual(events.count, 1_000, "only the newest 1,000 events are kept")
        XCTAssertFalse(codes.contains("stale"), "events older than 24 h are pruned")
        XCTAssertFalse(codes.contains("confirmed_0"))
        XCTAssertTrue(codes.contains("confirmed_1199"))
        XCTAssertFalse(codes.contains { $0.contains("secret") || $0.contains(" ") })
        XCTAssertFalse(events.contains { $0["field"] as? String == "stream_state" })
        XCTAssertNil(payload["device_model"]); XCTAssertNil((payload["app"] as? [String: Any])?["device_model"])
    }

    func testFlushRejectsMalformedChallengeWithoutUploading() async throws {
        let transport = RecordingTransport()
        await transport.setChallenge("<script>alert(1)</script>\r\nX-Injected: 1")
        let journal = await journal(temporaryDirectory("challenge"), transport: transport)
        try await journal.setEnabled(true)
        try await journal.record(field: .schedulerState, code: "confirmed")
        do { try await journal.flush(app: app); XCTFail("malformed challenge accepted") }
        catch ReportTransportError.invalidResponse { }
        let requests = await transport.captured()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v2/challenges"])
    }

    func testFlushIgnoresForeignAppAndDisabledJournal() async throws {
        let transport = RecordingTransport()
        let journal = await journal(temporaryDirectory("foreign"), transport: transport)
        try await journal.record(field: .schedulerState, code: "confirmed")
        try await journal.flush(app: app)
        try await journal.setEnabled(true)
        try await journal.record(field: .schedulerState, code: "confirmed")
        let foreign = ReportAppContext(appID: "lumen", appVersion: "1.0", appBuild: "1", platform: .macOS, osVersion: "test")
        try await journal.flush(app: foreign)
        let requests = await transport.captured()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDisablingClearsQueueAndOversizedStateFileIsIgnored() async throws {
        let directory = temporaryDirectory("disable")
        let transport = RecordingTransport()
        let journal = await journal(directory, transport: transport)
        try await journal.setEnabled(true)
        try await journal.record(field: .schedulerState, code: "confirmed")
        try await journal.setEnabled(false)
        try await journal.flush(app: app)
        let requests = await transport.captured()
        XCTAssertTrue(requests.isEmpty, "disabling must cancel pending uploads")
        let isEnabled = await journal.isEnabled
        XCTAssertFalse(isEnabled)

        let file = directory.appendingPathComponent("diagnostics.json")
        try Data(repeating: 0x20, count: DiagnosticJournal.maximumStateBytes + 1).write(to: file)
        let reloaded = DiagnosticJournal(profile: profile, directory: directory, transport: transport)
        let reloadedEnabled = await reloaded.isEnabled
        XCTAssertFalse(reloadedEnabled, "an oversized state file is never decoded")
    }

    func testJournalIsInertWhenCollectionIsNotAllowed() async throws {
        let transport = RecordingTransport()
        let journal = DiagnosticJournal(profile: profile, directory: temporaryDirectory("inert"), collectionAllowed: false, transport: transport)
        await journal.useSyntheticDeletionToken("synthetic")
        do { try await journal.setEnabled(true); XCTFail("collection enabled without qualification") }
        catch FeedbackClientError.featureDisabled { }
        try await journal.record(field: .schedulerState, code: "confirmed")
        try await journal.flush(app: app)
        let requests = await transport.captured()
        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: Transport endpoint policy

    func testNativeTransportRefusesInsecureOrCredentialedEndpoints() async {
        let transport = NativeFeedbackHTTPTransport()
        let endpoints = ["http://help.lorislab.fr/v2/apps", "https://user:pass@help.lorislab.fr/v2/apps", "file:///etc/hosts"]
        for endpoint in endpoints {
            let request = URLRequest(url: URL(string: endpoint)!)
            do { _ = try await transport.send(request, maximumBytes: 1024); XCTFail("accepted \(endpoint)") }
            catch ReportTransportError.invalidEndpoint { }
            catch { XCTFail("unexpected error for \(endpoint): \(error)") }
        }
        do { _ = try await transport.send(URLRequest(url: URL(string: "https://synthetic.invalid/")!), maximumBytes: 1024 * 1024); XCTFail("unbounded read accepted") }
        catch ReportTransportError.invalidResponse { }
        catch { XCTFail("unexpected error: \(error)") }
    }

    // MARK: Outbox bound

    func testOutboxRefusesMoreThanTenMebibytes() async throws {
        let outbox = FeedbackOutbox(directory: temporaryDirectory("outbox"))
        let consent = ConsentReceipt(noticeVersion: "synthetic", categories: [.userDescription, .appMetadata])
        let large = String(repeating: "a", count: 6 * 1024 * 1024)
        _ = try await outbox.enqueue(try ReportEnvelope(schemaVersion: 2, kind: .bug, title: "one", description: large, app: app, consent: consent))
        do {
            _ = try await outbox.enqueue(try ReportEnvelope(schemaVersion: 2, kind: .bug, title: "two", description: large, app: app, consent: consent))
            XCTFail("outbox exceeded 10 MiB")
        } catch FeedbackOutboxError.full { }
    }

    // MARK: userTextOnly

    func testUserTextOnlyClientRejectsContextAndDeviceMetadata() async throws {
        let transport = RecordingTransport()
        let configuration = FeedbackConfiguration(directory: temporaryDirectory("textonly"), serverAuthorizationApproved: true,
            nativeQualificationApproved: true, userTextOnly: true, requiresExactAppAuthorization: false)
        let client = FeedbackClient(profile: profile, configuration: configuration, transport: transport, ticketStorage: MemoryTickets())
        let withContext = try ReportEnvelope(schemaVersion: 2, kind: .bug, title: "t", description: "d", app: app,
            structuredContext: ["scheduler_state": "confirmed"], contextCategories: ["scheduler_state": .systemDiagnostics],
            consent: .init(noticeVersion: "synthetic", categories: [.userDescription, .appMetadata, .systemDiagnostics]))
        do { _ = try await client.submit(withContext); XCTFail("context accepted") } catch FeedbackClientError.invalidReport { }
        let withDevice = try ReportEnvelope(schemaVersion: 2, kind: .bug, title: "t", description: "d",
            app: ReportAppContext(appID: "velya", appVersion: "1.0", appBuild: "1", platform: .macOS, osVersion: "test", deviceModel: "Mac"),
            consent: .init(noticeVersion: "synthetic", categories: [.userDescription, .appMetadata, .deviceMetadata]))
        do { _ = try await client.submit(withDevice); XCTFail("device metadata accepted") } catch FeedbackClientError.invalidReport { }
        let requests = await transport.captured()
        XCTAssertTrue(requests.isEmpty, "rejected reports never reach the network")
    }
}

private final class MemoryTickets: FeedbackTicketStorage, @unchecked Sendable {
    let lock = NSLock(); var tickets: [FeedbackTicket] = []
    func load() -> [FeedbackTicket] { lock.withLock { tickets } }
    func save(_ tickets: [FeedbackTicket]) { lock.withLock { self.tickets = tickets } }
}
