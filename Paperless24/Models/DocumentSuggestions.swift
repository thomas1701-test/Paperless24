import Foundation

/// Antwort von `GET /api/documents/{id}/suggestions/`.
///
/// paperless-ngx trainiert aus dem bestehenden Archiv einen Klassifikator und schlägt damit
/// Sender, Typ, Tags und Datum vor. Die App hat das bis 2.1.4 ignoriert und nur die eigene
/// Apple-Intelligence-Erkennung angeboten — die es nur auf neueren Geräten gibt. Diese
/// Vorschläge kommen dagegen auf jedem iPhone an, kosten kein Modell und keine Rechenzeit.
///
/// Alle Felder sind optional: ältere Server liefern `storage_paths` und `dates` nicht.
struct DocumentSuggestions: Codable, Equatable {
    var correspondents: [Int] = []
    var tags: [Int] = []
    var documentTypes: [Int] = []
    var storagePaths: [Int] = []
    /// Datumsvorschläge als `yyyy-MM-dd`.
    var dates: [String] = []

    enum CodingKeys: String, CodingKey {
        case correspondents
        case tags
        case documentTypes = "document_types"
        case storagePaths = "storage_paths"
        case dates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        correspondents = try c.decodeIfPresent([Int].self, forKey: .correspondents) ?? []
        tags = try c.decodeIfPresent([Int].self, forKey: .tags) ?? []
        documentTypes = try c.decodeIfPresent([Int].self, forKey: .documentTypes) ?? []
        storagePaths = try c.decodeIfPresent([Int].self, forKey: .storagePaths) ?? []
        dates = try c.decodeIfPresent([String].self, forKey: .dates) ?? []
    }

    init() {}

    var isEmpty: Bool {
        correspondents.isEmpty && tags.isEmpty && documentTypes.isEmpty
            && storagePaths.isEmpty && dates.isEmpty
    }

    /// Erster Datumsvorschlag als `Date`.
    var suggestedDate: Date? {
        dates.compactMap { DateFormatting.parseAPIDate($0) }.first
    }
}
