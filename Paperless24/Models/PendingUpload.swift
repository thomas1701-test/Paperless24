import Foundation

struct PendingUpload: Identifiable, Codable {
    var id: UUID = UUID()
    /// Die Datei selbst. Liegt auf der Platte **neben** `pending.json`
    /// (`PersistenceService.saveUploads`), nicht darin.
    ///
    /// Bis 2.2.0 stand sie als Base64 im JSON: Jedes `saveToDisk()` — jede Bearbeitung, jeder
    /// Sync — kodierte alle wartenden Scans neu, auf dem Main Thread. Zehn wartende Scans hießen
    /// bei jeder Aktion hunderte Megabyte Kodierarbeit.
    var data: Data
    let filename: String
    let title: String
    let created: Date
    let correspondent: Int?
    let documentType: Int?
    let tags: [Int]
    /// Begründung, wenn der Server die Datei abgelehnt hat. Solche Einträge überspringt die
    /// Warteschlange, bis der Nutzer sie erneut versucht oder löscht.
    var failureReason: String? = nil

    init(id: UUID = UUID(), data: Data, filename: String, title: String, created: Date,
         correspondent: Int?, documentType: Int?, tags: [Int], failureReason: String? = nil) {
        self.id = id
        self.data = data
        self.filename = filename
        self.title = title
        self.created = created
        self.correspondent = correspondent
        self.documentType = documentType
        self.tags = tags
        self.failureReason = failureReason
    }

    enum CodingKeys: String, CodingKey {
        case id, data, filename, title, created, correspondent, documentType, tags, failureReason
    }

    /// Liest auch Einträge älterer Versionen, die die Datei noch im JSON tragen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        data = try c.decodeIfPresent(Data.self, forKey: .data) ?? Data()
        filename = try c.decode(String.self, forKey: .filename)
        title = try c.decode(String.self, forKey: .title)
        created = try c.decode(Date.self, forKey: .created)
        correspondent = try c.decodeIfPresent(Int.self, forKey: .correspondent)
        documentType = try c.decodeIfPresent(Int.self, forKey: .documentType)
        tags = try c.decodeIfPresent([Int].self, forKey: .tags) ?? []
        failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
    }

    /// Schreibt alles außer der Datei.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(filename, forKey: .filename)
        try c.encode(title, forKey: .title)
        try c.encode(created, forKey: .created)
        try c.encodeIfPresent(correspondent, forKey: .correspondent)
        try c.encodeIfPresent(documentType, forKey: .documentType)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}

struct PendingEdit: Identifiable, Codable {
    var id: UUID = UUID()
    let docId: Int
    let title: String
    let created: String
    let correspondent: Int?
    let documentType: Int?
    let archiveSerialNumber: Int?
    let tags: [Int]
    var customFields: [CustomFieldEdit] = []
    /// Begründung, wenn der Server die Änderung abgelehnt hat — siehe `PendingUpload`.
    var failureReason: String? = nil
    /// Welche Felder diese Änderung tatsächlich betrifft (API-Namen, siehe `Field`).
    ///
    /// `nil` bei Einträgen älterer Versionen: dann geht wie bisher der vollständige Stand hinaus.
    /// Vorher schickte jede Änderung Titel, Datum, Sender, Typ, ASN, Tags und Felder aus der
    /// lokalen Kopie mit — auch wer nur einen Tag setzte, überschrieb damit alles, was
    /// zwischendurch im Web oder per Workflow geändert worden war.
    var changedFields: [String]? = nil
    /// Eigene Felder, die das Dokument beim Bearbeiten schon trug. Sie bleiben am Dokument,
    /// auch wenn ihr Wert leer ist — paperless-ngx löscht Feldinstanzen, die im PATCH fehlen.
    var existingFieldIDs: [Int]? = nil

    /// Die API-Namen der Felder eines PATCH.
    enum Field {
        static let title = "title"
        static let created = "created"
        static let correspondent = "correspondent"
        static let documentType = "document_type"
        static let archiveSerialNumber = "archive_serial_number"
        static let tags = "tags"
        static let customFields = "custom_fields"
        static let all: [String] = [title, created, correspondent, documentType,
                                    archiveSerialNumber, tags, customFields]
    }

    private func changes(_ field: String) -> Bool { changedFields?.contains(field) ?? true }

    /// Was sich gegenüber `original` ändert. Datum tagesgenau verglichen: `created` kommt je
    /// nach API-Version mit oder ohne Uhrzeit.
    static func changedFields(from original: Document, title: String, created: String,
                              correspondent: Int?, documentType: Int?, archiveSerialNumber: Int?,
                              tags: [Int], customFields: [CustomFieldEdit]) -> [String] {
        var fields: [String] = []
        if original.title != title { fields.append(Field.title) }
        // Lässt sich das Ausgangsdatum nicht lesen, haben die Aufrufer „heute" eingesetzt
        // (`doc.dateObject ?? Date()`). Das ist keine Änderung des Nutzers — nicht überschreiben.
        if let originalDate = original.dateObject, DateFormatting.apiDate(originalDate) != created {
            fields.append(Field.created)
        }
        if original.correspondent != correspondent { fields.append(Field.correspondent) }
        if original.documentType != documentType { fields.append(Field.documentType) }
        if original.archiveSerialNumber != archiveSerialNumber { fields.append(Field.archiveSerialNumber) }
        if Set(original.tags) != Set(tags) { fields.append(Field.tags) }
        if normalized(original.customFields) != normalized(customFields) { fields.append(Field.customFields) }
        return fields
    }

    /// Feld → Wert, leere Werte ausgelassen: „kein Eintrag" und „Eintrag ohne Wert" sehen für
    /// den Vergleich gleich aus, sonst gälte schon das Öffnen des Formulars als Änderung.
    private static func normalized(_ fields: [CustomFieldEdit]) -> [Int: CFValue] {
        Dictionary(fields.filter { !$0.value.isEmpty }.map { ($0.field, $0.value) },
                   uniquingKeysWith: { _, last in last })
    }

    /// Wendet die noch nicht übertragene Änderung auf ein Dokument an — nur die Felder, die
    /// sie betrifft.
    ///
    /// Eine Stelle für alle Listen, in denen dasselbe Dokument stecken kann: Gesamtliste,
    /// Trefferliste und Posteingang. Fehlte hier ein Feld, zeigte eine der Listen nach dem
    /// Bearbeiten noch den alten Wert.
    func applied(to doc: Document) -> Document {
        var copy = doc
        if changes(Field.title) { copy.title = title }
        if changes(Field.created) { copy.created = created }
        if changes(Field.correspondent) { copy.correspondent = correspondent }
        if changes(Field.documentType) { copy.documentType = documentType }
        if changes(Field.archiveSerialNumber) { copy.archiveSerialNumber = archiveSerialNumber }
        if changes(Field.tags) { copy.tags = tags }
        if changes(Field.customFields) { copy.customFields = customFields }
        return copy
    }
}
