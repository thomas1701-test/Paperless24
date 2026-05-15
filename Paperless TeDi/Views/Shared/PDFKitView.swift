import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let data: Data
    var searchQuery: String = ""

    class Coordinator {
        var lastHighlightedQuery = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        var documentChanged = false
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
            documentChanged = true
        }
        if documentChanged || context.coordinator.lastHighlightedQuery != searchQuery {
            context.coordinator.lastHighlightedQuery = searchQuery
            highlight(in: uiView)
        }
    }

    private func highlight(in pdfView: PDFView) {
        guard !searchQuery.isEmpty, let doc = pdfView.document else {
            pdfView.highlightedSelections = nil
            return
        }
        let selections = doc.findString(searchQuery, withOptions: .caseInsensitive)
        pdfView.highlightedSelections = selections
        if let first = selections.first { pdfView.go(to: first) }
    }
}
