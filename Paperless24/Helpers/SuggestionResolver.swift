import Foundation

/// Ein Eintrag, den ein KI-Vorschlag nennt, den es auf dem Server aber noch nicht gibt.
struct MetadataProposal: Identifiable, Hashable {
    let kind: MetadataType
    let name: String
    var id: String { "\(kind.rawValue)-\(name.lowercased())" }
}

/// Ordnet KI-Vorschläge den vorhandenen Stammdaten zu. Was fehlt, wird nicht mehr still auf
/// dem Server angelegt, sondern als Vorschlag zurückgegeben — die Oberfläche fragt nach.
enum SuggestionResolver {
    struct Result: Equatable {
        var correspondent: Int?
        var documentType: Int?
        var tags: [Int] = []
        var missing: [MetadataProposal] = []
    }

    static func resolve(
        correspondent: String?, type: String?, tags: [String],
        correspondents: [(id: Int, name: String)],
        types: [(id: Int, name: String)],
        allTags: [(id: Int, name: String)]
    ) -> Result {
        var result = Result()

        func match(_ name: String, in items: [(id: Int, name: String)]) -> Int? {
            items.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.id
        }
        func cleaned(_ raw: String?) -> String? {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }

        if let name = cleaned(correspondent) {
            if let id = match(name, in: correspondents) {
                result.correspondent = id
            } else {
                result.missing.append(MetadataProposal(kind: .correspondent, name: name))
            }
        }
        if let name = cleaned(type) {
            if let id = match(name, in: types) {
                result.documentType = id
            } else {
                result.missing.append(MetadataProposal(kind: .docType, name: name))
            }
        }
        for raw in tags {
            guard let name = cleaned(raw) else { continue }
            if let id = match(name, in: allTags) {
                if !result.tags.contains(id) { result.tags.append(id) }
            } else {
                let proposal = MetadataProposal(kind: .tag, name: name)
                // Die KI nennt denselben Tag gern zweimal in unterschiedlicher Schreibweise.
                if !result.missing.contains(where: { $0.id == proposal.id }) {
                    result.missing.append(proposal)
                }
            }
        }
        return result
    }
}
