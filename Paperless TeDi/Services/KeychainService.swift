import Foundation
import Security

enum KeychainService {
    private static func key(for serverUrl: String, username: String) -> String {
        "paperless-token-\(serverUrl)|\(username)"
    }

    static func saveToken(_ token: String, for serverUrl: String, username: String) {
        let data = Data(token.utf8)
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken(for serverUrl: String, username: String) -> String? {
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken(for serverUrl: String, username: String) {
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Migration: liest alten Single-User-Token (Key = nur serverUrl)
    static func loadLegacyToken(for serverUrl: String) -> String? {
        let k = "paperless-token-\(serverUrl)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteLegacyToken(for serverUrl: String) {
        let k = "paperless-token-\(serverUrl)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k
        ]
        SecItemDelete(query as CFDictionary)
    }
}
