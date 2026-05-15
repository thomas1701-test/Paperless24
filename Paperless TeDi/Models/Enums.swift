import Foundation

enum AppState {
    case loading, welcome, login, main
}

enum SortOrder: Int, CaseIterable, Identifiable {
    case dateDesc = 0
    case dateAsc = 1
    case titleAZ = 2
    case senderAZ = 3
    case addedDesc = 4
    case addedAsc = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .dateDesc:  return "Datum (Neu)"
        case .dateAsc:   return "Datum (Alt)"
        case .titleAZ:   return "A–Z"
        case .senderAZ:  return "Sender (A–Z)"
        case .addedDesc: return "Hinzugefügt (Neu)"
        case .addedAsc:  return "Hinzugefügt (Alt)"
        }
    }
}

enum LayoutStyle: String {
    case grid, list
}

enum DateFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case lastMonth = "Letzter Monat"
    case thisYear = "Dieses Jahr"
    case custom = "Benutzerdefiniert"

    var id: String { rawValue }
}

enum MetadataType: String, Identifiable {
    case tag, correspondent, docType
    var id: String { rawValue }
}

struct PaperlessStatistics: Codable {
    let documentsTotal: Int?
    let documentsInbox: Int?
    let characterCount: Int?

    enum CodingKeys: String, CodingKey {
        case documentsTotal = "documents_total"
        case documentsInbox = "documents_inbox"
        case characterCount = "character_count"
    }
}

struct SavedFilter: Codable, Identifiable {
    var id = UUID()
    var name: String
    var tag: Int?
    var correspondent: Int?
    var type: Int?
    var dateFilterRaw: String

    var dateFilter: DateFilter { DateFilter(rawValue: dateFilterRaw) ?? .all }

    init(name: String, tag: Int?, correspondent: Int?, type: Int?, dateFilter: DateFilter) {
        self.name = name; self.tag = tag; self.correspondent = correspondent
        self.type = type; self.dateFilterRaw = dateFilter.rawValue
    }
}

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let changes: [String]
}
