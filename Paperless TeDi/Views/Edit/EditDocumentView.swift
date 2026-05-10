import SwiftUI
import PDFKit

struct EditDocumentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let document: Document
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int]) -> Void
    let onDelete: (Int) -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var correspondent: Int?
    @State private var documentType: Int?
    @State private var asn = ""
    @State private var tags: Set<Int> = []
    @State private var showDelete = false
    @State private var pdfData: Data? = nil

    var body: some View {
        NavigationView {
            Form {
                Section("Meta") {
                    TextField("Titel", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("ASN", text: $asn).keyboardType(.numberPad)
                }

                MetadataFormSection(
                    correspondent: $correspondent,
                    documentType: $documentType,
                    tags: $tags,
                    date: $date,
                    pdfData: pdfData
                )

                Section {
                    Button("Löschen", role: .destructive) { showDelete = true }
                }
            }
            .navigationTitle("Bearbeiten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onSave(document.id, title, date, correspondent, documentType, Int(asn), Array(tags))
                        dismiss()
                    }
                }
            }
            .alert("Löschen?", isPresented: $showDelete) {
                Button("Ja", role: .destructive) { onDelete(document.id); dismiss() }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        title = document.title
        tags = Set(document.tags)
        correspondent = document.correspondent
        documentType = document.documentType
        if let a = document.archiveSerialNumber { asn = "\(a)" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: document.created) { date = d }

        if store.fileExists(docId: document.id) {
            pdfData = try? Data(contentsOf: store.localFileURL(for: document.id))
        }
    }
}
