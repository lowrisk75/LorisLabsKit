import Foundation

private struct PendingSupportDiagnostics: Codable {
    let reference: String
    let bundle: SupportDiagnosticBundle
}

public extension FeedbackClient {
    /// Persist only an immutable selection confirmed by the user. Retrying reuses bundleID.
    func submitReviewedDiagnostics(_ bundle: SupportDiagnosticBundle, to ticket: FeedbackTicket) async throws {
        guard features.diagnostics, bundle.schemaVersion == 1, bundle.appID == profile.appID,
              bundle.consent.categories == [.appMetadata, .systemDiagnostics], !bundle.consent.remoteAIAllowed,
              try tickets().contains(where: { $0.reference == ticket.reference && $0.trackingToken == ticket.trackingToken }) else {
            throw FeedbackClientError.featureDisabled
        }
        _ = try SupportDiagnosticBundle(appID: bundle.appID, reviewedEvents: bundle.events,
            now: bundle.consent.grantedAt, bundleID: bundle.bundleID)
        guard Date().timeIntervalSince(bundle.consent.grantedAt) <= 7*86_400,
              bundle.consent.grantedAt <= Date().addingTimeInterval(300) else { throw FeedbackClientError.invalidReport }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(bundle)
        guard body.count <= 128*1024 else { throw FeedbackClientError.invalidReport }
        let file = diagnosticQueue.appendingPathComponent(bundle.bundleID.uuidString+".json")
        let pending = try encoder.encode(PendingSupportDiagnostics(reference: ticket.reference, bundle: bundle))
        if FileManager.default.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == pending else { throw FeedbackClientError.invalidReport }
        } else {
            let existing = (try? FileManager.default.contentsOfDirectory(at: diagnosticQueue, includingPropertiesForKeys: nil)) ?? []
            guard existing.count < 20 else { throw FeedbackOutboxError.full }
            try SupportPrivateFile.write(pending, to: file)
        }
        let server = await capabilities()
        guard server.diagnosticBundleVersions.contains(1) else { throw FeedbackClientError.featureDisabled }
        do {
            _ = try await request(ticket, suffix: "diagnostics", body: body)
            try FileManager.default.removeItem(at: file)
        } catch ReportTransportError.rejected(statusCode: 410) {
            try? FileManager.default.removeItem(at: file)
            throw ReportTransportError.rejected(statusCode: 410)
        }
    }

    func retryReviewedDiagnostics() async throws {
        guard features.diagnostics else { throw FeedbackClientError.featureDisabled }
        let files = (try? FileManager.default.contentsOfDirectory(at: diagnosticQueue, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let all = try tickets()
        for file in files.prefix(20) where file.pathExtension == "json" {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 140*1024,
                  let data = try? Data(contentsOf: file), let pending = try? decoder.decode(PendingSupportDiagnostics.self, from: data),
                  Date().timeIntervalSince(pending.bundle.consent.grantedAt) <= 7*86_400,
                  let ticket = all.first(where: { $0.reference == pending.reference }) else {
                try? FileManager.default.removeItem(at: file); continue
            }
            try await submitReviewedDiagnostics(pending.bundle, to: ticket)
        }
    }

    /// Lookup requires an opaque UUID, then a surviving local Keychain receipt.
    func ticketForNotification(route: UUID) throws -> FeedbackTicket? {
        let routes = try readRoutes()
        guard let reference = routes[route.uuidString] else { return nil }
        return try tickets().first { $0.reference == reference }
    }

    func notificationInstallationID() throws -> UUID {
        let file = featureDirectory.appendingPathComponent("installation.json")
        if let data = try? Data(contentsOf: file), let id = try? JSONDecoder().decode(UUID.self, from: data) { return id }
        let id = UUID(); try SupportPrivateFile.write(JSONEncoder().encode(id), to: file); return id
    }
}

extension FeedbackClient {
    private var diagnosticQueue: URL { featureDirectory.appendingPathComponent("diagnostic-outbox") }
    private var routeFile: URL { featureDirectory.appendingPathComponent("routes.json") }
    private func readRoutes() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: routeFile.path) else { return [:] }
        guard let size = try routeFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64*1024 else { throw FeedbackClientError.storage }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: routeFile))
    }
    func rememberRoute(_ id: UUID, for ticket: FeedbackTicket) throws {
        var routes = try readRoutes()
        routes = routes.filter { $0.value != ticket.reference }
        guard routes.count < 100 else { throw FeedbackClientError.storage }
        routes[id.uuidString] = ticket.reference
        try SupportPrivateFile.write(JSONEncoder().encode(routes), to: routeFile)
    }
    func forgetRoutes(for reference: String) throws {
        guard FileManager.default.fileExists(atPath: routeFile.path) else { return }
        let routes = try readRoutes().filter { $0.value != reference }
        try SupportPrivateFile.write(JSONEncoder().encode(routes), to: routeFile)
    }
    func discardDiagnostics(for reference: String) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for file in (try? FileManager.default.contentsOfDirectory(at: diagnosticQueue, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: file), data.count <= 140*1024,
                  let item = try? decoder.decode(PendingSupportDiagnostics.self, from: data), item.reference == reference else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}
