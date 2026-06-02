import Foundation

/// Ein auf dem Server definiertes Custom Field (`/api/custom_fields/`).
struct CustomField: Identifiable, Codable, Hashable {
    let id: Int
    let name: String?
    let dataType: String?
    let extraData: ExtraData?

    var safeName: String { name ?? "Feld" }
    var type: CustomFieldType { CustomFieldType(rawValue: dataType ?? "") ?? .string }

    enum CodingKeys: String, CodingKey {
        case id, name
        case dataType = "data_type"
        case extraData = "extra_data"
    }

    struct ExtraData: Codable, Hashable {
        let selectOptions: [SelectOption]?
        let defaultCurrency: String?

        enum CodingKeys: String, CodingKey {
            case selectOptions = "select_options"
            case defaultCurrency = "default_currency"
        }
    }

    /// Select-Optionen kommen je nach ngx-Version als Objekt `{id,label}` oder als reiner String.
    struct SelectOption: Codable, Hashable, Identifiable {
        let id: String?
        let label: String?

        var safeLabel: String { label ?? id ?? "Option" }

        enum CodingKeys: String, CodingKey { case id, label }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
                id = nil; label = s; return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            label = try? c.decode(String.self, forKey: .label)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(id, forKey: .id)
            try c.encodeIfPresent(label, forKey: .label)
        }
    }
}

struct CustomFieldResponse: Codable {
    let results: [CustomField]?
}

enum CustomFieldType: String {
    case string, url, date, boolean, integer, float, monetary, documentlink, select

    var label: String {
        switch self {
        case .string:       return "Text"
        case .url:          return "URL"
        case .date:         return "Datum"
        case .boolean:      return "Ja/Nein"
        case .integer:      return "Zahl"
        case .float:        return "Dezimalzahl"
        case .monetary:     return "Betrag"
        case .documentlink: return "Dokument-Link"
        case .select:       return "Auswahl"
        }
    }
}

/// Flexibler Custom-Field-Wert, der die heterogenen JSON-Typen de-/kodiert.
enum CFValue: Codable, Hashable {
    case text(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case ints([Int])      // documentlink
    case strings([String])
    case none

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .integer(i); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .text(s); return }
        if let ia = try? c.decode([Int].self) { self = .ints(ia); return }
        if let sa = try? c.decode([String].self) { self = .strings(sa); return }
        self = .none
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s):    try c.encode(s)
        case .number(let d):  try c.encode(d)
        case .integer(let i): try c.encode(i)
        case .bool(let b):    try c.encode(b)
        case .ints(let a):    try c.encode(a)
        case .strings(let a): try c.encode(a)
        case .none:           try c.encodeNil()
        }
    }

    /// Für JSONSerialization-basierte PATCH-Bodies.
    var jsonValue: Any {
        switch self {
        case .text(let s):    return s
        case .number(let d):  return d
        case .integer(let i): return i
        case .bool(let b):    return b
        case .ints(let a):    return a
        case .strings(let a): return a
        case .none:           return NSNull()
        }
    }

    var isEmpty: Bool {
        switch self {
        case .none: return true
        case .text(let s): return s.isEmpty
        case .ints(let a): return a.isEmpty
        case .strings(let a): return a.isEmpty
        default: return false
        }
    }
}

/// Ein Custom-Field-Wert an einem Dokument (`custom_fields: [{field, value}]`).
struct CustomFieldEdit: Codable, Hashable, Identifiable {
    let field: Int
    var value: CFValue

    var id: Int { field }

    enum CodingKeys: String, CodingKey { case field, value }
}
