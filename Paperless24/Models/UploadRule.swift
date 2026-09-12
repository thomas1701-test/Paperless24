import Foundation

/// Eine Regel, die das Importformular vorbelegt.
///
/// Wiederkehrende Importe sehen jedes Mal gleich aus: Was aus der Banking-App kommt, ist ein
/// Kontoauszug; was „Rechnung_" im Dateinamen trägt, gehört zum selben Sender. Bisher musste
/// man das bei jedem Import erneut zusammenklicken.
struct UploadRule: Identifiable, Codable, Hashable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case filenameContains
        case anyImport

        var id: String { rawValue }

        var label: String {
            switch self {
            case .filenameContains: return "Dateiname enthält"
            case .anyImport:        return "Jeder Import"
            }
        }
    }

    var id = UUID()
    var name: String = ""
    var trigger: Trigger = .filenameContains
    /// Vergleichstext für `filenameContains`.
    var pattern: String = ""
    var correspondent: Int? = nil
    var documentType: Int? = nil
    var tags: [Int] = []
    /// Titel-Vorlage. `{dateiname}` und `{datum}` werden ersetzt.
    var titleTemplate: String = ""
    var isEnabled: Bool = true

    func matches(filename: String) -> Bool {
        guard isEnabled else { return false }
        switch trigger {
        case .anyImport:
            return true
        case .filenameContains:
            let needle = pattern.trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return false }
            return filename.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Der Titel, den die Regel vorschlägt.
    func title(for filename: String, date: Date = Date()) -> String? {
        let template = titleTemplate.trimmingCharacters(in: .whitespaces)
        guard !template.isEmpty else { return nil }
        let stem = (filename as NSString).deletingPathExtension
        return template
            .replacingOccurrences(of: "{dateiname}", with: stem)
            .replacingOccurrences(of: "{datum}", with: DateFormatting.apiDate(date))
    }
}

extension Array where Element == UploadRule {
    /// Die erste passende Regel. Reihenfolge entscheidet — „Jeder Import" gehört ans Ende.
    func firstMatch(filename: String) -> UploadRule? {
        first { $0.matches(filename: filename) }
    }
}
