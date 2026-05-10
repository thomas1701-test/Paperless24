import Foundation

struct DocumentType: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?

    var safeName: String { name ?? "Typ" }
}

struct DocTypeResponse: Codable {
    let results: [DocumentType]?
}
