import Testing
import Foundation
import UIKit
@testable import Paperless24

/// Meldung vom Gerät (13.09.2026): Nach einem Wechsel in Mail standen „Fehler:
/// Zeitüberschreitung" und „Offline" in der Liste und gingen nicht mehr weg.
///
/// Als Erweiterung von `AccountSwitchTests`, weil die Tests Konten in die `UserDefaults`
/// schreiben und nicht parallel zu dessen Tests laufen dürfen.
extension AccountSwitchTests {

    private static let pageJSON = #"{"count":1,"next":null,"results":[{"id":1,"title":"Dokument","created":"2026-01-01","tags":[]}]}"#

    private static func withAccount(_ server: TestHTTPServer?, url: String? = nil,
                                    _ body: @MainActor (AppStore) async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let backup = (accounts: defaults.data(forKey: "accounts_v2"),
                      active: defaults.string(forKey: "activeAccountId"),
                      demo: defaults.object(forKey: "isDemoMode"))
        let account = Account(id: UUID(), serverUrl: url ?? server!.baseURL, username: "offline")
        defer {
            defaults.set(backup.accounts, forKey: "accounts_v2")
            defaults.set(backup.active, forKey: "activeAccountId")
            defaults.set(backup.demo, forKey: "isDemoMode")
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
            PersistenceService.deleteAccountFiles(accountId: account.id)
            for key in defaults.dictionaryRepresentation().keys where key.contains("127.0.0.1") {
                defaults.removeObject(forKey: key)
            }
        }
        #expect(KeychainService.saveToken("token", for: account.serverUrl, username: "offline"))
        defaults.set(false, forKey: "isDemoMode")
        AccountService.save([account])
        AccountService.setActiveId(account.id)
        try await body(AppStore())
    }

    /// Server nicht erreichbar: nur „Offline", kein zweites Fehlerbanner.
    @Test func nichtErreichbarZeigtNurOffline() async throws {
        // Port 9 auf localhost: Verbindung wird sofort abgewiesen.
        try await Self.withAccount(nil, url: "http://127.0.0.1:9") { store in
            await store.loadFirstPage()
            #expect(store.isOffline)
            #expect(store.lastSyncError == nil, "Netzfehler erschien zusätzlich als rotes Fehlerbanner")
        }
    }

    /// Zurück im Vordergrund und der Server antwortet wieder: Die App geht von selbst online.
    @Test func vordergrundHoltAusOfflineZurueck() async throws {
        let server = try await TestHTTPServer.start { _ in Self.pageJSON }
        defer { server.stop() }
        try await Self.withAccount(server) { store in
            store.isOffline = true
            store.appDidBecomeActive()
            for _ in 0..<40 where store.isOffline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            #expect(!store.isOffline, "App blieb nach Rückkehr in den Vordergrund offline")
            #expect(store.documents.map(\.id) == [1])
        }
    }

    // Nicht als Test abgedeckt: „Anfrage wurde im Hintergrund eingefroren" (`backgroundTransitions`
    // in `loadFirstPage`). Ein abgerissener Server hilft dabei nicht — `URLSession` wiederholt
    // eine abgebrochene GET-Anfrage selbst, in der App kommt gar kein Fehler an. Ein Versuch mit
    // verworfenen Verbindungen blieb deshalb auch ohne den Fix grün und wurde wieder entfernt.
}
