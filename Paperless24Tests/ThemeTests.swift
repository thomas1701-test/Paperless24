import Testing
import SwiftUI
@testable import Paperless24

/// Die Farbableitung ist der einzige Teil des Themings, der ohne laufende Oberfläche prüfbar
/// ist — und der einzige, in dem ein Fehler die App unbedienbar machen kann (unlesbarer
/// Kontrast, schwarze Fläche im Hellmodus).
struct ThemeTests {

    // MARK: - Hex-Bereinigung

    @Test func sanitizeAkzeptiertReinesHex() {
        #expect(ThemeSettings.sanitize("A1B2C3") == "A1B2C3")
    }

    @Test func sanitizeEntferntRauteUndVereinheitlichtGrossschreibung() {
        #expect(ThemeSettings.sanitize("#a1b2c3") == "A1B2C3")
    }

    @Test func sanitizeFaelltBeiUnsinnAufDenStandardZurueck() {
        #expect(ThemeSettings.sanitize("") == "3F51B5")
        #expect(ThemeSettings.sanitize("ZZZZZZ") == "3F51B5")
        #expect(ThemeSettings.sanitize("A1B2") == "3F51B5")
        #expect(ThemeSettings.sanitize("A1B2C3D4") == "3F51B5")
    }

    // MARK: - Akzentfarben

    @Test func jedesThemaHatFuerHellUndDunkelUnterschiedlicheAkzente() {
        // Gleiche Farbe in beiden Modi hieße: in einem der beiden schlecht lesbar.
        for theme in AppTheme.allCases where theme != .custom {
            #expect(theme.accentHex(isDark: false) != theme.accentHex(isDark: true),
                    "\(theme.rawValue) nutzt in hell und dunkel dieselbe Akzentfarbe")
        }
    }

    @Test func standardthemaEntsprichtDemBisherigenAccentColorAsset() {
        // Ohne das würde ein Update ungefragt das Erscheinungsbild aller Bestandsnutzer ändern.
        #expect(AppTheme.indigo.accentHex(isDark: false) == "3F51B5")
        #expect(AppTheme.indigo.accentHex(isDark: true) == "5C6BC0")
    }

    @Test func alleAkzentfarbenSindGueltigesHex() {
        for theme in AppTheme.allCases {
            for dark in [true, false] {
                let hex = theme.accentHex(isDark: dark)
                #expect(hex.count == 6 && hex.allSatisfy { $0.isHexDigit },
                        "\(theme.rawValue) liefert ungültiges Hex: \(hex)")
            }
        }
    }

    // MARK: - Eigene Farbe

    @Test func eigenesThemaNutztDieGespeicherteFarbe() {
        let settings = ThemeSettings(theme: .custom, customAccentHex: "FF0000")
        #expect(settings.palette(isDark: false).accent == Color(hex: "FF0000"))
    }

    @Test func eigenesThemaIgnoriertKaputtenHexWert() {
        let settings = ThemeSettings(theme: .custom, customAccentHex: "nope")
        #expect(settings.palette(isDark: false).accent == Color(hex: "3F51B5"))
    }

    @Test func eigenesThemaZeichnetKeinenVerlauf() {
        // Ein aus einer einzigen Farbe abgeleiteter Verlauf sieht schmutzig aus.
        let settings = ThemeSettings(theme: .custom, customAccentHex: "FF0000")
        #expect(settings.palette(isDark: false).hasGradient == false)
    }

    // MARK: - Verlauf

    @Test func farbthemenMitVerlaufLiefernGenauZweiFarben() {
        for theme in [AppTheme.indigo, .ocean, .forest, .sunset] {
            #expect(theme.gradientHexes.count == 2, "\(theme.rawValue)")
        }
    }

    @Test func neutraleThemenVerzichtenAufDenVerlauf() {
        #expect(AppTheme.graphite.gradientHexes.isEmpty)
        #expect(AppTheme.contrast.gradientHexes.isEmpty)
    }

    // MARK: - AMOLED

    @Test func amoledFaerbtNurImDunkelmodusSchwarz() {
        let settings = ThemeSettings(theme: .indigo, amoled: true)
        #expect(settings.palette(isDark: true).surface == .black)
        #expect(settings.palette(isDark: false).surface == nil)
    }

    @Test func ohneAmoledBleibtDerSystemhintergrund() {
        let settings = ThemeSettings(theme: .indigo, amoled: false)
        #expect(settings.palette(isDark: true).surface == nil)
    }

    // MARK: - Erscheinungsbild

    @Test func erscheinungsbildAutomatischFolgtDemSystem() {
        #expect(isDarkAppearance(mode: 0, system: .dark) == true)
        #expect(isDarkAppearance(mode: 0, system: .light) == false)
    }

    @Test func erscheinungsbildHellUndDunkelUeberstimmenDasSystem() {
        #expect(isDarkAppearance(mode: 1, system: .dark) == false)
        #expect(isDarkAppearance(mode: 2, system: .light) == true)
    }

    // MARK: - Chips

    @Test func aktiverChipZeichnetWeissAufAkzentfarbe() {
        let palette = ThemeSettings(theme: .ocean).palette(isDark: false)
        #expect(palette.chipBackground(active: true) == palette.accent)
        #expect(palette.chipForeground(active: true) == .white)
        #expect(palette.chipForeground(active: false) == palette.accent)
    }

    @Test func nurDasKontrastthemaZeichnetKanten() {
        #expect(ThemeSettings(theme: .contrast).palette(isDark: false).edgeWidth > 0)
        #expect(ThemeSettings(theme: .indigo).palette(isDark: false).edgeWidth == 0)
    }
}
