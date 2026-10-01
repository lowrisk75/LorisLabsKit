import Foundation

public struct FeedbackMessage: Codable, Identifiable, Sendable {
    public let id: Int
    public let clientMessageID: UUID
    public let author: String
    public let kind: String
    public let body: String
    public let targetVersion: String?
    public let betaURL: URL?
    public let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, author, kind, body
        case clientMessageID = "client_message_id", targetVersion = "target_version"
        case betaURL = "beta_url", createdAt = "created_at"
    }
    public var validatedBetaURL: URL? {
        guard let url = betaURL, url.scheme == "https", url.host == "testflight.apple.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: "^/join/[A-Za-z0-9]+$", options: .regularExpression) != nil else { return nil }
        return url
    }
}

public struct FeedbackConversation: Codable, Sendable {
    public let publicReference: String
    public let title: String
    public let description: String
    public let state: String
    public let version: Int
    public let messages: [FeedbackMessage]
    public let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case title, description, state, version, messages
        case publicReference = "public_reference", hasMore = "has_more"
    }
}

public struct FeedbackTicket: Codable, Identifiable, Sendable {
    public var id: String { reference }
    public let reference: String
    public let trackingToken: String
    public var lastReadMessageID: Int
}

/// Counts operator replies after the locally acknowledged message cursor.
public struct FeedbackActivity: Decodable, Sendable {
    public let unreadTeamMessages: Int
    enum CodingKeys: String, CodingKey { case unreadTeamMessages = "unread_team_messages" }
}
