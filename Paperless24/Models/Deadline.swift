import Foundation

/// Eine Frist, die in einem Dokument steht.
struct Deadline: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case payment        // Rechnung, Zahlungsziel
        case cancellation   // Kündigung, Widerruf, Vertragsende
        case warranty       // Garantie, Gewährleistung
        case expiry         // gültig bis, Ablauf (Ausweis, Vertrag)
        case appointment    // Termin

        var label: String {
            switch self {
            case .payment:      return "Zahlung"
            case .cancellation: return "Kündigung"
            case .warranty:     return "Garantie"
            case .expiry:       return "Ablauf"
            case .appointment:  return "Termin"
            }
        }

        var symbolName: String {
            switch self {
            case .payment:      return "eurosign.circle"
            case .cancellation: return "xmark.circle"
            case .warranty:     return "shield"
            case .expiry:       return "hourglass"
            case .appointment:  return "calendar"
            }
        }

        /// Wie viele Tage vorher erinnert wird.
        ///
        /// Eine Kündigungsfrist braucht Vorlauf — wer drei Tage vorher erfährt, dass ein
        /// Vertrag in drei Tagen kündbar ist, hat nichts gewonnen.
        var reminderLeadDays: Int {
            switch self {
            case .payment:      return 3
            case .cancellation: return 42
            case .warranty:     return 30
            case .expiry:       return 30
            case .appointment:  return 2
            }
        }
    }

    var id: String { "\(documentId)-\(kind.rawValue)-\(DateFormatting.apiDate(date))" }

    let documentId: Int
    let date: Date
    let kind: Kind
    /// Die Textstelle, aus der die Frist stammt — damit der Nutzer prüfen kann, was erkannt wurde.
    let evidence: String
    /// 0…1. Wie klar das Schlüsselwort war.
    let confidence: Double

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    var isOverdue: Bool { daysRemaining < 0 }
}
