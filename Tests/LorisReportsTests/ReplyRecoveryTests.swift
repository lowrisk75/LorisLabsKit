import Foundation
import XCTest
@testable import LorisReports

private final class RecoveryTickets: FeedbackTicketStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FeedbackTicket]
    init(_ ticket: FeedbackTicket) { items = [ticket] }
    func load() -> [FeedbackTicket] { lock.withLock { items } }
    func save(_ tickets: [FeedbackTicket]) { lock.withLock { items = tickets } }
}
private actor ReplyServer: FeedbackHTTPTransport {
    var stored: [[String: Any]] = []
    var version = 1
    var attempts: [Data] = []
    var calls: [String] = []
    var loseAfterAccept = false
    var offlineBeforeAccept = false
    var revoked = false
    var deletion = "not_requested"
    var holding = false
    var started = false
    var held: CheckedContinuation<Void, Never>?
    var malformedPagination = false
    func startHolding() { holding = true }
    func didStart() -> Bool { started }
    func release() { holding = false; held?.resume(); held = nil }
    func breakPagination() { malformedPagination = true }
    func configure(loseAfterAccept: Bool = false, offlineBeforeAccept: Bool = false, revoked: Bool = false) {
        self.loseAfterAccept = loseAfterAccept; self.offlineBeforeAccept = offlineBeforeAccept; self.revoked = revoked
    }
    func changeVersion() { version += 1 }
    func setDeletion(_ value: String) { deletion = value }
    func snapshot() -> (Int, [Data], [String]) { (stored.count, attempts, calls) }
    func message(_ payload: [String: Any]) -> [String: Any] {
        ["id": stored.count + 1, "client_message_id": payload["client_message_id"]!, "author": "user",
         "kind": payload["kind"]!, "body": ReportRedactionPipeline().redact(payload["body"] as! String), "created_at": "2026-10-06T10:00:00Z"]
    }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        let path = request.url!.path; calls.append((request.httpMethod ?? "GET") + " " + path)
        if path == "/v2/apps" { return .init(data: Data(#"{"apps":["filova"]}"#.utf8), statusCode: 200) }
        if revoked { return .init(data: Data(), statusCode: 410) }
        let encoder: ([String: Any], Int) throws -> FeedbackHTTPResponse = { .init(data: try JSONSerialization.data(withJSONObject: $0), statusCode: $1) }
        if path.hasSuffix("/deletion-status") { return try encoder(["status": deletion], 200) }
        if path.hasSuffix("/deletion-requests") { deletion = "pending"; return try encoder(["status": deletion], 202) }
        if path.hasSuffix("/conversation") {
            if malformedPagination { return try encoder(["public_reference": "FILOV-2026-RECOVERY", "title": "Synthetic", "description": "Synthetic", "state": "open", "version": version, "messages": [], "has_more": true], 200) }
            return try encoder(["public_reference": "FILOV-2026-RECOVERY", "title": "Synthetic", "description": "Synthetic only",
                "state": stored.last?["kind"] as? String == "resolved" ? "resolved" : "open", "version": version,
                "messages": stored, "has_more": false], 200)
        }
        if path.hasSuffix("/messages") {
            let data = request.httpBody!; attempts.append(data)
            if offlineBeforeAccept { throw URLError(.notConnectedToInternet) }
            if holding { started = true; await withCheckedContinuation { held = $0 } }
            let payload = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if let previous = stored.first(where: { $0["client_message_id"] as? String == payload["client_message_id"] as? String }) {
                guard previous["body"] as? String == ReportRedactionPipeline().redact(payload["body"] as! String),
                      previous["kind"] as? String == payload["kind"] as? String else { return .init(data: Data(), statusCode: 409) }
                return try encoder(previous, 201)
            }
            guard payload["expected_version"] as? Int == version else { return .init(data: Data(), statusCode: 409) }
            let value = message(payload); stored.append(value); version += 1
            if loseAfterAccept { throw URLError(.networkConnectionLost) }
            return try encoder(value, 201)
        }
        throw URLError(.unsupportedURL)
    }
}

final class ReplyRecoveryTests: XCTestCase, @unchecked Sendable {
    let ticket = FeedbackTicket(reference: "FILOV-2026-RECOVERY", trackingToken: "synthetic-capability-must-stay-off-disk", lastReadMessageID: 0)
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("reply-recovery-" + UUID().uuidString) }
    private func client(root: URL, server: ReplyServer, tickets: RecoveryTickets) -> FeedbackClient {
        FeedbackClient(profile: .init(appID: "filova", displayName: "Synthetic", allowedFields: []),
            configuration: .init(directory: root, keychainAccessGroup: "TESTTEAM.com.lorislab.filova.support", serverAuthorizationApproved: true, nativeQualificationApproved: true, features: .init(diagnostics: true, assistant: true, notifications: true)),
            transport: server, ticketStorage: tickets)
    }
    func testLostReplyAcknowledgementRelaunchReconcilesWithoutAnotherPost() async throws {
        for kind in ["message", "resolved", "reopened"] {
            let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
            defer { try? FileManager.default.removeItem(at: root) }
            await server.configure(loseAfterAccept: true)
            let first = client(root: root, server: server, tickets: storage), id = UUID()
            do { try await first.reply("Synthetic password=abcdefghi", to: ticket, version: 1, clientMessageID: id, kind: kind); XCTFail("Lost acknowledgement") }
            catch let error as URLError { XCTAssertEqual(error.code, .networkConnectionLost) }
            let file = root.appendingPathComponent("replies/FILOV-2026-RECOVERY.json")
            let persisted = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(persisted.contains(ticket.trackingToken)); XCTAssertFalse(persisted.contains("abcdefghi"))
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o600)
            await server.configure()
            let restored = client(root: root, server: server, tickets: storage)
            let operation = try await restored.pendingReply(for: ticket)
            XCTAssertEqual(operation?.id, id); XCTAssertEqual(operation?.kind, kind)
            try await restored.retryPendingReply(ticket)
            let result = await server.snapshot(); XCTAssertEqual(result.0, 1); XCTAssertEqual(result.1.count, 1)
            let pending = try await restored.pendingReply(for: ticket); XCTAssertNil(pending)
        }
    }
    func testOfflineBeforeAcceptanceRelaunchRetriesExactPayloadAfterRead() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
        defer { try? FileManager.default.removeItem(at: root) }
        await server.configure(offlineBeforeAccept: true)
        let first = client(root: root, server: server, tickets: storage)
        do { try await first.reply("Synthetic reply", to: ticket, version: 1, clientMessageID: UUID()); XCTFail("Offline") }
        catch is URLError { }
        await server.configure()
        let restored = client(root: root, server: server, tickets: storage)
        try await restored.retryPendingReply(ticket)
        let result = await server.snapshot()
        XCTAssertEqual(result.0, 1); XCTAssertEqual(result.1.count, 2); XCTAssertEqual(result.1[0], result.1[1])
        let read = try XCTUnwrap(result.2.lastIndex(of: "GET /v2/reports/FILOV-2026-RECOVERY/conversation"))
        let post = try XCTUnwrap(result.2.lastIndex(of: "POST /v2/reports/FILOV-2026-RECOVERY/messages"))
        XCTAssertLessThan(read, post)
    }
    func testUncertainOperationCannotBeReplacedOrRebasedAfterConflict() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket), id = UUID()
        defer { try? FileManager.default.removeItem(at: root) }
        await server.configure(offlineBeforeAccept: true)
        let first = client(root: root, server: server, tickets: storage)
        do { try await first.reply("Synthetic reply", to: ticket, version: 1, clientMessageID: id); XCTFail("Offline") } catch is URLError { }
        await server.configure(); await server.changeVersion()
        let restored = client(root: root, server: server, tickets: storage)
        do { try await restored.reply("Changed", to: ticket, version: 2, clientMessageID: UUID()); XCTFail("No bypass UUID") }
        catch FeedbackReplyOutboxError.conflict { }
        do { try await restored.reply("Synthetic reply", to: ticket, version: 2, clientMessageID: id); XCTFail("Keep expected version") }
        catch ReportTransportError.rejected(statusCode: 409) { }
        let operation = try await restored.pendingReply(for: ticket); XCTAssertEqual(operation?.expectedVersion, 1)
        let result = await server.snapshot(); XCTAssertEqual(result.0, 0); XCTAssertEqual(result.1[0], result.1[1])
    }
    func test410ErasesPendingOperationAndStoredCapability() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
        defer { try? FileManager.default.removeItem(at: root) }
        await server.configure(offlineBeforeAccept: true)
        let first = client(root: root, server: server, tickets: storage)
        do { try await first.reply("Synthetic", to: ticket, version: 1, clientMessageID: UUID()); XCTFail("Offline") } catch is URLError { }
        await server.configure(revoked: true)
        let restored = client(root: root, server: server, tickets: storage)
        do { try await restored.retryPendingReply(ticket); XCTFail("Gone") } catch ReportTransportError.rejected(statusCode: 410) { }
        let pending = try await restored.pendingReply(for: ticket); XCTAssertNil(pending)
        XCTAssertTrue(storage.load().isEmpty)
    }
    func testRequestedDeletionDiscardsReplyWithoutRetryingIt() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
        defer { try? FileManager.default.removeItem(at: root) }
        await server.configure(offlineBeforeAccept: true)
        let first = client(root: root, server: server, tickets: storage)
        do { try await first.reply("Synthetic", to: ticket, version: 1, clientMessageID: UUID()); XCTFail("Offline") } catch is URLError { }
        await server.configure()
        try await first.requestDeletion(ticket)
        let pending = try await first.pendingReply(for: ticket); XCTAssertNil(pending)
        let result = await server.snapshot(); XCTAssertEqual(result.0, 0); XCTAssertEqual(result.1.count, 1)
    }
    func testQueueCountExpirationAndNoUUIDBypassAfterScrubbing() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let box = FeedbackReplyOutbox(directory: root), now = Date()
        for index in 0..<20 {
            _ = try await box.stage(reference: "FILOV-2026-R\(index)", id: UUID(), body: "Synthetic", version: 1, kind: "message", now: now)
        }
        do { _ = try await box.stage(reference: "FILOV-2026-EXTRA", id: UUID(), body: "Synthetic", version: 1, kind: "message"); XCTFail("Bounded") }
        catch FeedbackReplyOutboxError.full { }
        let expired = try await box.pending(now: now.addingTimeInterval(8 * 86400))
        XCTAssertTrue(expired.allSatisfy { $0.expired && $0.body.isEmpty })
        do { _ = try await box.stage(reference: "FILOV-2026-R0", id: UUID(), body: "Synthetic", version: 2, kind: "message"); XCTFail("No new UUID after expiration") }
        catch FeedbackReplyOutboxError.expired { }
    }

    private func seedAuxiliary(_ client: FeedbackClient, root: URL) async throws -> URL {
        try await client.setNotificationPreference(true, for: ticket.reference)
        try await client.setNotificationPreference(true, for: "FILOV-2026-OTHER")
        try await client.rememberRoute(UUID(), for: ticket)
        let other = FeedbackTicket(reference: "FILOV-2026-OTHER", trackingToken: "synthetic-other", lastReadMessageID: 0)
        try await client.rememberRoute(UUID(), for: other)
        let event = SupportDiagnosticEvent(correlationID: UUID(), component: .ui, operation: .render, outcome: .success)
        let bundle = try SupportDiagnosticBundle(appID: "filova", reviewedEvents: [event])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(bundle))
        let directory = root.appendingPathComponent("features/diagnostic-outbox")
        let file = directory.appendingPathComponent("synthetic.json")
        try SupportPrivateFile.write(JSONSerialization.data(withJSONObject: ["reference": ticket.reference, "bundle": object]), to: file)
        return file
    }
    func testPendingAndCompletedDeletionCleanOnlyThisConversation() async throws {
        for status in ["pending", "completed"] {
            let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
            defer { try? FileManager.default.removeItem(at: root) }
            let client = client(root: root, server: server, tickets: storage)
            let file = try await seedAuxiliary(client, root: root)
            await server.configure(offlineBeforeAccept: true)
            do { try await client.reply("Synthetic", to: ticket, version: 1, clientMessageID: UUID()); XCTFail("Offline") } catch is URLError { }
            await server.configure(); await server.setDeletion(status)
            let actual = try await client.deletionStatus(ticket); XCTAssertEqual(actual, status)
            let pending = try await client.pendingReply(for: ticket); XCTAssertNil(pending)
            let prefs = try await client.notificationPreferences(); XCTAssertNil(prefs[ticket.reference]); XCTAssertEqual(prefs["FILOV-2026-OTHER"], true)
            let routes = try String(contentsOf: root.appendingPathComponent("features/routes.json"), encoding: .utf8)
            XCTAssertFalse(routes.contains(ticket.reference)); XCTAssertTrue(routes.contains("FILOV-2026-OTHER"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertEqual(storage.load().isEmpty, status == "completed")
        }
    }
    func testRemovedOperationCannotBeResurrectedByDelayedAttempt() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let box = FeedbackReplyOutbox(directory: root)
        let operation = try await box.stage(reference: ticket.reference, id: UUID(), body: "Synthetic", version: 1, kind: "message")
        try await box.remove(reference: ticket.reference)
        do { _ = try await box.markAttempted(operation); XCTFail("No resurrection") } catch FeedbackReplyOutboxError.invalidOperation { }
        let pending = try await box.pending(); XCTAssertTrue(pending.isEmpty)
    }
    func testReadingCorruptQueueEnforcesAggregateSizeAndFileCount() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let box = FeedbackReplyOutbox(directory: root)
        for index in 0..<21 { try Data().write(to: root.appendingPathComponent("FILOV-2026-R\(index).json")) }
        do { _ = try await box.pending(); XCTFail("File count bounded before decoding") } catch FeedbackReplyOutboxError.full { }
    }

    func testDeletionIsRejectedWhileAConfirmedReplyIsInFlight() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = client(root: root, server: server, tickets: storage)
        await server.startHolding()
        let task = Task { try await client.reply("Synthetic", to: ticket, version: 1, clientMessageID: UUID()) }
        var started = false
        for _ in 0..<200 {
            if await server.didStart() { started = true; break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(started)
        guard started else { await server.release(); task.cancel(); _ = try? await task.value; return }
        do { try await client.requestDeletion(ticket); XCTFail("Do not race deletion with a reply") } catch FeedbackClientError.alreadySending { }
        let pending = try await client.pendingReply(for: ticket); XCTAssertNotNil(pending)
        await server.release(); try await task.value
        let final = try await client.pendingReply(for: ticket); XCTAssertNil(final)
        let result = await server.snapshot(); XCTAssertEqual(result.0, 1)
        XCTAssertFalse(result.2.contains("POST /v2/reports/FILOV-2026-RECOVERY/deletion-requests"))
    }
    func testMalformedPaginationFailsClosedWithoutAnotherPost() async throws {
        let root = root(), server = ReplyServer(), storage = RecoveryTickets(ticket)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = client(root: root, server: server, tickets: storage)
        await server.configure(offlineBeforeAccept: true)
        do { try await client.reply("Synthetic", to: ticket, version: 1, clientMessageID: UUID()); XCTFail("Offline") } catch is URLError { }
        await server.configure(); await server.breakPagination()
        do { try await client.retryPendingReply(ticket); XCTFail("No blind send after malformed page") } catch ReportTransportError.invalidResponse { }
        let result = await server.snapshot(); XCTAssertEqual(result.1.count, 1)
        let pending = try await client.pendingReply(for: ticket); XCTAssertNotNil(pending)
    }
    func testCorruptSingleFileCannotExceedQueueByteBudget() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 256 * 1024 + 1).write(to: root.appendingPathComponent(ticket.reference + ".json"))
        let box = FeedbackReplyOutbox(directory: root)
        do { _ = try await box.pending(); XCTFail("Bound before decoding") } catch FeedbackReplyOutboxError.invalidOperation { }
    }
}
