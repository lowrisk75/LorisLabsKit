import Foundation
import Security

@MainActor
public struct ReferralCache: Sendable {
    public struct CachedMe: Codable, Sendable {
        public let uuid: String
        public let code: String
        public let confirmedReferrals: Int
        public let pendingReferrals: Int
        public let bonusUntil: Date?
        public let tiersUnlocked: [String]
        public let rewardsAvailable: [CachedReward]
        public let signedAt: Date

        public init(
            uuid: String, code: String,
            confirmedReferrals: Int, pendingReferrals: Int,
            bonusUntil: Date?, tiersUnlocked: [String],
            rewardsAvailable: [CachedReward], signedAt: Date
        ) {
            self.uuid = uuid
            self.code = code
            self.confirmedReferrals = confirmedReferrals
            self.pendingReferrals = pendingReferrals
            self.bonusUntil = bonusUntil
            self.tiersUnlocked = tiersUnlocked
            self.rewardsAvailable = rewardsAvailable
            self.signedAt = signedAt
        }
    }

    public struct CachedReward: Codable, Sendable {
        public let tier: String
        public let promoCode: String
        public let redeemUrl: String

        public init(tier: String, promoCode: String, redeemUrl: String) {
            self.tier = tier
            self.promoCode = promoCode
            self.redeemUrl = redeemUrl
        }
    }

    public enum CacheError: Error, Sendable {
        case keychainStatus(OSStatus)
    }

    public let service: String
    public let account: String

    public init(
        service: String = "fr.lorislab.referralkit.cache",
        account: String = "me"
    ) {
        self.service = service
        self.account = account
    }

    public func store(_ payload: CachedMe) throws {
        let data = try JSONEncoder.referralKitCache.encode(payload)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var combined = query
            combined.merge(attrs) { _, new in new }
            let addStatus = SecItemAdd(combined as CFDictionary, nil)
            if addStatus != errSecSuccess { throw CacheError.keychainStatus(addStatus) }
        } else if status != errSecSuccess {
            throw CacheError.keychainStatus(status)
        }
    }

    public func fetch() throws -> CachedMe? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw CacheError.keychainStatus(status) }
        guard let data = result as? Data else { return nil }
        return try JSONDecoder.referralKitCache.decode(CachedMe.self, from: data)
    }

    public func fetchIfFresh(maxAge: TimeInterval) throws -> CachedMe? {
        guard let me = try fetch() else { return nil }
        if Date().timeIntervalSince(me.signedAt) > maxAge { return nil }
        return me
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CacheError.keychainStatus(status)
        }
    }
}

extension JSONEncoder {
    static let referralKitCache: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let referralKitCache: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
