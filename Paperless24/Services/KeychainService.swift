import Foundation
import Security

enum KeychainService {
    /// Grenzt die Einträge der App von allem anderen im Keychain ab. Frühere Versionen haben
    /// ohne `kSecAttrService` geschrieben — `loadToken` holt solche Einträge einmalig nach.
    private static let service = "de.tedi.paperless.token"

    /// `AfterFirstUnlock`, damit der Hintergrund-Task (`BGAppRefreshTask`) den Token auch bei
    /// gesperrtem Bildschirm lesen kann. `ThisDeviceOnly` hält ihn aus Backups heraus — sonst
    /// ließe sich ein Backup auf ein fremdes Gerät zurückspielen und wäre dort angemeldet.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static func key(for serverUrl: String, username: String) -> String {
        "paperless-token-\(serverUrl)|\(username)"
    }

    /// Ohne `kSecAttrService` trifft die Abfrage jeden Eintrag mit diesem Account — also auch die
    /// Alt-Einträge ohne Service. Genau dafür ist `includeService: false` da.
    private static func query(account: String, includeService: Bool = true) -> [CFString: Any] {
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account
        ]
        if includeService { q[kSecAttrService] = service }
        return q
    }

    /// `false`, wenn der Keychain den Token nicht aufnehmen konnte. Der Aufrufer muss das
    /// auswerten: eine stillschweigend fehlgeschlagene Anmeldung endet sonst in einer
    /// Endlosschleife aus „Sitzung abgelaufen".
    @discardableResult
    static func saveToken(_ token: String, for serverUrl: String, username: String) -> Bool {
        let k = key(for: serverUrl, username: username)
        // Ohne Service-Filter löschen, damit auch ein Alt-Eintrag verschwindet. Der neue
        // Eintrag existiert an dieser Stelle noch nicht, es kann also nichts Falsches treffen.
        SecItemDelete(query(account: k, includeService: false) as CFDictionary)

        var add = query(account: k)
        add[kSecValueData] = Data(token.utf8)
        add[kSecAttrAccessible] = accessibility
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func loadToken(for serverUrl: String, username: String) -> String? {
        let k = key(for: serverUrl, username: username)
        if let token = read(account: k, includeService: true) { return token }

        // Migration: Eintrag einer früheren Version (ohne Service, ohne Zugriffsklasse).
        guard let legacy = read(account: k, includeService: false) else { return nil }
        saveToken(legacy, for: serverUrl, username: username)
        return legacy
    }

    static func deleteToken(for serverUrl: String, username: String) {
        // Ohne Service-Filter: trifft neuen und migrierten Alt-Eintrag gleichermaßen.
        SecItemDelete(query(account: key(for: serverUrl, username: username), includeService: false) as CFDictionary)
    }

    private static func read(account: String, includeService: Bool) -> String? {
        var q = query(account: account, includeService: includeService)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Migration Single-User → Multi-Account

    /// Liest den alten Single-User-Token (Schlüssel = nur `serverUrl`).
    static func loadLegacyToken(for serverUrl: String) -> String? {
        read(account: "paperless-token-\(serverUrl)", includeService: false)
    }

    static func deleteLegacyToken(for serverUrl: String) {
        SecItemDelete(query(account: "paperless-token-\(serverUrl)", includeService: false) as CFDictionary)
    }
}
