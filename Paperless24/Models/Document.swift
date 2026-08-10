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
    var customFields: [CustomFieldEdit] = []

    enum CodingKeys: String, CodingKey {
        case id, title, content, created, added, correspondent, tags, notes
        case documentType = "document_type"
        case archiveSerialNumber = "archive_serial_number"
        case customFields = "custom_fields"
    }

    var dateObject: Date? { DateFormatting.parseAPIDate(created) }

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
        customFields = (try? c.decode([CustomFieldEdit].self, forKey: .customFields)) ?? []
    }
}

struct UploadContainer: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}
