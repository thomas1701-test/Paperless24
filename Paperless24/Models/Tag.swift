import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let color: String?
    let parent: Int?

    var safeName: String { name ?? "Unbenannt" }
    var safeColor: String { color ?? "#808080" }

    enum CodingKeys: String, CodingKey {
        case id, name, color, parent
    }
}

struct TagResponse: Codable {
    let results: [Tag]?
}
