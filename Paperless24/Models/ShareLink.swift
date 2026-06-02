import Foundation

/// Öffentlicher Freigabe-Link für ein Dokument (`/api/share_links/`).
/// Name `DocShareLink`, um Kollision mit SwiftUIs `ShareLink` zu vermeiden.
struct DocShareLink: Identifiable, Codable, Hashable {
    let id: Int
    let slug: String?
    let created: String?
    let expiration: String?
    let document: Int?
    let fileVersion: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, created, expiration, document
        case fileVersion = "file_version"
    }

    /// Vollständige öffentliche URL, z. B. `https://server/share/<slug>`.
    func publicURL(serverBase: String) -> URL? {
        guard let slug else { return nil }
        return URL(string: "\(serverBase)/share/\(slug)")
    }
}

struct ShareLinkResponse: Codable {
    let results: [DocShareLink]?
}
