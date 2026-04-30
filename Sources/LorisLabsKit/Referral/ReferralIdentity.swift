import Foundation
import Security

/// Reads / writes the user's stable UUID in the iCloud Keychain
/// (so it syncs across devices automatically). The UUID is the
/// referrer's identity for the lifetime of their iCloud account.
@MainActor
public struct ReferralIdentity: Sendable {
    public enum IdentityError: Error, Sendable {
        case keychainStatus(OSStatus)
        case dataCorrupt
    }

    public let service: String
    public let account: String

    public init(
        service: String = "fr.lorislab.referralkit.identity",
        account: String = "uuid"
    ) {
        self.service = service
        self.account = account
    }

    public func getOrCreateUUID() throws -> String {
        if let existing = try fetch() { return existing }
        let new = UUID().uuidString
        try save(new)
        return new
    }

    public func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw IdentityError.keychainStatus(status)
        }
    }

    private func fetch() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
                throw IdentityError.dataCorrupt
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            throw IdentityError.keychainStatus(status)
        }
    }

    private func save(_ uuid: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecValueData as String: uuid.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kCFBooleanTrue!,
            ]
            let update: [String: Any] = [
                kSecValueData as String: uuid.data(using: .utf8)!,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if updateStatus != errSecSuccess {
                throw IdentityError.keychainStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw IdentityError.keychainStatus(status)
        }
    }
}
