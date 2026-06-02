import Foundation

/// Eine server-seitige Saved View (`/api/saved_views/`).
struct SavedView: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    var showOnDashboard: Bool?
    var showInSidebar: Bool?
    var sortField: String?
    var sortReverse: Bool?
    var filterRules: [FilterRule]

    var safeName: String { name ?? "Ansicht" }

    enum CodingKeys: String, CodingKey {
        case id, name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortReverse = "sort_reverse"
        case filterRules = "filter_rules"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try? c.decode(String.self, forKey: .name)
        showOnDashboard = try? c.decode(Bool.self, forKey: .showOnDashboard)
        showInSidebar = try? c.decode(Bool.self, forKey: .showInSidebar)
        sortField = try? c.decode(String.self, forKey: .sortField)
        sortReverse = try? c.decode(Bool.self, forKey: .sortReverse)
        filterRules = (try? c.decode([FilterRule].self, forKey: .filterRules)) ?? []
    }

    struct FilterRule: Codable, Hashable {
        let ruleType: Int
        let value: String?

        enum CodingKeys: String, CodingKey {
            case ruleType = "rule_type"
            case value
        }
    }
}

struct SavedViewResponse: Codable {
    let results: [SavedView]?
}

/// Verifiziert gegen ngx-Quellcode `filter-rule-type.ts`.
enum FilterRuleType {
    static let title = 0
    static let correspondent = 3
    static let documentType = 4
    static let hasTagAll = 6
    static let createdBefore = 8
    static let createdAfter = 9
}
