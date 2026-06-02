import SwiftUI

/// Eine aus einem Dokument erkannte Frist/Termin.
struct Deadline: Identifiable, Codable, Hashable {
    var id = UUID()
    let docId: Int
    let docTitle: String
    let typeRaw: String
    let date: Date
    let detail: String

    var type: DeadlineType { DeadlineType(rawValue: typeRaw) ?? .general }
}

enum DeadlineType: String, Codable, CaseIterable {
    case payment, cancellation, warranty, withdrawal, general

    var label: String {
        switch self {
        case .payment:      return "Zahlungsziel"
        case .cancellation: return "Kündigungsfrist"
        case .warranty:     return "Garantie"
        case .withdrawal:   return "Widerruf"
        case .general:      return "Termin"
        }
    }

    var icon: String {
        switch self {
        case .payment:      return "eurosign.circle"
        case .cancellation: return "xmark.circle"
        case .warranty:     return "shield"
        case .withdrawal:   return "arrow.uturn.backward.circle"
        case .general:      return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .payment:      return .red
        case .cancellation: return .orange
        case .warranty:     return .blue
        case .withdrawal:   return .purple
        case .general:      return .gray
        }
    }
}

/// Roh-Ausgabe der KI-Extraktion.
struct ExtractedDeadline {
    let type: DeadlineType
    let date: Date
    let detail: String
}
