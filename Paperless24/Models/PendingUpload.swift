import Foundation

struct PendingUpload: Identifiable, Codable {
    var id: UUID = UUID()
    let data: Data
    let filename: String
    let title: String
    let created: Date
    let correspondent: Int?
    let documentType: Int?
    let tags: [Int]
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

    /// Wendet die noch nicht übertragene Änderung auf ein Dokument an.
    ///
    /// Eine Stelle für alle Listen, in denen dasselbe Dokument stecken kann: Gesamtliste,
    /// Trefferliste und Posteingang. Fehlte hier ein Feld, zeigte eine der Listen nach dem
    /// Bearbeiten noch den alten Wert.
    func applied(to doc: Document) -> Document {
        var copy = doc
        copy.title = title
        copy.created = created
        copy.correspondent = correspondent
        copy.documentType = documentType
        copy.archiveSerialNumber = archiveSerialNumber
        copy.tags = tags
        copy.customFields = customFields
        return copy
    }
}
