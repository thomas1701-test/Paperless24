import Testing
import Foundation
@testable import Paperless24

/// Meldung vom Gerät (13.09.2026): Sortieren in „Dokumente" tat nichts, und mit 25 geladenen
/// Dokumenten wurde höchstens innerhalb dieser 25 umsortiert — statt die neuesten 25 nach
/// „Hinzugefügt" vom Server zu holen.
///
/// Als Erweiterung von `AccountSwitchTests`: Beide Tests schreiben Konten in die
/// `UserDefaults` und dürfen deshalb nicht parallel zu dessen Tests laufen (`.serialized`).
extension AccountSwitchTests {

    /// Liefert je nach `ordering=` eine andere Reihenfolge — wie der echte Server.
    private static func sortingServer() async throws -> TestHTTPServer {
        try await TestHTTPServer.start { line in
            guard line.contains("/api/documents/") else {
                return #"{"count":0,"next":null,"results":[]}"#
            }
            let ids = line.contains("ordering=-added") ? [30, 10, 20] : [10, 20, 30]
            let results = ids.map {
                #"{"id":\#($0),"title":"Dokument \#($0)","created":"2026-01-0\#($0 / 10)","tags":[]}"#
            }.joined(separator: ",")
            return #"{"count":3,"next":null,"results":[\#(results)]}"#
        }
    }

    private static func withServerAccount(_ server: TestHTTPServer,
                                          _ body: @MainActor (AppStore) async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let backup = (accounts: defaults.data(forKey: "accounts_v2"),
                      active: defaults.string(forKey: "activeAccountId"),
                      demo: defaults.object(forKey: "isDemoMode"))
        let account = Account(id: UUID(), serverUrl: server.baseURL, username: "sort")
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
        #expect(KeychainService.saveToken("token", for: account.serverUrl, username: "sort"))
        defaults.set(false, forKey: "isDemoMode")
        AccountService.save([account])
        AccountService.setActiveId(account.id)
        try await body(AppStore())
    }

    private static func waitFor(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<40 where !condition() {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @Test func sortierwechselLaedtVomServer() async throws {
        let server = try await Self.sortingServer()
        defer { server.stop() }
        try await Self.withServerAccount(server) { store in
            store.currentSortOrder = .dateDesc
            await store.loadFirstPage()
            #expect(store.filteredDocs.map(\.id) == [10, 20, 30])

            store.currentSortOrder = .addedDesc
            store.applyFilters()
            try await Self.waitFor { store.filteredDocs.map(\.id) == [30, 10, 20] }

            #expect(server.requests.contains { $0.contains("ordering=-added") },
                    "Sortierwechsel hat den Server nicht gefragt")
            #expect(store.filteredDocs.map(\.id) == [30, 10, 20],
                    "Liste zeigt nicht die Server-Reihenfolge nach „Hinzugefügt\"")
        }
    }

    @Test func sortierwechselBeiAktivemFilter() async throws {
        let server = try await Self.sortingServer()
        defer { server.stop() }
        try await Self.withServerAccount(server) { store in
            store.currentSortOrder = .dateDesc
            await store.loadFirstPage()
            store.currentFilterTag = 5
            store.applyFilters(debounce: false)
            // Erst die gefilterte Antwort abwarten — sonst überholt der Sortierwechsel sie.
            try await Self.waitFor { server.requests.contains { $0.contains("tags__id") } }
            try await Self.waitFor { !store.isSearching }
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(server.requests.contains { $0.contains("tags__id") })
            #expect(store.filteredDocs.map(\.id) == [10, 20, 30])

            store.currentSortOrder = .addedDesc
            store.applyFilters(debounce: false)
            try await Self.waitFor { store.filteredDocs.map(\.id) == [30, 10, 20] }

            #expect(server.requests.filter { $0.contains("ordering=-added") }.contains { $0.contains("tags__id") },
                    "Gefilterte Anfrage wurde nicht mit neuer Sortierung gestellt")
            #expect(store.filteredDocs.map(\.id) == [30, 10, 20])
        }
    }
}
