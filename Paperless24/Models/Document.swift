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

extension Document {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        content = try? c.decode(String.self, forKey: .content)
        created = (try? c.decode(String.self, forKey: .created)) ?? ""
        added = try? c.decode(String.self, forKey: .added)
        correspondent = try? c.decode(Int.self, forKey: .correspondent)
        documentType = try? c.decode(Int.self, forKey: .documentType)
        archiveSerialNumber = try? c.decode(Int.self, forKey: .archiveSerialNumber)
        tags = (try? c.decode([Int].self, forKey: .tags)) ?? []
        notes = try? c.decode([Note].self, forKey: .notes)
    }
}

struct UploadContainer: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}
