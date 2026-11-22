import Foundation
import Security

/// The saved sign-in: server address and credential, stored as one Keychain item.
struct SavedLogin: Codable, Equatable {
    var server: String
    var credential: Credential
    var name: String?
}

enum Keychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "holyarrs") + ".login"
    private static let account = "default"

    static func load() -> SavedLogin? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SavedLogin.self, from: data)
    }

    @discardableResult
    static func save(_ login: SavedLogin) -> Bool {
        guard let data = try? JSONEncoder().encode(login) else { return false }
        clear()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
