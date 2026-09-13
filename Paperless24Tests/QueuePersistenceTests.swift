import Testing
import Foundation
@testable import Paperless24

/// Die Offline-Warteschlange muss den App-Start überleben.
///
/// Hintergrund: `init` lädt den Plattenstand asynchron. Erschien die Liste, bevor er gelesen
/// war, stieß `syncIfStale()` einen Sync an, dessen `saveToDisk()` die leeren Warteschlangen
/// über `pending.json` und `edits.json` schrieb. Nachgestellt am 12.09.2026: Bei 14 MB
/// `documents.json` ging die Warteschlange ohne Verzögerung, bei 36 MB auch nach 100 ms verloren.
@MainActor
@Suite(.serialized)
struct QueuePersistenceTests {

    /// Groß genug, dass das Dekodieren spürbar dauert — sonst gewinnt der Plattenstand das
    /// Rennen zufällig und der Test beweist nichts.
    private static let docCount = 6000
    private static let filler = String(repeating: "Lorem ipsum dolor sit amet ", count: 90)

    @Test(arguments: [false, true])
    func warteschlangeUeberlebtStart(importWaehrendDesLadens: Bool) async throws {
        let defaults = UserDefaults.standard
        let backup = (accounts: defaults.data(forKey: "accounts_v2"),
                      active: defaults.string(forKey: "activeAccountId"),
                      demo: defaults.object(forKey: "isDemoMode"))
        defer {
            defaults.set(backup.accounts, forKey: "accounts_v2")
            defaults.set(backup.active, forKey: "activeAccountId")
            defaults.set(backup.demo, forKey: "isDemoMode")
        }

        // Port 9 (discard) ist nicht erreichbar: jede Anfrage scheitert sofort.
        let account = Account(id: UUID(), serverUrl: "http://127.0.0.1:9", username: "queue-test")
        #expect(KeychainService.saveToken("token", for: account.serverUrl, username: account.username))
        defer {
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
            PersistenceService.deleteAccountFiles(accountId: account.id)
        }

        func url(_ name: String) -> URL { PersistenceService.accountDataURL(for: account.id, filename: name) }
        let docs = (1...Self.docCount).map {
            Document(id: $0, title: "Dokument \($0)", content: Self.filler, created: "2026-01-01",
                     added: nil, correspondent: nil, documentType: nil,
                     archiveSerialNumber: nil, tags: [], notes: nil)
        }
        let upload = PendingUpload(data: Data(repeating: 7, count: 2048), filename: "scan.pdf",
                                   title: "Offline-Scan", created: Date(),
                                   correspondent: nil, documentType: nil, tags: [])
        let edit = PendingEdit(docId: 1, title: "Offline geändert", created: "2026-01-01",
                               correspondent: nil, documentType: nil, archiveSerialNumber: nil, tags: [])
        try JSONEncoder().encode(docs).write(to: url("documents.json"))
        PersistenceService.saveUploads([upload], accountId: account.id)
        PersistenceService.waitForPendingWrites()
        try JSONEncoder().encode([edit]).write(to: url("edits.json"))

        defaults.set(false, forKey: "isDemoMode")
        AccountService.save([account])
        AccountService.setActiveId(account.id)

        let store = AppStore()
        if importWaehrendDesLadens {
            // Eine Datei aus der Share-Extension, bevor der Plattenstand da ist.
            store.addToQueue(data: Data(repeating: 1, count: 16), filename: "neu.pdf", title: "Neu",
                             created: Date(), corr: nil, type: nil, tags: [])
        }
        store.syncIfStale()   // wie `MainDocView.onAppear`

        let expectedUploads = importWaehrendDesLadens ? 2 : 1
        // Warten, bis Snapshot und Sync durch sind (Sync: zwei Versuche mit 2 s Pause).
        for _ in 0..<60 where store.isSyncing || store.documents.isEmpty {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        try await Task.sleep(nanoseconds: 3_000_000_000)

        #expect(store.pendingUploads.count == expectedUploads)
        #expect(store.pendingEdits.count == 1)
        PersistenceService.waitForPendingWrites()
        let onDiskUploads = PersistenceService.loadUploads(accountId: account.id)
        let onDiskEdits = PersistenceService.load([PendingEdit].self, fromURL: url("edits.json")) ?? []
        #expect(onDiskUploads.count == expectedUploads, "Offline-Upload auf der Platte verloren")
        #expect(onDiskEdits.count == 1, "Offline-Änderung auf der Platte verloren")
        #expect(store.documents.count == Self.docCount)
    }
}

/// Einordnung der Serverantworten für die Warteschlangen.
struct WriteResponseClassificationTests {

    private func error(status: Int, body: String = "") -> Error? {
        do {
            try PaperlessAPI.classifyWrite(status: status, body: Data(body.utf8))
            return nil
        } catch {
            return error
        }
    }

