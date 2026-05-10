import Foundation

struct Correspondent: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?

    var safeName: String { name ?? "Unbekannt" }
}

struct CorrespondentResponse: Codable {
    let results: [Correspondent]?
}
