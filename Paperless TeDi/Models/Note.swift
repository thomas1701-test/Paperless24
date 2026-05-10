import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: Int
    let note: String
    let created: String?
    let user: Int?
}
