import UIKit

/// Wählbare App-Symbole. Der `rawValue` ist der Name des Asset-Sets — genau den erwartet
/// `setAlternateIconName`. `standard` steht für das mitgelieferte `AppIcon` und wird als
/// `nil` gesetzt.
enum AppIconOption: String, CaseIterable, Identifiable {
    case standard = "AppIcon"
    case indigo = "AppIconIndigo"
    case forest = "AppIconForest"
    case sunset = "AppIconSunset"
    case graphite = "AppIconGraphite"
    case contrast = "AppIconContrast"

    var id: String { rawValue }

    /// `nil` = Standardsymbol.
    var alternateName: String? { self == .standard ? nil : rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .indigo:   return "Indigo"
        case .forest:   return "Wald"
        case .sunset:   return "Sonnenuntergang"
        case .graphite: return "Graphit"
        case .contrast: return "Kontrast"
        }
    }

    /// Bild für die Vorschau in den Einstellungen.
    ///
    /// Bewusst ein eigenes Image-Set und nicht das `.appiconset`: App-Symbole landen nicht als
    /// benannte Assets im Bundle, `UIImage(named: "AppIconIndigo")` liefert immer `nil` — auch
    /// mit `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, das nur dafür sorgt, dass
    /// sich die Symbole überhaupt umschalten lassen. Die Kacheln blieben deshalb alle leer.
    /// Die Vorschaubilder liegen als `AppIconPreview…` mit 180 px (60 pt bei 3x) daneben.
    var previewImage: UIImage? {
        switch self {
        case .standard: return UIImage(named: "AppIconPreviewStandard")
        case .indigo:   return UIImage(named: "AppIconPreviewIndigo")
        case .forest:   return UIImage(named: "AppIconPreviewForest")
        case .sunset:   return UIImage(named: "AppIconPreviewSunset")
        case .graphite: return UIImage(named: "AppIconPreviewGraphite")
        case .contrast: return UIImage(named: "AppIconPreviewContrast")
        }
    }
}

@MainActor
enum AppIconService {
    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .standard }
        return AppIconOption(rawValue: name) ?? .standard
    }

    static var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Wechselt das Symbol. iOS zeigt dabei selbst einen Hinweis-Dialog an.
    /// Ein erneutes Setzen desselben Symbols würde diesen Dialog unnötig auslösen.
    static func set(_ option: AppIconOption) {
        guard isSupported, current != option else { return }
        UIApplication.shared.setAlternateIconName(option.alternateName) { _ in }
    }
}
