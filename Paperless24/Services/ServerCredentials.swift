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

    private static func headerKey(_ server: String) -> String { "customHeaders.\(server)" }

    /// Kopfzeilen, die jeder Anfrage an diesen Server mitgegeben werden.
    static func headers(for server: String) -> [String: String] {
        guard !server.isEmpty,
              let raw = UserDefaults.standard.dictionary(forKey: headerKey(server)) as? [String: String]
        else { return [:] }
        return raw
    }

    static func setHeaders(_ headers: [String: String], for server: String) {
        guard !server.isEmpty else { return }
        if headers.isEmpty {
            UserDefaults.standard.removeObject(forKey: headerKey(server))
        } else {
            UserDefaults.standard.set(headers, forKey: headerKey(server))
        }
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
        readData(service: certService, account: server) != nil
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

    private static func readData(service: String, account: String) -> Data? {
        guard !account.isEmpty else { return nil }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}

/// `URLSession`, die auf die Zertifikatsanfrage des Servers antwortet.
///
/// `URLSession.shared` kann das nicht: Sie nimmt keinen Delegate an, und ohne Delegate bleibt
/// eine mTLS-Anfrage unbeantwortet — die Verbindung bricht ab, bevor eine Zeile HTTP fließt.
final class ClientCertSessionProvider: NSObject, URLSessionDelegate {
    static let shared = ClientCertSessionProvider()

    private var sessions: [String: URLSession] = [:]
    private let lock = NSLock()

    /// Session für diesen Server. Ohne Zertifikat die geteilte Session — kein Grund, für
    /// jeden Server eine eigene aufzumachen.
    func session(for server: String) -> URLSession {
        guard ServerCredentials.hasCertificate(for: server) else { return .shared }
        lock.lock()
        defer { lock.unlock() }
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
