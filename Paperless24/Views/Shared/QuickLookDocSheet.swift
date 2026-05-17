import SwiftUI

struct QuickLookDocSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let doc: Document

    @State private var pdfData: Data? = nil

    var body: some View {
        NavigationView {
            Group {
                if let data = pdfData {
                    PDFKitView(data: data, searchQuery: "")
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