    @Test func erfolgWirftNicht() {
        #expect(error(status: 200) == nil)
        #expect(error(status: 204) == nil)
    }

    @Test func ablehnungMitBegruendung() {
        guard case APIError.rejected(400, let reason)? = error(
            status: 400, body: #"{"custom_fields":["Ungültiger Wert"]}"#
        ) else {
            Issue.record("400 muss als Ablehnung gelten")
            return
        }
        #expect(reason?.contains("custom_fields") == true)
    }

    @Test func htmlSeiteEinesProxysIstKeineBegruendung() {
        guard case APIError.rejected(413, let reason)? = error(
            status: 413, body: "<html><body>Request Entity Too Large</body></html>"
        ) else {
            Issue.record("413 muss als Ablehnung gelten")
            return
        }
        #expect(reason == nil)
    }

    @Test func abgelaufeneAnmeldungIstKeineAblehnung() {
        guard case APIError.unauthorized? = error(status: 401) else {
            Issue.record("401 muss `unauthorized` bleiben")
            return
        }
    }

    /// Zeitüberschreitung, Drosselung und Serverfehler gehen vorbei — erneut versuchen.
    @Test(arguments: [408, 429, 500, 502, 503])
    func voruebergehendeFehlerWerdenWiederholt(status: Int) {
        guard case APIError.serverError(status)? = error(status: status) else {
            Issue.record("\(status) muss als vorübergehender Fehler gelten")
            return
        }
    }
}

/// Abgelehnte Einträge in der Warteschlange.
@MainActor
struct RejectedQueueItemTests {

    /// Warteschlangen, die eine ältere App-Version geschrieben hat, kennen `failureReason`
    /// nicht. Ohne sauberes Dekodieren wäre die Warteschlange nach dem Update leer.
    @Test func alteWarteschlangeBleibtLesbar() throws {
        let legacy = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","docId":7,"title":"Alt","created":"2026-01-01",
          "correspondent":null,"documentType":null,"archiveSerialNumber":null,"tags":[3],"customFields":[]}]
        """#
        let edits = try JSONDecoder().decode([PendingEdit].self, from: Data(legacy.utf8))
        #expect(edits.count == 1)
        #expect(edits.first?.failureReason == nil)
    }

    @Test func abgelehnteAenderungWirdNichtInDieListeUebernommen() {
        let store = AppStore()
        store.documents = [Document(id: 1, title: "Server", content: nil, created: "2026-01-01",
                                    added: nil, correspondent: nil, documentType: nil,
                                    archiveSerialNumber: nil, tags: [], notes: nil)]
        var edit = PendingEdit(docId: 1, title: "Lokal", created: "2026-01-01", correspondent: nil,
                               documentType: nil, archiveSerialNumber: nil, tags: [])
        edit.failureReason = "Vom Server abgelehnt (404)"
        store.pendingEdits = [edit]
        store.pendingUploads = []

        store.reApplyPendingEdits()

        #expect(store.documents.first?.title == "Server")
        #expect(store.hasRetryableQueueItems == false)
    }
}

/// Wartende Uploads tragen ihre Datei nicht im JSON (P1).
struct UploadStorageTests {

    @Test func dateiLiegtNebenDemJSON() throws {
        let account = UUID()
        defer { PersistenceService.deleteAccountFiles(accountId: account) }
        let upload = PendingUpload(data: Data(repeating: 9, count: 4096), filename: "scan.pdf",
                                   title: "Scan", created: Date(), correspondent: nil,
                                   documentType: nil, tags: [3])

        PersistenceService.saveUploads([upload], accountId: account)
        PersistenceService.waitForPendingWrites()

        let json = try Data(contentsOf: PersistenceService.accountDataURL(for: account, filename: "pending.json"))
        #expect(json.count < 1024, "Die Datei darf nicht im JSON stehen")
        let loaded = PersistenceService.loadUploads(accountId: account)
        #expect(loaded.first?.data == upload.data)
        #expect(loaded.first?.failureReason == nil)

        // Aus der Warteschlange genommen → Datei wird aufgeräumt.
        PersistenceService.saveUploads([], accountId: account)
        PersistenceService.waitForPendingWrites()
        let dir = PersistenceService.accountDataURL(for: account, filename: "uploads")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? true)
    }

    /// Warteschlangen älterer Versionen tragen die Datei als Base64 im JSON.
    @Test func altesFormatBleibtLesbar() throws {
        let account = UUID()
        defer { PersistenceService.deleteAccountFiles(accountId: account) }
        let bytes = Data("PDF".utf8).base64EncodedString()
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","data":"\#(bytes)","filename":"a.pdf","title":"Alt","created":700000000,"correspondent":null,"documentType":null,"tags":[]}]"#
        try Data(legacy.utf8).write(to: PersistenceService.accountDataURL(for: account, filename: "pending.json"))

        let loaded = PersistenceService.loadUploads(accountId: account)
        #expect(loaded.first?.data == Data("PDF".utf8))
    }
}
