import Testing
import Foundation
@testable import Paperless24

/// Eigene Kopfzeilen liegen im Schlüsselbund, nicht in den UserDefaults.
///
/// Hintergrund (Codeprüfung 12.09.2026, S4): Bis 2.2.0 standen `CF-Access-Client-Secret` und
/// `Authorization: Basic …` im Klartext in der Preferences-Datei und damit in jedem Backup.
struct ServerCredentialsTests {

    private func uniqueServer() -> String { "https://test-\(UUID().uuidString).example" }

    @Test func kopfzeilenLandenNichtInDenUserDefaults() {
        let server = uniqueServer()
        defer { ServerCredentials.removeAll(for: server) }

        #expect(ServerCredentials.setHeaders(["CF-Access-Client-Secret": "geheim"], for: server))
        #expect(UserDefaults.standard.object(forKey: "customHeaders.\(server)") == nil)
        #expect(ServerCredentials.headers(for: server) == ["CF-Access-Client-Secret": "geheim"])
    }

    @Test func altEintragWirdUmgezogen() {
        let server = uniqueServer()
        defer { ServerCredentials.removeAll(for: server) }
        UserDefaults.standard.set(["X-Proxy": "wert"], forKey: "customHeaders.\(server)")

        #expect(ServerCredentials.headers(for: server) == ["X-Proxy": "wert"])
        #expect(UserDefaults.standard.object(forKey: "customHeaders.\(server)") == nil,
                "Klartext-Eintrag muss nach dem Umzug weg sein")
    }

    @Test func entfernenLoeschtKopfzeilen() {
        let server = uniqueServer()
        ServerCredentials.setHeaders(["X-Proxy": "wert"], for: server)

        ServerCredentials.removeAll(for: server)

        #expect(ServerCredentials.headers(for: server).isEmpty)
        #expect(!ServerCredentials.hasCertificate(for: server))
    }

    /// Vorschaubilder nutzen denselben Schlüssel wie die API — sonst greifen Kopfzeilen und
    /// Zertifikat dort nicht.
    @Test(arguments: [
        ("https://paperless.example/api/documents/42/thumb/", "https://paperless.example"),
        ("http://192.168.1.10:8000/paperless/api/documents/7/thumb/", "http://192.168.1.10:8000/paperless"),
    ])
    func vorschauNutztDieServeradresseDerAPI(url: String, base: String) {
        #expect(AuthImage.serverBase(of: url) == base)
    }
}
