import SwiftUI
import PDFKit

/// PDF-Anzeige. Optional mit abgedunkelten Seiten: PDFKit zeichnet auch im Dunkelmodus
/// weiße Seiten, was nachts blendet.
///
/// Die Abdunklung passiert bewusst in SwiftUI (`colorInvert` + `hueRotation`) und nicht über
/// `CALayer.filters` — das ist private API und riskiert die App-Store-Abnahme. Die Drehung um
/// 180° holt die Farbtöne zurück, die die Invertierung verschiebt; rein farbige Fotos bleiben
/// trotzdem eine Näherung.
struct PDFKitView: View {
    let data: Data
    var searchQuery: String = ""
    /// Vom Aufrufer entschieden: Einstellung aktiv **und** Dunkelmodus aktiv.
    var darkened: Bool = false

    var body: some View {
        PDFKitRepresentable(data: data, searchQuery: searchQuery)
            .modifier(DarkenedPDF(active: darkened))
    }
}

private struct DarkenedPDF: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .colorInvert()
                .hueRotation(.degrees(180))
                .background(Color.black)
        } else {
            content
        }
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    let data: Data
    var searchQuery: String = ""

    class Coordinator {
        /// Merkt sich, welche Daten gerade angezeigt werden.
        ///
        /// Vorher stand hier ein Vergleich gegen `uiView.document?.dataRepresentation()` — der
        /// serialisiert bei *jedem* `updateUIView` das komplette PDF neu, nur um es Byte für Byte
        /// zu vergleichen. Bei einem großen Scan ist das jedes Mal ein sichtbarer Aussetzer.
        var loadedData: Data?
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
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
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
