import Foundation
import Security

/// Opt-in technical journal. Recording never performs network I/O.
public actor DiagnosticJournal {
    private struct Event: Codable { let occurred_at: Date; let field: String; let code: String }
    private struct State: Codable {
        var enabled = false
        var grantedAt: Date?
        var correlationID = UUID()
        var rotatedAt = Date()
        var events: [Event] = []
        var pending: Data?
        var pendingSince: Date?
    }
    private let collectionAllowed: Bool
    private let keychainAccessGroup: String?
    private let profile: FeedbackAppProfile
    private let file: URL
    private let http: any FeedbackHTTPTransport
    private var state: State
    private var upload: Task<Void, Error>?
    private var generation = UUID()
    private var deleting = false
    private var syntheticDeletionToken: String?
    /// Tests only: bypass the device Keychain with a fixed secret so no real item is created.
    func useSyntheticDeletionToken(_ token: String) { syntheticDeletionToken = token }

    /// Uploads share the bounded, redirect-rejecting transport used for reports; `init` performs no network I/O.
    public init(profile: FeedbackAppProfile, directory: URL, keychainAccessGroup: String? = nil, collectionAllowed: Bool = true,
                transport: (any FeedbackHTTPTransport)? = nil) {
        self.keychainAccessGroup = keychainAccessGroup; self.collectionAllowed = collectionAllowed
        self.profile = profile
        self.http = transport ?? NativeFeedbackHTTPTransport()
        file = directory.appendingPathComponent("diagnostics.json")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maximumStateBytes,
           let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(State.self, from: data) { state = saved }
        else { state = State() }
    }
    static let maximumStateBytes = 2 * 1024 * 1024
    static let maximumResponseBytes = 64 * 1024
    static func isValidChallenge(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9._~-]{8,512}$", options: .regularExpression) != nil
    }
    public var isEnabled: Bool { collectionAllowed && state.enabled }

    public func setEnabled(_ enabled: Bool, now: Date = Date()) throws {
        guard collectionAllowed || !enabled else { throw FeedbackClientError.featureDisabled }
        guard !deleting || !enabled else { throw FeedbackClientError.storage }
        generation = UUID()
        upload?.cancel(); upload = nil
        if !enabled {
            state.enabled = false; state.events = []; state.pending = nil; state.pendingSince = nil
        } else if !state.enabled {
            _ = try deletionToken()
            state.enabled = true; state.grantedAt = now
            state.correlationID = UUID(); state.rotatedAt = now
        }
        try persist()
    }

    public func record(field: FeedbackContextField, code: String, now: Date = Date()) throws {
        guard collectionAllowed, state.enabled, profile.allowedFields.contains(field),
              code.range(of: "^[a-zA-Z0-9_.-]{1,64}$", options: .regularExpression) != nil else { return }
        state.events.removeAll { now.timeIntervalSince($0.occurred_at) > 86_400 }
        state.events.append(Event(occurred_at: now, field: field.rawValue, code: code))
        state.events = Array(state.events.suffix(1000))
        try persist()
    }

    /// Call from an idle foreground lifecycle hook, never the app's critical path.
    public func flush(app: ReportAppContext, now: Date = Date()) async throws {
        guard collectionAllowed, state.enabled, app.appID == profile.appID, upload == nil,
              let grantedAt = state.grantedAt else { return }
        if now.timeIntervalSince(state.rotatedAt) >= 30 * 86_400 { state.correlationID = UUID(); state.rotatedAt = now }
        state.events.removeAll { now.timeIntervalSince($0.occurred_at) > 86_400 }
        if let since = state.pendingSince, now.timeIntervalSince(since) > 7 * 86_400 { state.pending = nil; state.pendingSince = nil }
        if state.pending == nil {
            guard !state.events.isEmpty else { return }
            struct Payload: Encodable {
                let schema_version = 1
                let batch_id: UUID
                let correlation_id: UUID
                let app: ReportAppContext
                let consent: ConsentReceipt
                let events: [Event]
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let minimal = ReportAppContext(appID: app.appID, appVersion: app.appVersion, appBuild: app.appBuild,
                platform: app.platform, osVersion: app.osVersion)
            state.pending = try encoder.encode(Payload(batch_id: UUID(), correlation_id: state.correlationID,
                app: minimal, consent: ConsentReceipt(noticeVersion: "automatic-diagnostics-2026-10-01", grantedAt: grantedAt,
                categories: [.appMetadata, .systemDiagnostics]), events: state.events))
            state.pendingSince = now
            state.events = []
            try persist()
        }
        guard let payload = state.pending else { return }
        let token = try deletionToken()
        let endpoint = profile.endpoint, http = http
        let task = Task {
            let challengeData = try await Self.send(http: http, endpoint: endpoint, path: "v2/challenges", body: Data("{}".utf8))
            guard let object = try JSONSerialization.jsonObject(with: challengeData) as? [String: Any],
                  let challenge = object["challenge"] as? String, Self.isValidChallenge(challenge) else { throw ReportTransportError.invalidResponse }
            try Task.checkCancellation()
            _ = try await Self.send(http: http, endpoint: endpoint, path: "v2/diagnostics", body: payload,
                headers: ["X-Feedback-Challenge": challenge, "X-Diagnostic-Deletion-Token": token])
        }
        let operationGeneration = UUID(); generation = operationGeneration
        upload = task
        do {
            try await task.value
            if generation == operationGeneration {
                if state.pending == payload { state.pending = nil; state.pendingSince = nil; try persist() }
                upload = nil
            }
        } catch { if generation == operationGeneration { upload = nil }; throw error }
    }

    /// Disable locally first. Keep the deletion secret until the server acknowledges erasure.
    public func deleteUploadedDiagnostics() async throws {
        guard !deleting else { return }
        try setEnabled(false)
        deleting = true
        defer { deleting = false }
        let token = try deletionToken()
        let payload = try JSONSerialization.data(withJSONObject: ["app_id": profile.appID])
        _ = try await Self.send(http: http, endpoint: profile.endpoint, path: "v2/diagnostics/deletion-requests", body: payload,
                                headers: ["X-Diagnostic-Deletion-Token": token])
        if syntheticDeletionToken != nil { syntheticDeletionToken = nil; return }
        guard SecItemDelete(keychainQuery() as CFDictionary) == errSecSuccess else { throw FeedbackClientError.storage }
    }

    private static func send(http: any FeedbackHTTPTransport, endpoint: URL, path: String, body: Data, headers: [String: String] = [:]) async throws -> Data {
        guard endpoint.scheme == "https", endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              let url = URL(string: path, relativeTo: endpoint)?.absoluteURL,
              url.scheme == endpoint.scheme, url.host == endpoint.host, url.port == endpoint.port else { throw ReportTransportError.invalidEndpoint }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let response = try await http.send(request, maximumBytes: maximumResponseBytes)
        guard (200..<300).contains(response.statusCode) else { throw ReportTransportError.rejected(statusCode: response.statusCode) }
        return response.data
    }
    private func persist() throws {
        let dir = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var root = dir; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try root.setResourceValues(flags)
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maximumStateBytes else { throw FeedbackOutboxError.full }
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func keychainQuery() -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "fr.lorislab.feedback.\(profile.appID)", kSecAttrAccount as String: "diagnostic-deletion",
            kSecAttrSynchronizable as String: false]
        if let keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = keychainAccessGroup
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
    private func deletionToken() throws -> String {
        if let syntheticDeletionToken { return syntheticDeletionToken }
        var query = keychainQuery(); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) { return token }
        guard status == errSecItemNotFound else { throw FeedbackClientError.storage }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw FeedbackClientError.storage }
        let token = Data(bytes).base64EncodedString()
        var item = keychainQuery(); item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw FeedbackClientError.storage }
        return token
    }
}
