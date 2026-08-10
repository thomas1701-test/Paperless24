import SwiftUI

/// Farbthema der App. `custom` nutzt die frei gewählte Akzentfarbe aus den Einstellungen.
///
/// Die Themen sind bewusst als Paket definiert (Akzent + Verlauf + Kantenstärke) und nicht
/// als einzelne Farbe: eine allein gewählte Akzentfarbe färbt zwar Knöpfe, lässt Verlauf und
/// Chips aber unverändert — das Ergebnis wirkt halb umgesetzt.
enum AppTheme: String, CaseIterable, Identifiable {
    case indigo
    case ocean
    case forest
    case sunset
    case graphite
    case contrast
    case custom

    var id: String { rawValue }

    /// Anzeigename. Deutsche Literale sind die Schlüssel in `Localizable.xcstrings`.
    var displayName: LocalizedStringKey {
        switch self {
        case .indigo:   return "Indigo"
        case .ocean:    return "Ozean"
        case .forest:   return "Wald"
        case .sunset:   return "Sonnenuntergang"
        case .graphite: return "Graphit"
        case .contrast: return "Kontrast"
        case .custom:   return "Eigene Farbe"
        }
    }

    /// Akzentfarbe je Erscheinungsbild. Dunkle Varianten sind heller angesetzt — dieselbe
    /// Farbe, die auf Weiß gut sitzt, verschwindet auf Schwarz.
    /// `indigo` entspricht exakt dem bisherigen `AccentColor`-Asset, damit die
    /// Standardeinstellung die App optisch nicht verändert.
    func accentHex(isDark: Bool) -> String {
        switch self {
        case .indigo:   return isDark ? "5C6BC0" : "3F51B5"
        case .ocean:    return isDark ? "22B8CF" : "0E7490"
        case .forest:   return isDark ? "66BB6A" : "2E7D32"
        case .sunset:   return isDark ? "FF8A5B" : "D2542A"
        case .graphite: return isDark ? "A0AEC0" : "4A5568"
        case .contrast: return isDark ? "7CB0FF" : "0B57D0"
        case .custom:   return isDark ? "5C6BC0" : "3F51B5"   // wird von den Einstellungen überschrieben
        }
    }

    /// Zwei Farben für den zarten Hintergrundverlauf. Leer = kein Verlauf.
    var gradientHexes: [String] {
        switch self {
        case .indigo:   return ["3F51B5", "8E24AA"]
        case .ocean:    return ["0E7490", "1D4ED8"]
        case .forest:   return ["2E7D32", "00897B"]
        case .sunset:   return ["D2542A", "C2185B"]
        case .graphite: return []
        case .contrast: return []
        case .custom:   return []
        }
    }

    /// Kontrast-Thema zeichnet sichtbare Kanten statt sich auf Farbflächen zu verlassen.
    var prefersStrongEdges: Bool { self == .contrast }
}

/// Aufgelöste Farben für genau einen Zustand (Thema + hell/dunkel + AMOLED).
struct ThemePalette: Equatable {
    var accent: Color
    /// Leer, wenn das Thema keinen Verlauf zeichnet.
    var gradient: [Color]
    /// Hintergrund, der `systemBackground` ersetzt — nur im AMOLED-Modus gesetzt.
    var surface: Color?
    var strongEdges: Bool

    var hasGradient: Bool { !gradient.isEmpty }

    /// Hintergrund eines Filter-Chips.
    func chipBackground(active: Bool) -> Color {
        active ? accent : accent.opacity(0.12)
    }

    /// Beschriftung eines Filter-Chips.
    func chipForeground(active: Bool) -> Color {
        active ? .white : accent
    }

    /// Kantenstärke für Karten und Chips — im Kontrast-Thema sichtbar, sonst aus.
    var edgeWidth: CGFloat { strongEdges ? 1 : 0 }

    static let fallback = ThemePalette(
        accent: Color(hex: "3F51B5"), gradient: [], surface: nil, strongEdges: false
    )
}

/// Die drei gespeicherten Werte, aus denen sich jede Farbe der App ableitet.
///
/// Bewusst ein eigener Typ und keine verstreuten `@AppStorage`-Zugriffe: so lässt sich die
/// Ableitung ohne SwiftUI testen, und Widget wie App benutzen dieselbe Logik.
struct ThemeSettings: Equatable {
    var theme: AppTheme = .indigo
    /// Hex ohne `#`. Nur wirksam, wenn `theme == .custom`.
    var customAccentHex: String = "3F51B5"
    /// Echtes Schwarz statt Systemgrau — wirkt ausschließlich im Dunkelmodus.
    var amoled: Bool = false

    /// Die tatsächlich verwendete Akzentfarbe als Hex — auch vom Widget genutzt,
    /// das die Themen-Tabelle selbst nicht kennt.
    func accentHex(isDark: Bool) -> String {
        theme == .custom ? Self.sanitize(customAccentHex) : theme.accentHex(isDark: isDark)
    }

    func palette(isDark: Bool) -> ThemePalette {
        return ThemePalette(
            accent: Color(hex: accentHex(isDark: isDark)),
            gradient: theme.gradientHexes.map { Color(hex: $0) },
            surface: (isDark && amoled) ? .black : nil,
            strongEdges: theme.prefersStrongEdges
        )
    }

    /// Nimmt `#RRGGBB`, `RRGGBB` oder Unsinn entgegen und liefert immer sechs gültige Hex-Stellen.
    static func sanitize(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        let valid = cleaned.allSatisfy { $0.isHexDigit }
        guard valid, cleaned.count == 6 else { return "3F51B5" }
        return cleaned
    }
}

/// Ob effektiv dunkel dargestellt wird. `appearanceMode`: 0 = automatisch, 1 = hell, 2 = dunkel.
func isDarkAppearance(mode: Int, system: ColorScheme) -> Bool {
    switch mode {
    case 1:  return false
    case 2:  return true
    default: return system == .dark
    }
}

// MARK: - Environment

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.fallback
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Listen und Formulare übernehmen im AMOLED-Modus den schwarzen Untergrund.
    /// Ohne `scrollContentBackground(.hidden)` malt UIKit weiterhin sein eigenes Grau darüber.
    @ViewBuilder
    func themedSurface(_ palette: ThemePalette) -> some View {
        if let surface = palette.surface {
            self.scrollContentBackground(.hidden).background(surface)
        } else {
            self
        }
    }
}
