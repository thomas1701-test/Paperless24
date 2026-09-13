import Foundation
import Security

/// Zusätzliche Zugangsdaten je Server: eigene HTTP-Header und ein Client-Zertifikat.
///
/// Viele Selbst-Hoster stellen paperless-ngx nicht direkt ins Netz, sondern hinter Cloudflare
/// Access, Authelia oder einen Proxy, der ein Client-Zertifikat verlangt. Ohne beides kommt
/// die App dort nicht einmal bis zum Anmeldebildschirm — der Server antwortet mit einer
/// Weiterleitung auf eine Anmeldeseite, und die App sieht nur „unerwartete Antwort".
enum ServerCredentials {

    // MARK: - Eigene Header

    /// Kopfzeilen enthalten Geheimnisse (`CF-Access-Client-Secret`, `Authorization: Basic …`) und
    /// liegen deshalb im Schlüsselbund. Bis 2.2.0 standen sie im Klartext in den UserDefaults —
    /// also in der Preferences-Datei und damit in jedem Backup. `headers(for:)` holt solche
    /// Alt-Einträge beim ersten Lesen einmalig um.
    private static let headerService = "de.tedi.paperless.headers"
    private static func legacyHeaderKey(_ server: String) -> String { "customHeaders.\(server)" }

    /// Jede Anfrage liest die Kopfzeilen — ein Schlüsselbundzugriff pro Anfrage wäre zu teuer.
    private static var headerCache: [String: [String: String]] = [:]
    private static let cacheLock = NSLock()

    /// Kopfzeilen, die jeder Anfrage an diesen Server mitgegeben werden.
    static func headers(for server: String) -> [String: String] {
        guard !server.isEmpty else { return [:] }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = headerCache[server] { return cached }

        var result: [String: String] = [:]
        if let data = readData(service: headerService, account: server),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            result = stored
        } else if let legacy = UserDefaults.standard.dictionary(forKey: legacyHeaderKey(server)) as? [String: String] {
            // Umzug aus den UserDefaults. Nur löschen, wenn der Schlüsselbund angenommen hat.
            if writeHeaders(legacy, for: server) {
                UserDefaults.standard.removeObject(forKey: legacyHeaderKey(server))
            }
            result = legacy
        }
        headerCache[server] = result
        return result
    }

    @discardableResult
    static func setHeaders(_ headers: [String: String], for server: String) -> Bool {
        guard !server.isEmpty else { return false }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        UserDefaults.standard.removeObject(forKey: legacyHeaderKey(server))
        let ok = writeHeaders(headers, for: server)
        headerCache[server] = ok ? headers : nil
        return ok
    }

    private static func writeHeaders(_ headers: [String: String], for server: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: headerService,
            kSecAttrAccount: server
        ]
        SecItemDelete(query as CFDictionary)
        guard !headers.isEmpty else { return true }
        guard let data = try? JSONEncoder().encode(headers) else { return false }
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Entfernt alles, was für diesen Server hinterlegt ist: Kopfzeilen, Client-Zertifikat
    /// samt Kennwort und die zugehörige Session. Für „Abmelden" und „Konto löschen" — vorher
    /// blieben dabei der private Schlüssel und die Proxy-Geheimnisse auf dem Gerät.
    static func removeAll(for server: String) {
        guard !server.isEmpty else { return }
        setHeaders([:], for: server)
        removeCertificate(for: server)
        ClientCertSessionProvider.shared.invalidate(server: server)
    }

    // MARK: - Client-Zertifikat (mTLS)

    private static let certService = "de.tedi.paperless.clientcert"

    /// Ein importiertes PKCS#12-Bündel liegt im Schlüsselbund — nicht in den UserDefaults.
    /// Es enthält den privaten Schlüssel und gehört damit zum Schützenswertesten der App.
    static func storeCertificate(_ data: Data, password: String, for server: String) -> Bool {
        guard !server.isEmpty, identity(from: data, password: password) != nil else { return false }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: certService,
            kSecAttrAccount: server,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { return false }
        // Das Kennwort getrennt ablegen: Ohne es lässt sich das Bündel nicht öffnen.
        query[kSecAttrService] = certService + ".password"
        query[kSecValueData] = Data(password.utf8)
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        return true
    }

    static func hasCertificate(for server: String) -> Bool {
        readData(service: certService, account: server, returnData: false) != nil
    }

    static func removeCertificate(for server: String) {
        for service in [certService, certService + ".password"] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: server
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Die Identität für die TLS-Aushandlung.
    static func identity(for server: String) -> SecIdentity? {
        guard let data = readData(service: certService, account: server),
              let passwordData = readData(service: certService + ".password", account: server),
              let password = String(data: passwordData, encoding: .utf8) else { return nil }
        return identity(from: data, password: password)
    }

    private static func identity(from data: Data, password: String) -> SecIdentity? {
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else { return nil }
        return (identity as! SecIdentity)
    }

    /// Mit `returnData: false` nur die Prüfung, ob ein Eintrag existiert (liefert dann leere Daten).
    private static func readData(service: String, account: String, returnData: Bool = true) -> Data? {
        guard !account.isEmpty else { return nil }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if returnData { query[kSecReturnData] = true }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return returnData ? item as? Data : Data()
    }
}

/// `URLSession`, die auf die Zertifikatsanfrage des Servers antwortet.
///
/// `URLSession.shared` kann das nicht: Sie nimmt keinen Delegate an, und ohne Delegate bleibt
/// eine mTLS-Anfrage unbeantwortet — die Verbindung bricht ab, bevor eine Zeile HTTP fließt.
final class ClientCertSessionProvider: NSObject, URLSessionDelegate {
    static let shared = ClientCertSessionProvider()

    private var sessions: [String: URLSession] = [:]
    /// Ob für einen Server ein Zertifikat hinterlegt ist. Vorher fragte jede einzelne Anfrage
    /// den Schlüsselbund; `invalidate(server:)` verwirft den gemerkten Wert.
    private var hasCertificate: [String: Bool] = [:]
    private let lock = NSLock()

    /// Session für diesen Server. Ohne Zertifikat die geteilte Session — kein Grund, für
    /// jeden Server eine eigene aufzumachen.
    func session(for server: String) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        let certificate = hasCertificate[server] ?? ServerCredentials.hasCertificate(for: server)
        hasCertificate[server] = certificate
        guard certificate else { return .shared }
        if let existing = sessions[server] { return existing }
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: ServerDelegate(server: server),
                                 delegateQueue: nil)
        sessions[server] = session
        return session
    }

    /// Verwirft die Session eines Servers, etwa nach dem Entfernen des Zertifikats.
    func invalidate(server: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions[server]?.finishTasksAndInvalidate()
        sessions[server] = nil
        hasCertificate[server] = nil
    }

    /// Beantwortet die Zertifikatsanfrage genau eines Servers.
    private final class ServerDelegate: NSObject, URLSessionDelegate {
        let server: String
        init(server: String) { self.server = server }

        func urlSession(_ session: URLSession,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
                  let identity = ServerCredentials.identity(for: server) else {
                // Alles andere — Serverzertifikat, Basic-Auth — bleibt beim Standardverhalten.
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let credential = URLCredential(identity: identity, certificates: nil,
                                           persistence: .forSession)
            completionHandler(.useCredential, credential)
        }
    }
}
