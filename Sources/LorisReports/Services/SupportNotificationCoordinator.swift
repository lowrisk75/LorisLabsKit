import Foundation
import Observation
import UserNotifications

/// One host-owned coordinator. Device tokens stay in memory and app delegates stay host-owned.
@MainActor @Observable
public final class SupportNotificationCoordinator {
    public private(set) var preferences: [String: Bool] = [:]
    public private(set) var error: String?
    public private(set) var route: UUID?
    private let client: FeedbackClient
    private let topic: String
    private let environment: String
    private let registerWithAPNs: @MainActor () -> Void
    private var currentToken: Data?

    public init(client: FeedbackClient, topic: String, environment: String,
                registerWithAPNs: @escaping @MainActor () -> Void) {
        self.client = client; self.topic = topic; self.environment = environment; self.registerWithAPNs = registerWithAPNs
    }
    public func refreshPreferences() async {
        preferences = (try? await client.notificationPreferences()) ?? [:]
    }
    /// Re-register only after prior consent. Never request permission during relaunch.
    public func resume() async {
        guard client.features.notifications else { return }
        await refreshPreferences()
        guard !preferences.isEmpty else { return }
        if await SupportNotificationPermission.isAuthorized() {
            registerWithAPNs()
        } else {
            let tickets = (try? await client.tickets()) ?? []
            for ticket in tickets where preferences[ticket.reference] != nil {
                await disable(for: ticket)
            }
        }
    }
    public func enable(for ticket: FeedbackTicket) async {
        guard client.features.notifications else { return }
        do {
            guard try await SupportNotificationPermission.request() else { return }
            try await client.setNotificationPreference(true, for: ticket.reference)
            await refreshPreferences()
            if let currentToken { try await register(currentToken, for: ticket) }
            else { registerWithAPNs() }
            error = nil
        } catch { self.error = "Notification registration unconfirmed. Retry from Help." }
    }
    public func disable(for ticket: FeedbackTicket) async {
        do {
            try await client.setNotificationPreference(false, for: ticket.reference)
            await refreshPreferences()
            let installation = try await client.notificationInstallationID()
            try await client.removeNotifications(for: ticket, installationID: installation)
            try await client.clearNotificationPreference(for: ticket.reference)
            error = nil
        } catch { self.error = "Remote notification removal unconfirmed. Retry from Help." }
        await refreshPreferences()
    }
    /// Forward the host's current APNs callback; never cache this token on disk.
    public func didRegister(deviceToken: Data) async {
        currentToken = deviceToken
        guard client.features.notifications else { return }
        await refreshPreferences()
        let tickets = (try? await client.tickets()) ?? []
        for ticket in tickets {
            guard let enabled = preferences[ticket.reference] else { continue }
            do {
                if enabled { try await register(deviceToken, for: ticket) }
                else {
                    let installation = try await client.notificationInstallationID()
                    try await client.removeNotifications(for: ticket, installationID: installation)
                    try await client.clearNotificationPreference(for: ticket.reference)
                }
            } catch { self.error = "Notification synchronization unconfirmed. Retry from Help." }
        }
        await refreshPreferences()
    }
    public func didFailRegistration() { error = "APNs registration unavailable. Your conversation remains accessible." }
    public func handleNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard client.features.notifications,
              let value = userInfo["loris_support_route"] as? String, let id = UUID(uuidString: value) else { return false }
        route = id; return true
    }
    public func clearRoute() { route = nil }
    private func register(_ token: Data, for ticket: FeedbackTicket) async throws {
        let installation = try await client.notificationInstallationID()
        _ = try await client.registerNotifications(.init(installationID: installation, deviceToken: token,
            topic: topic, environment: environment, locale: Locale.current.language.languageCode?.identifier ?? "en"), for: ticket)
    }
}

extension FeedbackClient {
    func notificationPreferences() throws -> [String: Bool] {
        let file = featureDirectory.appendingPathComponent("notification-preferences.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32*1024 else { throw FeedbackClientError.storage }
        return try JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: file))
    }
    func setNotificationPreference(_ enabled: Bool, for reference: String) throws {
        guard features.notifications else { throw FeedbackClientError.featureDisabled }
        var preferences = try notificationPreferences()
        guard preferences.count < 100 || preferences[reference] != nil else { throw FeedbackClientError.storage }
        preferences[reference] = enabled
        try SupportPrivateFile.write(JSONEncoder().encode(preferences), to: featureDirectory.appendingPathComponent("notification-preferences.json"))
    }
    func clearNotificationPreference(for reference: String) throws {
        var preferences = try notificationPreferences()
        guard preferences.removeValue(forKey: reference) != nil else { return }
        try SupportPrivateFile.write(JSONEncoder().encode(preferences), to: featureDirectory.appendingPathComponent("notification-preferences.json"))
    }
}
