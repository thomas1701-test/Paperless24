import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let color: String?

    var safeName: String { name ?? "Unbenannt" }
    var safeColor: String { color ?? "#808080" }
}

struct TagResponse: Codable {
    let results: [Tag]?
}
