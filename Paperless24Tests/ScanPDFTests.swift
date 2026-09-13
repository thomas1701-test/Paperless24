import Testing
import UIKit
import PDFKit
@testable import Paperless24

/// Scans landen verkleinert und als JPEG im PDF (P2).
struct ScanPDFTests {

    private func photo(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            // Rauschen statt Einfarbigkeit — sonst komprimiert jedes Verfahren gut und der Test sagt nichts.
            for row in stride(from: 0, to: height, by: 8) {
                for column in stride(from: 0, to: width, by: 8) {
                    UIColor(white: CGFloat((Int(row) * 31 + Int(column) * 17) % 255) / 255, alpha: 1).setFill()
                    ctx.fill(CGRect(x: column, y: row, width: 8, height: 8))
                }
            }
        }
    }

    @Test func grossesFotoWirdKleinesPDF() throws {
        let image = photo(width: 3024, height: 4032)
        let data = ScanPDF.make(from: [image])
        // Unkomprimiert wären das über 30 MB Bilddaten.
        #expect(data.count < 3_000_000, "PDF ist \(data.count) Bytes groß")

        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let bounds = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(bounds.height - ScanPDF.pageLongSide) < 1)
        #expect(abs(bounds.width / bounds.height - 3024.0 / 4032.0) < 0.01)
    }

    @Test func mehrereSeiten() throws {
        let data = ScanPDF.make(pageCount: 3) { _ in photo(width: 800, height: 600) }
        #expect(PDFDocument(data: data)?.pageCount == 3)
    }
}
