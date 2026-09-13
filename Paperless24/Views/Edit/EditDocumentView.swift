import SwiftUI
import PDFKit

struct EditDocumentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let document: Document
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int], [CustomFieldEdit]) -> Void
    let onDelete: (Int) -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var correspondent: Int?
    @State private var documentType: Int?
    @State private var asn = ""
    @State private var isFetchingASN = false
    @State private var tags: Set<Int> = []
    @State private var customFields: [CustomFieldEdit] = []
    @State private var showDelete = false
    @State private var pdfData: Data? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Meta") {
                    TextField("Titel", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    HStack {
                        TextField("ASN", text: $asn).keyboardType(.numberPad)
                        // Wer physisch ablegt, braucht die nächste freie Nummer — sie von
                        // Hand zu suchen heißt, das ganze Archiv nach dem Maximum zu
                        // durchsehen.
                        if asn.isEmpty {
                            Button {
                                Task {
                                    isFetchingASN = true
                                    if let next = await store.nextFreeASN() { asn = "\(next)" }
                                    isFetchingASN = false
                                }
                            } label: {
                                if isFetchingASN {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Label("Nächste freie", systemImage: "number")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                MetadataFormSection(
                    correspondent: $correspondent,
                    documentType: $documentType,
                    tags: $tags,
                    date: $date,
                    pdfData: pdfData
                )

                CustomFieldsSection(values: $customFields)

                Section {
                    Button("Löschen", role: .destructive) { showDelete = true }
                }
            }
            .navigationTitle("Bearbeiten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onSave(document.id, title, date, correspondent, documentType, Int(asn), Array(tags), customFields)
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
        customFields = document.customFields
        if let a = document.archiveSerialNumber { asn = "\(a)" }
        // Über `dateObject`, nicht über einen eigenen Formatter: ein Parser, der Millisekunden
        // erzwingt, scheitert an `2026-08-10T00:00:00+02:00` und erst recht am reinen Datum der
        // API-Version 9. `date` bliebe dann auf „heute" stehen — und „Speichern" würde das
        // echte Erstelldatum überschreiben.
        if let d = document.dateObject { date = d }

        if store.fileExists(docId: document.id) {
            let fileURL = store.localFileURL(for: document.id)
            Task {
                pdfData = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: fileURL) }.value
            }
        }
    }
}
