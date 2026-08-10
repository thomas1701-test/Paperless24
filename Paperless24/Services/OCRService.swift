import Foundation
import Vision
import UIKit
import PDFKit

/// On-device Texterkennung (Vision) — wiederverwendbar für Stapel-Scan und Dublettencheck.
enum OCRService {
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            }
        }
    }

    /// Erkennt den Text auf der ersten Seite eines PDFs.
    ///
    /// Rendern und Erkennen laufen beide abseits des Main Threads. Vorher stand beides in einer
    /// an den MainActor gebundenen View-Methode — die Oberfläche stand für die Dauer der
    /// Texterkennung still.
    static func recognizeFirstPage(ofPDF data: Data) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { return "" }
            let image = page.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox)
            guard let cgImage = image.cgImage else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage).perform([request])

            return (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }.value
    }

    /// PDF aus einem oder mehreren Bildern erzeugen.
    static func pdf(from images: [UIImage]) -> Data {
        let renderer = UIGraphicsPDFRenderer()
        return renderer.pdfData { ctx in
            for img in images {
                let rect = CGRect(origin: .zero, size: img.size)
                ctx.beginPage(withBounds: rect, pageInfo: [:])
                img.draw(in: rect)
            }
        }
    }
}
