import Foundation
import Vision
import UIKit

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
