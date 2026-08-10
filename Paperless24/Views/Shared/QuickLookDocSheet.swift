import SwiftUI

struct QuickLookDocSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let doc: Document

    @State private var pdfData: Data? = nil
    @AppStorage("pdfDarkMode") private var pdfDarkMode = false
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        NavigationStack {
            Group {
                if let data = pdfData {
                    PDFKitView(
                        data: data,
                        searchQuery: "",
                        darkened: pdfDarkMode && isDarkAppearance(mode: appearanceMode, system: systemScheme)
                    )
                } else {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.3)
                        Text("Lade Dokument...").foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            Task { pdfData = await store.loadPDFData(for: doc.id) }
        }
    }
}
