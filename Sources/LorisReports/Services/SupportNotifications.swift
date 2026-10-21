import Foundation
import UserNotifications

/// The host retains its UIApplication/NSApplication and UNUserNotificationCenter delegates.
public struct SupportNotificationRegistration: Encodable, Sendable {
    public let installationID: UUID
    public let token: String
    public let topic: String
    public let environment: String
    public let locale: String
    public init(installationID: UUID, deviceToken: Data, topic: String, environment: String, locale: String) {
        self.installationID = installationID; self.token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.topic = topic; self.environment = environment; self.locale = locale == "fr" ? "fr" : "en"
    }
    enum CodingKeys: String, CodingKey { case installationID = "installation_id", token, topic, environment, locale }
}

public enum SupportNotificationPermission {
    public static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return [.authorized, .provisional].contains(settings.authorizationStatus)
    }
    /// Invoke from a dedicated explanation after a successful report, never at app launch.
    public static func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

public extension FeedbackClient {
    func registerNotifications(_ registration: SupportNotificationRegistration, for ticket: FeedbackTicket) async throws -> UUID {
        guard features.notifications, ["sandbox", "production"].contains(registration.environment),
              (64...200).contains(registration.token.count) else { throw FeedbackClientError.featureDisabled }
        let server = await capabilities()
        guard server.notifications else { throw FeedbackClientError.featureDisabled }
        let data = try await request(ticket, suffix: "notifications", body: JSONEncoder().encode(registration), method: "PUT")
        struct Route: Decodable { let routing_id: UUID }
        let route = try JSONDecoder().decode(Route.self, from: data).routing_id
        try rememberRoute(route, for: ticket)
        return route
    }
    func removeNotifications(for ticket: FeedbackTicket, installationID: UUID) async throws {
        guard features.notifications else { throw FeedbackClientError.featureDisabled }
        _ = try await request(ticket, suffix: "notifications?installation_id=\(installationID.uuidString)", method: "DELETE")
        try forgetRoutes(for: ticket.reference)
    }
}
