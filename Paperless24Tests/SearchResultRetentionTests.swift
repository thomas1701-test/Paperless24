import Testing
import Foundation
@testable import Paperless24

/// `filteredDocs` ist die einzige Quelle der Dokumentliste — sie enthält je nach Lage
/// entweder das lokal gefilterte Ergebnis über `documents` oder die Serverantwort einer
/// Suche. Beim Zurückspringen aus der Detailansicht läuft `onAppear` erneut und ruft
/// `updateFilteredDocs()`; ohne Schutz überschrieb das die Suchtreffer mit der
/// vollständigen Liste, während das Suchfeld weiterhin den Begriff zeigte.
@MainActor
struct SearchResultRetentionTests {

    private func doc(_ id: Int, title: String = "Doc") -> Document {
        Document(id: id, title: "\(title) \(id)", content: nil, created: "2026-07-2\(id % 10)",
                 added: nil, correspondent: nil, documentType: nil,
                 archiveSerialNumber: nil, tags: [], notes: nil)
    }

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.documents = [doc(1), doc(2), doc(3)]
        return store
    }

    @Test func filterlaufBehaeltSuchtrefferBeiAktiverSuche() {
        let store = makeStore()
        store.currentSearchText = "Rechnung"
        store.filteredDocs = [doc(2)]

        store.updateFilteredDocs()

        #expect(store.filteredDocs.map(\.id) == [2])
    }

    @Test func filterlaufBautListeOhneSucheNeuAuf() {
        let store = makeStore()
        store.currentSearchText = ""
        store.filteredDocs = []

        store.updateFilteredDocs()

        #expect(Set(store.filteredDocs.map(\.id)) == [1, 2, 3])
    }

    @Test func loeschenEntferntDokumentAuchAusDenSuchtreffern() {
        let store = makeStore()
        store.currentSearchText = "Rechnung"
        store.filteredDocs = [doc(2), doc(3)]

        store.removeDocumentLocally(id: 2)

        #expect(store.filteredDocs.map(\.id) == [3])
        #expect(store.documents.map(\.id) == [1, 3])
    }

    @Test func bearbeitungAktualisiertAuchDenSuchtreffer() {
        let store = makeStore()
        store.currentSearchText = "Rechnung"
        store.filteredDocs = [doc(2)]

        store.addPendingEdit(docId: 2, title: "Neuer Titel", created: Date(), corr: nil,
                             type: nil, asn: nil, tags: [], customFields: [])

        #expect(store.filteredDocs.first?.title == "Neuer Titel")
    }
}
