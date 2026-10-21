import Foundation
import Security

public struct FeedbackConfiguration: Sendable {
    public let directory: URL
    public let keychainAccessGroup: String?
    public let serverAuthorizationApproved: Bool
    public let nativeQualificationApproved: Bool
    public let features: SupportFeatureConfiguration
    public let userTextOnly: Bool
    public let requiresExactAppAuthorization: Bool

    public init(directory: URL, keychainAccessGroup: String? = nil,
                serverAuthorizationApproved: Bool = false, nativeQualificationApproved: Bool = false, features: SupportFeatureConfiguration = .disabled, userTextOnly: Bool = false, requiresExactAppAuthorization: Bool = true) {
        self.userTextOnly = userTextOnly; self.requiresExactAppAuthorization = requiresExactAppAuthorization
        self.features = features
        self.directory = directory
        self.keychainAccessGroup = keychainAccessGroup
        self.serverAuthorizationApproved = serverAuthorizationApproved
        self.nativeQualificationApproved = nativeQualificationApproved
    }
    public var deliveryEnabled: Bool { serverAuthorizationApproved && nativeQualificationApproved }
}

public protocol FeedbackTicketStorage: Sendable {
    func load() throws -> [FeedbackTicket]
    func save(_ tickets: [FeedbackTicket]) throws
}

/// Explicit host-only group, no synchronizable items, no vault keys or shared App Group.
struct DeviceOnlyFeedbackTicketStorage: FeedbackTicketStorage {
    let accessGroup: String?
    let service: String
    func query() throws -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "tickets-v2",
            kSecAttrSynchronizable as String: false]
        if let accessGroup {
            guard accessGroup.range(of: "^[A-Za-z0-9]+\\.[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
                  accessGroup.hasSuffix(".support"),
                  !accessGroup.contains("$(") else { throw FeedbackClientError.storage }
            result[kSecAttrAccessGroup as String] = accessGroup
            result[kSecUseDataProtectionKeychain as String] = true
        }
        // Nil preserves existing apps' receipts; never migrate into/out of a group implicitly.
        return result
    }
    func load() throws -> [FeedbackTicket] {
        var query = try query(); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw FeedbackClientError.storage }
        return try JSONDecoder().decode([FeedbackTicket].self, from: data)
    }
    func save(_ tickets: [FeedbackTicket]) throws {
        let data = try JSONEncoder().encode(tickets), query = try query()
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw FeedbackClientError.storage }
        } else if status != errSecSuccess { throw FeedbackClientError.storage }
    }
}

public struct FeedbackHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public init(data: Data, statusCode: Int) { self.data = data; self.statusCode = statusCode }
}
public protocol FeedbackHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse
}
