import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let color: String?
    let parent: Int?
    /// `is_inbox_tag` aus paperless-ngx. Der Server definiert seinen Posteingang über diese
    /// Tags — nicht über fehlende Sender.
    var isInboxTag: Bool? = nil

    var safeName: String { name ?? "Unbenannt" }
    var isInbox: Bool { isInboxTag ?? false }
    var safeColor: String { color ?? "#808080" }

    enum CodingKeys: String, CodingKey {
        case id, name, color, parent
        case isInboxTag = "is_inbox_tag"
    }
}

struct TagResponse: Codable {
    let results: [Tag]?
}
