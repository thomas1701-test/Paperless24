import Foundation

/// Ein Speicherpfad (`/api/storage_paths/`).
///
/// Bestimmt, wohin paperless-ngx die Datei im Dateisystem legt. Für alle, die ihr Archiv auch
/// außerhalb der Weboberfläche benutzen (Backup, Netzlaufwerk), ist das ein wichtiges Feld —
/// die App kannte es bisher nicht.
struct StoragePath: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let path: String?

    var safeName: String { name ?? "Pfad" }

    enum CodingKeys: String, CodingKey { case id, name, path }
}

struct StoragePathResponse: Codable {
    let results: [StoragePath]?
}

/// Ein Benutzer des Servers (`/api/users/`).
struct ServerUser: Identifiable, Codable, Hashable {
    let id: Int
    let username: String?
    let firstName: String?
    let lastName: String?

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? (username ?? "Benutzer \(id)") : full
    }

    enum CodingKeys: String, CodingKey {
        case id, username
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

/// Eine Gruppe (`/api/groups/`).
struct ServerGroup: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    var safeName: String { name ?? "Gruppe \(id)" }
}
