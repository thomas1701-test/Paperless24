import SwiftUI

/// Blättert seitenweise durch die Dokumente der Liste.
///
/// Vorher zeigte die Detailansicht genau ein Dokument: zurück zur Liste, nächstes antippen,
/// wieder zurück. Beim Durchsehen eines Monats sind das zwei Tipps pro Dokument.
///
/// Das Fenster um das gewählte Dokument ist bewusst begrenzt: Ein `TabView` im Seitenstil legt
/// seine Seiten nicht zuverlässig erst bei Bedarf an, und bei einem Archiv mit einigen tausend
/// Dokumenten wäre das eine spürbare Bremse. Erreicht man den Rand, wächst das Fenster nach.
struct DocumentPagerView: View {
    let documents: [Document]
    let startId: Int
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int], [CustomFieldEdit]) -> Void
    let onDelete: (Int) -> Void
    var searchQuery: String = ""

    /// Seiten je Richtung, die vorgehalten werden.
    private static let windowRadius = 40
    /// Abstand zum Rand, ab dem nachgeladen wird.
    private static let growThreshold = 5

    @State private var selection: Int = 0
    @State private var lowerBound = 0
    @State private var upperBound = 0
    @State private var didSetUp = false

    private var window: [Document] {
        guard !documents.isEmpty else { return [] }
        let lower = max(0, lowerBound)
        let upper = min(documents.count - 1, upperBound)
        guard lower <= upper else { return documents }
        return Array(documents[lower...upper])
    }

    var body: some View {
        Group {
            if documents.count <= 1, let single = documents.first ?? currentDocument {
                DocumentDetailView(doc: single, onSave: onSave, onDelete: onDelete,
                                   searchQuery: searchQuery)
            } else {
                TabView(selection: $selection) {
                    ForEach(window) { doc in
                        DocumentDetailView(doc: doc, onSave: onSave, onDelete: onDelete,
                                           searchQuery: searchQuery)
                            .tag(doc.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selection) { growWindowIfNeeded() }
            }
        }
        .onAppear(perform: setUp)
    }

    private var currentDocument: Document? {
        documents.first { $0.id == selection }
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        selection = startId
        let index = documents.firstIndex { $0.id == startId } ?? 0
        lowerBound = max(0, index - Self.windowRadius)
        upperBound = min(max(documents.count - 1, 0), index + Self.windowRadius)
    }

    private func growWindowIfNeeded() {
        guard let index = documents.firstIndex(where: { $0.id == selection }) else { return }
        if index - lowerBound < Self.growThreshold {
            lowerBound = max(0, lowerBound - Self.windowRadius)
        }
        if upperBound - index < Self.growThreshold {
            upperBound = min(documents.count - 1, upperBound + Self.windowRadius)
        }
    }
}
