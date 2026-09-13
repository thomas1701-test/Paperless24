import UIKit

/// Baut aus gescannten oder fotografierten Seiten ein PDF in vernünftiger Größe.
///
/// Vorher zeichneten Scanner, Fotoauswahl, Stapel-Scan und Netzwerkscanner jede Seite in voller
/// Kameraauflösung ins PDF — als unkomprimierte Bitmap, mehrere Megabyte pro Seite. Das kostete
/// Upload-Zeit und Speicher, und jede wartende Datei lag zusätzlich in der Warteschlange.
///
/// Jetzt: Seite auf höchstens `maxPixelLongSide` Pixel verkleinert (für OCR reichlich) und als
/// JPEG eingebettet. Die Seite selbst bekommt A4-Größe in Punkten, im Seitenverhältnis des Bildes.
enum ScanPDF {

    /// Etwa 190 dpi auf A4 — scharf genug für Texterkennung und Lesen, ein Bruchteil der
    /// Datenmenge eines 12-Megapixel-Fotos.
    static let maxPixelLongSide: CGFloat = 2200
    static let jpegQuality: CGFloat = 0.7
    /// Lange Seite von A4 in PDF-Punkten.
    static let pageLongSide: CGFloat = 842

    static func make(from images: [UIImage]) -> Data {
        make(pageCount: images.count) { images[$0] }
    }

    /// Seiten einzeln anfordern — der Dokumentenscanner liefert jede Seite als großes Bild, und
    /// alle gleichzeitig im Speicher zu halten ist unnötig.
    static func make(pageCount: Int, page: (Int) -> UIImage) -> Data {
        UIGraphicsPDFRenderer().pdfData { context in
            for index in 0..<pageCount {
                autoreleasepool {
                    let prepared = prepare(page(index))
                    let longSide = max(prepared.size.width, prepared.size.height)
                    let factor = longSide > 0 ? pageLongSide / longSide : 1
                    let pageRect = CGRect(x: 0, y: 0,
                                          width: prepared.size.width * factor,
                                          height: prepared.size.height * factor)
                    context.beginPage(withBounds: pageRect, pageInfo: [:])
                    if let cgImage = prepared.jpeg {
                        // UIKit-Koordinaten (Ursprung oben links) → für `CGContext.draw` spiegeln.
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: 0, y: pageRect.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.draw(cgImage, in: pageRect)
                        cg.restoreGState()
                    } else {
                        prepared.fallback.draw(in: pageRect)
                    }
                }
            }
        }
    }

    /// Verkleinert (und backt dabei die Ausrichtung ein) und kodiert als JPEG. Ein `CGImage` aus
    /// einem JPEG-Datenlieferanten übernimmt Quartz unverändert ins PDF, statt es neu zu packen.
    private static func prepare(_ image: UIImage) -> (jpeg: CGImage?, fallback: UIImage, size: CGSize) {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longSide = max(pixelWidth, pixelHeight)
        let factor = longSide > maxPixelLongSide ? maxPixelLongSide / longSide : 1
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = scaled.jpegData(compressionQuality: jpegQuality),
              let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(jpegDataProviderSource: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent)
        else { return (nil, scaled, target) }
        return (cgImage, scaled, target)
    }
}
