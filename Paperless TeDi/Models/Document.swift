import Foundation

struct Document: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var content: String?
    var created: String
    var added: String?
    var correspondent: Int?
    var documentType: Int?
    var archiveSerialNumber: Int?
    var tags: [Int]
    var notes: [Note]?

    enum CodingKeys: String, CodingKey {
        case id, title, content, created, added, correspondent, tags, notes
        case documentType = "document_type"
        case archiveSerialNumber = "archive_serial_number"
    }

    var dateObject: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: created) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: created) { return d }
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        return simple.date(from: created)
    }

    var safeNotes: [Note] { notes ?? [] }
}

struct UploadContainer: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}
