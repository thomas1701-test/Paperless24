import Testing
import UIKit
@testable import Paperless24

/// Hält fest, dass jedes App-Symbol eine ladbare Vorschau hat.
///
/// Hintergrund: Die Kacheln in „Darstellung" waren alle leer. Bilder aus einem `.appiconset`
/// sind zur Laufzeit nicht über `UIImage(named:)` erreichbar — auch nicht mit
/// `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, das nur das Umschalten des Symbols
/// ermöglicht. Die Vorschauen liegen deshalb als eigene Image-Sets daneben, und genau das
/// prüft dieser Test: er läuft im App-Bundle und lädt die Bilder so, wie es die Ansicht tut.
struct AppIconPreviewTests {

    @Test("Jedes wählbare Symbol hat ein Vorschaubild", arguments: AppIconOption.allCases)
    func everyOptionHasAPreview(option: AppIconOption) {
        #expect(option.previewImage != nil, "Keine Vorschau für \(option.displayName)")
    }

    @Test("Die Vorschau ist quadratisch und groß genug für die Kachel")
    func previewsAreSquareAndLargeEnough() throws {
        for option in AppIconOption.allCases {
            let image = try #require(option.previewImage, "Keine Vorschau für \(option.displayName)")
            #expect(image.size.width == image.size.height, "\(option.displayName) ist nicht quadratisch")
            // Die Kachel ist 60 pt breit; darunter würde das Bild sichtbar unscharf.
            #expect(image.size.width >= 60, "\(option.displayName) ist zu klein")
        }
    }

    @Test("Standard bedeutet kein Alternativsymbol, alle anderen tragen ihren Asset-Namen")
    func alternateNamesMatchTheAssets() {
        #expect(AppIconOption.standard.alternateName == nil)
        for option in AppIconOption.allCases where option != .standard {
            #expect(option.alternateName == option.rawValue)
        }
    }
}
