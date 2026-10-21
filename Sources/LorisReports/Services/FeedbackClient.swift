import Foundation
import Security

public actor FeedbackClient {
    public let profile: FeedbackAppProfile
    private let configuration: FeedbackConfiguration
    private let http: any FeedbackHTTPTransport
    private let storage: any FeedbackTicketStorage
    public nonisolated let features: SupportFeatureConfiguration
    public nonisolated let journal: SupportDiagnosticJournal
    let featureDirectory: URL
    public nonisolated let diagnostics: DiagnosticJournal
    private let outbox: FeedbackOutbox
    private var sending: Set<UUID> = []
    private let replies: FeedbackReplyOutbox
    private var replying: Set<String> = []

    public init(profile: FeedbackAppProfile) {
        let safeID = profile.appID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LorisReports/\(safeID)", isDirectory: true)
        // Preserve already-qualified consumers and the existing receipt namespace.
        self.init(profile: profile, configuration: FeedbackConfiguration(directory: root,
            serverAuthorizationApproved: true, nativeQualificationApproved: true, features: .forBuild(), requiresExactAppAuthorization: false))
    }

    public init(profile: FeedbackAppProfile, configuration: FeedbackConfiguration,
                transport: (any FeedbackHTTPTransport)? = nil, ticketStorage: (any FeedbackTicketStorage)? = nil) {
        self.profile = profile; self.configuration = configuration; self.http = transport ?? NativeFeedbackHTTPTransport()
        self.storage = ticketStorage ?? DeviceOnlyFeedbackTicketStorage(accessGroup: configuration.keychainAccessGroup,
            service: "fr.lorislab.feedback.\(profile.appID)")
        self.features = configuration.features; self.featureDirectory = configuration.directory.appendingPathComponent("features")
        self.journal = SupportDiagnosticJournal(appID: profile.appID, directory: configuration.directory.appendingPathComponent("journal"),
            qualified: configuration.features.diagnostics)
        self.diagnostics = DiagnosticJournal(profile: profile, directory: configuration.directory.appendingPathComponent("diagnostics"),
            keychainAccessGroup: configuration.keychainAccessGroup, collectionAllowed: false, transport: self.http)
        self.outbox = FeedbackOutbox(directory: configuration.directory.appendingPathComponent("outbox", isDirectory: true))
        self.replies = FeedbackReplyOutbox(directory: configuration.directory.appendingPathComponent("replies", isDirectory: true))
    }

    public func tickets() throws -> [FeedbackTicket] { try storage.load() }

    public func isAppAuthorized() async throws -> Bool {
        let result = try await publicRequest(path: "v2/apps")
        struct Apps: Decodable { let apps: [String] }
        return try JSONDecoder().decode(Apps.self, from: result).apps.contains(profile.appID)
    }

    public func capabilities() async -> SupportCapabilities {
        do { let data = try await publicRequest(path: "v2/capabilities"); return try JSONDecoder().decode(SupportCapabilities.self, from: data) }
        catch { return .unavailable }
    }

    private func requireDelivery() throws {
        guard configuration.deliveryEnabled else { throw FeedbackClientError.deliveryDisabled }
    }

    private func publicRequest(path: String) async throws -> Data {
        guard profile.endpoint.scheme == "https", profile.endpoint.host != nil, profile.endpoint.user == nil,
              profile.endpoint.password == nil, profile.endpoint.query == nil, profile.endpoint.fragment == nil,
              let url = URL(string: path, relativeTo: profile.endpoint)?.absoluteURL,
              url.host == profile.endpoint.host, url.scheme == "https", url.port == profile.endpoint.port else {
            throw ReportTransportError.invalidEndpoint
        }
        let result = try await http.send(URLRequest(url: url), maximumBytes: 16*1024)
        guard result.statusCode == 200 else { throw ReportTransportError.rejected(statusCode: result.statusCode) }
        return result.data
    }

    public func submit(_ envelope: ReportEnvelope) async throws -> FeedbackTicket {
        try requireDelivery()
        if configuration.userTextOnly {
            guard envelope.structuredContext.isEmpty, envelope.artifacts.isEmpty, envelope.reporter == nil,
                  envelope.app.deviceModel == nil, envelope.consent.categories == [.userDescription, .appMetadata],
                  !envelope.consent.remoteAIAllowed else { throw FeedbackClientError.invalidReport }
        }
        guard envelope.version == 2, envelope.app.appID == profile.appID else { throw FeedbackClientError.invalidReport }
        guard !sending.contains(envelope.clientReportID) else { throw FeedbackClientError.alreadySending }
        sending.insert(envelope.clientReportID)
        defer { sending.remove(envelope.clientReportID) }
        if configuration.requiresExactAppAuthorization, try await !isAppAuthorized() { throw FeedbackClientError.appNotAuthorized }
        let confirmed = try await outbox.pending().first { $0.clientReportID == envelope.clientReportID }
        let safeEnvelope = confirmed == envelope ? envelope : try ReportRedactionPipeline().redact(envelope)
        let recoveryToken = try await outbox.enqueue(safeEnvelope)
        let receipt = try await DirectReportTransport(endpoint: profile.endpoint, transport: http)
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

    /// A confirmed reply keeps its identity and exact payload across relaunches.
    public func reply(_ body: String, to ticket: FeedbackTicket, version: Int,
                      clientMessageID: UUID, kind: String = "message") async throws {
        try requireDelivery()
        if configuration.requiresExactAppAuthorization, try await !isAppAuthorized() { throw FeedbackClientError.appNotAuthorized }
        guard ["message", "resolved", "reopened"].contains(kind) else { throw FeedbackClientError.invalidReport }
        guard replying.insert(ticket.reference).inserted else { throw FeedbackClientError.alreadySending }
        defer { replying.remove(ticket.reference) }
        let operation = try await replies.stage(reference: ticket.reference, id: clientMessageID,
            body: ReportRedactionPipeline().redact(body), version: version, kind: kind)
        try await deliver(operation, ticket: ticket)
    }

    public func pendingReply(for ticket: FeedbackTicket) async throws -> PendingFeedbackReply? {
        try await replies.pending().first { $0.reference == ticket.reference }
    }

    /// Read and reconcile before every uncertain retry. Never replace an operation
    /// with a fresh UUID or silently rebase its expected version after a conflict.
    public func retryPendingReply(_ ticket: FeedbackTicket) async throws {
        try requireDelivery()
        guard replying.insert(ticket.reference).inserted else { throw FeedbackClientError.alreadySending }
        defer { replying.remove(ticket.reference) }
        if let operation = try await pendingReply(for: ticket) { try await deliver(operation, ticket: ticket) }
    }

    public func reconcilePendingReply(_ ticket: FeedbackTicket) async throws {
        try requireDelivery()
        guard replying.insert(ticket.reference).inserted else { throw FeedbackClientError.alreadySending }
        defer { replying.remove(ticket.reference) }
        if let operation = try await pendingReply(for: ticket), operation.attempted, !operation.expired {
            _ = try await reconcile(operation, ticket: ticket)
        }
    }

    private func reconcile(_ operation: PendingFeedbackReply, ticket: FeedbackTicket) async throws -> Bool {
        var cursor = 0
        for _ in 0..<100 {
            let page = try await conversation(ticket, after: cursor)
            guard page.publicReference == ticket.reference else { throw ReportTransportError.invalidResponse }
            if let message = page.messages.first(where: { $0.clientMessageID == operation.id }) {
                guard message.author == "user", message.body == ReportRedactionPipeline().redact(operation.body), message.kind == operation.kind else {
                    throw FeedbackReplyOutboxError.conflict
                }
                try await replies.remove(reference: ticket.reference)
                return true
            }
            if !page.hasMore { return false }
            guard let next = page.messages.last?.id, next > cursor else { throw ReportTransportError.invalidResponse }
            cursor = next
        }
        throw ReportTransportError.invalidResponse
    }

    private func deliver(_ operation: PendingFeedbackReply, ticket: FeedbackTicket) async throws {
        guard !operation.expired else { throw FeedbackReplyOutboxError.expired }
        if operation.attempted, try await reconcile(operation, ticket: ticket) { return }
        let attempted = try await replies.markAttempted(operation)
        let data = try await request(ticket, suffix: "messages", body: attempted.payload)
        let message = try JSONDecoder().decode(FeedbackMessage.self, from: data)
        guard message.clientMessageID == attempted.id, message.author == "user",
              message.body == ReportRedactionPipeline().redact(attempted.body), message.kind == attempted.kind else {
            throw ReportTransportError.invalidResponse
        }
        try await replies.remove(reference: ticket.reference)
    }

    public func requestDeletion(_ ticket: FeedbackTicket) async throws {
        try requireDelivery()
        guard replying.insert(ticket.reference).inserted else { throw FeedbackClientError.alreadySending }
        defer { replying.remove(ticket.reference) }
        try await replies.remove(reference: ticket.reference)
        _ = try await request(ticket, suffix: "deletion-requests", body: Data("{}".utf8))
        try clearNotificationPreference(for: ticket.reference)
        try forgetRoutes(for: ticket.reference)
        try discardDiagnostics(for: ticket.reference)
    }

    public func deletionStatus(_ ticket: FeedbackTicket) async throws -> String {
        let data = try await request(ticket, suffix: "deletion-status")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String,
              ["not_requested", "pending", "completed"].contains(status) else {
            throw ReportTransportError.invalidResponse
        }
        if status == "pending" || status == "completed" {
            try await replies.remove(reference: ticket.reference)
            try clearNotificationPreference(for: ticket.reference)
            try forgetRoutes(for: ticket.reference)
            try discardDiagnostics(for: ticket.reference)
        }
        if status == "completed" { try save(tickets().filter { $0.reference != ticket.reference }) }
        return status
    }

    public func markRead(_ ticket: FeedbackTicket, messageID: Int) throws {
        var all = try tickets()
        if let i = all.firstIndex(where: { $0.reference == ticket.reference }) {
            all[i].lastReadMessageID = max(all[i].lastReadMessageID, messageID)
            try save(all)
        }
    }

    func request(_ ticket: FeedbackTicket, suffix: String, body: Data? = nil, method: String? = nil) async throws -> Data {
        try requireDelivery()
        let started = ContinuousClock.now, correlationID = UUID()
        let operation: SupportOperation = method == "DELETE" ? .delete : (body == nil ? .read : .submit)
        do {
            let data = try await performRequest(ticket, suffix: suffix, body: body, method: method)
            await recordSupportOutcome(operation, .success, correlationID: correlationID, started: started)
            return data
        } catch {
            let outcome: SupportOutcome
            switch error {
            case let error as URLError where error.code == .timedOut: outcome = .timeout
            case let error as URLError where error.code == .cancelled: outcome = .cancelled
            case is CancellationError: outcome = .cancelled
            default: outcome = .failed
            }
            await recordSupportOutcome(operation, outcome, correlationID: correlationID, started: started)
            throw error
        }
    }

    /// Closed enums only; no ticket identity, URL, body, token or error description.
    /// Journal consent and qualification are enforced by the journal itself.
    private func recordSupportOutcome(_ operation: SupportOperation, _ outcome: SupportOutcome,
                                      correlationID: UUID, started: ContinuousClock.Instant) async {
        let elapsed = started.duration(to: .now).components
        let milliseconds = min(3_600_000, max(0, elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))
        try? await journal.record(.init(correlationID: correlationID, component: .support, operation: operation,
            outcome: outcome, durationMilliseconds: Int(milliseconds), attemptCount: 1))
    }

    private func performRequest(_ ticket: FeedbackTicket, suffix: String, body: Data? = nil, method: String? = nil) async throws -> Data {
        try requireDelivery()
        if configuration.requiresExactAppAuthorization, try await !isAppAuthorized() { throw FeedbackClientError.appNotAuthorized }
        guard profile.endpoint.scheme == "https", profile.endpoint.user == nil, profile.endpoint.password == nil, profile.endpoint.query == nil, profile.endpoint.fragment == nil,
              ticket.reference.range(of: "^[A-Z0-9]+-[0-9]{4}-[A-Z0-9]+$", options: .regularExpression) != nil,
              let url = URL(string: "v2/reports/\(ticket.reference)/\(suffix)", relativeTo: profile.endpoint)?.absoluteURL else { throw FeedbackClientError.invalidReport }
        var request = URLRequest(url: url)
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ticket.trackingToken, forHTTPHeaderField: "X-Tracking-Token")
        let result = try await http.send(request, maximumBytes: 512 * 1024)
        if result.statusCode == 410 {
            try await replies.remove(reference: ticket.reference)
            try clearNotificationPreference(for: ticket.reference)
            try forgetRoutes(for: ticket.reference)
            try discardDiagnostics(for: ticket.reference)
            try save(tickets().filter { $0.reference != ticket.reference })
        }
        guard (200..<300).contains(result.statusCode) else { throw ReportTransportError.rejected(statusCode: result.statusCode) }
        return result.data
    }
    private func save(_ tickets: [FeedbackTicket]) throws { try storage.save(tickets) }

}

public enum FeedbackClientError: Error { case storage, invalidReport, alreadySending, deliveryDisabled, appNotAuthorized, featureDisabled }
