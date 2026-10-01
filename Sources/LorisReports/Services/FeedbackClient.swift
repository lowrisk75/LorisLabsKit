import Foundation
import Security

/// Reject redirects: support capabilities must never be forwarded to another origin.
final class FeedbackSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor FeedbackClient {
    public let profile: FeedbackAppProfile
    private let session: URLSession
    private let keychainService: String
    public nonisolated let diagnostics: DiagnosticJournal
    private let outbox: FeedbackOutbox
    private var sending: Set<UUID> = []

    public init(profile: FeedbackAppProfile) {
        self.profile = profile
        self.keychainService = "fr.lorislab.feedback.\(profile.appID)"
        let safeID = profile.appID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        diagnostics = DiagnosticJournal(profile: profile, directory: root.appendingPathComponent("LorisReports/\(safeID)/diagnostics", isDirectory: true))
        outbox = FeedbackOutbox(directory: root.appendingPathComponent("LorisReports/\(safeID)/outbox", isDirectory: true))
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config, delegate: FeedbackSessionDelegate(), delegateQueue: nil)
    }

    public func tickets() throws -> [FeedbackTicket] {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw FeedbackClientError.storage }
        return try JSONDecoder().decode([FeedbackTicket].self, from: data)
    }

    public func submit(_ envelope: ReportEnvelope) async throws -> FeedbackTicket {
        guard envelope.version == 2, envelope.app.appID == profile.appID else { throw FeedbackClientError.invalidReport }
        guard !sending.contains(envelope.clientReportID) else { throw FeedbackClientError.alreadySending }
        sending.insert(envelope.clientReportID)
        defer { sending.remove(envelope.clientReportID) }
        let safeEnvelope = try ReportRedactionPipeline().redact(envelope)
        let recoveryToken = try await outbox.enqueue(safeEnvelope)
        let receipt = try await DirectReportTransport(endpoint: profile.endpoint, session: session)
            .submit(safeEnvelope, recoveryToken: recoveryToken)
        let ticket = FeedbackTicket(reference: receipt.publicReference, trackingToken: receipt.trackingToken, lastReadMessageID: 0)
        var all = try tickets()
        all.removeAll { $0.reference == ticket.reference }; all.append(ticket)
        try save(all)
        try await outbox.remove(envelope.clientReportID)
        return ticket
    }

    public func pendingReports() async throws -> [ReportEnvelope] { try await outbox.pending() }
    public func cancelPending(_ id: UUID) async throws { try await outbox.remove(id) }
    public func retryPending() async throws {
        for envelope in try await outbox.pending() { _ = try await submit(envelope) }
    }

    public func conversation(_ ticket: FeedbackTicket, after: Int = 0) async throws -> FeedbackConversation {
        let data = try await request(ticket, suffix: "conversation?after=\(max(0, after))")
        return try JSONDecoder().decode(FeedbackConversation.self, from: data)
    }

    public func activity(_ ticket: FeedbackTicket) async throws -> FeedbackActivity {
        let data = try await request(ticket, suffix: "activity?after=\(max(0, ticket.lastReadMessageID))")
        return try JSONDecoder().decode(FeedbackActivity.self, from: data)
    }

    /// Keep clientMessageID stable when retrying after a lost response.
    public func reply(_ body: String, to ticket: FeedbackTicket, version: Int,
                      clientMessageID: UUID, kind: String = "message") async throws {
        guard ["message", "resolved", "reopened"].contains(kind) else { throw FeedbackClientError.invalidReport }
        let payload: [String: Any] = ["body": body, "expected_version": version,
                                    "client_message_id": clientMessageID.uuidString, "kind": kind]
        _ = try await request(ticket, suffix: "messages", body: JSONSerialization.data(withJSONObject: payload))
    }

    public func requestDeletion(_ ticket: FeedbackTicket) async throws {
        _ = try await request(ticket, suffix: "deletion-requests", body: Data("{}".utf8))
    }

    public func deletionStatus(_ ticket: FeedbackTicket) async throws -> String {
        let data = try await request(ticket, suffix: "deletion-status")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String,
              ["not_requested", "pending", "completed"].contains(status) else {
            throw ReportTransportError.invalidResponse
        }
        if status == "completed" {
            try save(tickets().filter { $0.reference != ticket.reference })
        }
        return status
    }

    public func markRead(_ ticket: FeedbackTicket, messageID: Int) throws {
        var all = try tickets()
        if let i = all.firstIndex(where: { $0.reference == ticket.reference }) {
            all[i].lastReadMessageID = max(all[i].lastReadMessageID, messageID)
            try save(all)
        }
    }

    private func request(_ ticket: FeedbackTicket, suffix: String, body: Data? = nil) async throws -> Data {
        guard profile.endpoint.scheme == "https", profile.endpoint.user == nil, profile.endpoint.password == nil, profile.endpoint.query == nil, profile.endpoint.fragment == nil,
              ticket.reference.range(of: "^[A-Z0-9]+-[0-9]{4}-[A-Z0-9]+$", options: .regularExpression) != nil,
              let url = URL(string: "v2/reports/\(ticket.reference)/\(suffix)", relativeTo: profile.endpoint)?.absoluteURL else { throw FeedbackClientError.invalidReport }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ticket.trackingToken, forHTTPHeaderField: "X-Tracking-Token")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReportTransportError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ReportTransportError.rejected(statusCode: response.statusCode) }
        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= 512 * 1024 else { throw ReportTransportError.invalidResponse }
        return try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
    }

    private func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "tickets-v2"]
    }
    private func save(_ tickets: [FeedbackTicket]) throws {
        let data = try JSONEncoder().encode(tickets)
        let query = keychainQuery()
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw FeedbackClientError.storage }
        } else if status != errSecSuccess { throw FeedbackClientError.storage }
    }
}

public enum FeedbackClientError: Error { case storage, invalidReport, alreadySending }
