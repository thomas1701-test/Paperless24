import Foundation
import Security

enum KeychainService {
    private static func key(for server: String) -> String {
        "paperless-token-\(server)"
    }

    static func saveToken(_ token: String, for server: String) {
        let data = Data(token.utf8)
        let k = key(for: server)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken(for server: String) -> String? {
        let k = key(for: server)
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

    static func deleteToken(for server: String) {
        let k = key(for: server)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k
        ]
        SecItemDelete(query as CFDictionary)
    }
}
