import Testing
import Foundation
@testable import Paperless24

/// Eine Änderung schreibt nur, was sie ändert.
///
/// Hintergrund (Codeprüfung 12.09.2026, B4/B5): Jede Änderung schickte den vollständigen lokalen
/// Stand und überschrieb damit zwischenzeitliche Änderungen auf dem Server. Eigene Felder ohne
/// Wert fehlten im PATCH — paperless-ngx löscht solche Feldinstanzen.
struct EditPatchTests {

    private func doc(title: String = "Rechnung", tags: [Int] = [1],
                     fields: [CustomFieldEdit] = []) -> Document {
        Document(id: 5, title: title, content: nil, created: "2026-03-01T00:00:00+01:00",
                 added: nil, correspondent: 2, documentType: 3, archiveSerialNumber: nil,
                 tags: tags, notes: nil, customFields: fields)
    }

    @Test func nurDerTagGehtHinaus() {
        let original = doc()
        let changed = PendingEdit.changedFields(
            from: original, title: "Rechnung", created: "2026-03-01", correspondent: 2,
            documentType: 3, archiveSerialNumber: nil, tags: [1, 9], customFields: []
        )
        #expect(changed == [PendingEdit.Field.tags])

        var edit = PendingEdit(docId: 5, title: "Rechnung", created: "2026-03-01", correspondent: 2,
                               documentType: 3, archiveSerialNumber: nil, tags: [1, 9])
        edit.changedFields = changed
        let body = PaperlessAPI.patchBody(for: edit)
        #expect(Set(body.keys) == ["tags"])
    }

    @Test func datumMitUhrzeitGiltAlsUnveraendert() {
        let changed = PendingEdit.changedFields(
            from: doc(), title: "Rechnung", created: "2026-03-01", correspondent: 2,
            documentType: 3, archiveSerialNumber: nil, tags: [1], customFields: []
        )
        #expect(changed.isEmpty)
    }

    @Test func leeresFeldAmDokumentBleibtErhalten() {
        let existing = [CustomFieldEdit(field: 11, value: .none)]
        var edit = PendingEdit(docId: 5, title: "Neu", created: "2026-03-01", correspondent: 2,
                               documentType: 3, archiveSerialNumber: nil, tags: [1],
                               customFields: existing + [CustomFieldEdit(field: 12, value: .none)])
        edit.changedFields = [PendingEdit.Field.title, PendingEdit.Field.customFields]
        edit.existingFieldIDs = [11]

        let entries = PaperlessAPI.patchBody(for: edit)["custom_fields"] as? [[String: Any]] ?? []
        // Feld 11 trug das Dokument schon: bleibt, mit null. Feld 12 ist neu und leer: nicht anlegen.
        #expect(entries.count == 1)
        #expect(entries.first?["field"] as? Int == 11)
        #expect(entries.first?["value"] is NSNull)
    }

    /// Einträge älterer Versionen kennen `changedFields` nicht — sie schreiben wie bisher alles.
    @Test func altEintragSchreibtAlles() {
        let edit = PendingEdit(docId: 5, title: "Alt", created: "2026-03-01", correspondent: nil,
                               documentType: nil, archiveSerialNumber: nil, tags: [])
        #expect(Set(PaperlessAPI.patchBody(for: edit).keys) ==
                ["title", "created", "correspondent", "document_type", "archive_serial_number", "tags", "custom_fields"])
    }

    @Test(arguments: [
        ("12,50 €", "12.50"), ("1.234,5", "1234.50"), ("EUR12,5", "EUR12.50"), ("7", "7.00"), ("12.99", "12.99"),
    ])
    func betraegeInServerform(eingabe: String, erwartet: String) {
        #expect(AppStore.normalizedMonetary(eingabe) == .text(erwartet))
    }

    @MainActor
    @Test func unveraendertesSpeichernErzeugtKeineAnfrage() {
        let store = AppStore()
        store.documents = [doc()]
        store.pendingEdits = []
        store.addPendingEdit(docId: 5, title: "Rechnung", created: doc().dateObject!, corr: 2,
                             type: 3, asn: nil, tags: [1], customFields: [])
        #expect(store.pendingEdits.isEmpty)
    }
}

/// ASN aus einem Barcode (B11).
struct ASNBarcodeTests {
    @Test(arguments: [
        ("ASN00042", 42), ("https://paperless.example:8000/asn/42", 42), ("42", 42),
    ])
    func erkenntNummer(payload: String, asn: Int) {
        #expect(ASNScannerSheet.asn(from: payload) == asn)
    }

    @Test func ohneZiffernKeineNummer() {
        #expect(ASNScannerSheet.asn(from: "ASN") == nil)
        #expect(ASNScannerSheet.asn(from: "½²") == nil)
    }
}
