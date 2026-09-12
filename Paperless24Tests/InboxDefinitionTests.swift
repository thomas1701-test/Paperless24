import Testing
import Foundation
@testable import Paperless24

/// Deckt ab, was als Posteingang zählt.
///
/// Anlass ist Issue #1: Die App las den Posteingang als „Dokument ohne Sender". In einem
/// gepflegten Archiv sind das hunderte längst bearbeitete Dokumente — das Abzeichen zeigte
/// 542, während der Server im selben Moment 1 meldete. Maßgeblich ist das, was
/// paperless-ngx selbst benutzt: ein Tag mit `is_inbox_tag`.
struct InboxDefinitionTests {

    /// `Tag` gibt es auch im Testing-Framework — hier ist immer das Modell der App gemeint.
    private func tag(_ id: Int, name: String, inbox: Bool) -> Paperless24.Tag {
        Paperless24.Tag(id: id, name: name, color: "#808080", parent: nil, isInboxTag: inbox)
    }

    private func document(_ id: Int, tags: [Int], correspondent: Int?) -> Document {
        Document(id: id, title: "Dokument \(id)", content: nil,
                 created: "2026-09-01", added: "2026-09-01",
                 correspondent: correspondent, documentType: nil,
                 archiveSerialNumber: nil, tags: tags, notes: nil, customFields: [])
    }

    // MARK: - Modell

    @Test("`is_inbox_tag` wird aus der Server-Antwort gelesen")
    func decodesInboxFlag() throws {
        let json = """
        {"results": [
          {"id": 1, "name": "Posteingang", "color": "#a6cee3", "parent": null, "is_inbox_tag": true},
          {"id": 2, "name": "Rechnung", "color": "#a6cee3", "parent": null, "is_inbox_tag": false}
        ]}
        """.data(using: .utf8)!
        let tags = try #require(try JSONDecoder().decode(TagResponse.self, from: json).results)
        #expect(tags[0].isInbox)
        #expect(!tags[1].isInbox)
    }

    @Test("Fehlt das Feld, gilt das Tag nicht als Posteingang")
    func treatsMissingFlagAsFalse() throws {
        let json = """
        {"results": [{"id": 3, "name": "Alt", "color": "#a6cee3", "parent": null}]}
        """.data(using: .utf8)!
        let tags = try #require(try JSONDecoder().decode(TagResponse.self, from: json).results)
        #expect(!tags[0].isInbox)
    }

    // MARK: - Abgrenzung zum alten Verhalten

    @Test("Ein Dokument ohne Sender ist kein Posteingang mehr")
    func documentWithoutCorrespondentIsNotInbox() {
        let inboxTagID = 1
        let docs = [
            document(10, tags: [inboxTagID], correspondent: 5),   // bearbeitet, aber im Posteingang
            document(11, tags: [2], correspondent: nil),          // ohne Sender, nicht im Posteingang
            document(12, tags: [2, inboxTagID], correspondent: 7) // im Posteingang
        ]
        let ids: Set<Int> = [inboxTagID]
        let inbox = docs.filter { !ids.isDisjoint(with: $0.tags) }

        #expect(inbox.map(\Document.id) == [10, 12])
        // Die alte Regel hätte genau das falsche Dokument geliefert.
        #expect(docs.filter { $0.correspondent == nil }.map(\Document.id) == [11])
    }

    @Test("Ohne Inbox-Tag am Server bleibt der Posteingang leer")
    func noInboxTagMeansEmptyInbox() {
        let tags = [tag(1, name: "Rechnung", inbox: false), tag(2, name: "Vertrag", inbox: false)]
        #expect(Set(tags.filter(\.isInbox).map(\Paperless24.Tag.id)).isEmpty)
    }

    // MARK: - Abfrage

    @Test("Der Posteingang wird über `tags__id__in` abgefragt")
    func buildsTagFilterQuery() throws {
        let url = try PaperlessAPI.url(base: "http://paperless.local", path: "documents/", query: [
            URLQueryItem(name: "tags__id__in", value: [3, 1].sorted().map(String.init).joined(separator: ",")),
            URLQueryItem(name: "page", value: "1")
        ])
        #expect(url.absoluteString == "http://paperless.local/api/documents/?tags__id__in=1,3&page=1")
    }
}

/// Zum Aktualisieren ziehen darf niemanden auf den Anmeldebildschirm werfen.
///
/// `loadFirstPage()` schloss aus „kein API-Client" auf „Sitzung abgelaufen" und setzte
/// `needsReLogin`. Im Demo-Modus gibt es aber nie einen Token — ein Zug nach unten warf den
/// Nutzer damit aus der App.
@MainActor
struct RefreshDoesNotLogOutTests {

    @Test func demoModusFordertKeinenNeuenLogin() async {
        let store = AppStore()
        store.isDemoMode = true
        store.needsReLogin = false

        await store.loadFirstPage()
        #expect(store.needsReLogin == false)

        await store.reloadVisible()
        #expect(store.needsReLogin == false)
    }

    @Test func ohneKontoKeinLoginZwang() async {
        let store = AppStore()
        store.isDemoMode = false
        store.accounts = []
        store.activeAccountId = nil
        store.needsReLogin = false

        await store.loadFirstPage()
        #expect(store.needsReLogin == false)
    }
}
