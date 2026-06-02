import Foundation

/// Ein im Papierkorb liegendes Dokument (`/api/trash/`).
struct TrashDocument: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let created: String?
    let deletedAt: String?

    var safeTitle: String { (title?.isEmpty == false ? title : nil) ?? "Ohne Titel" }

    enum CodingKeys: String, CodingKey {
        case id, title, created
        case deletedAt = "deleted_at"
    }
}

struct TrashResponse: Codable {
    let results: [TrashDocument]?
}
