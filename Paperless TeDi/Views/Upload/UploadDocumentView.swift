import SwiftUI

struct UploadDocumentView: View {
    @EnvironmentObject var store: AppStore
    let container: UploadContainer
    let onUpload: (Data, String, String, Date, Int?, Int?, [Int], @escaping () -> Void) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var correspondent: Int?
    @State private var documentType: Int?
    @State private var tags: Set<Int> = []
    @State private var isUploading = false

    var body: some View {
        NavigationView {
            Form {
                Section("Vorschau") {
                    HStack {
                        Image(systemName: "doc.text.fill").font(.largeTitle).foregroundColor(.red)
                        Text(container.filename).lineLimit(1)
                    }
                }

                Section("Meta") {
                    TextField("Titel", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }

                MetadataFormSection(
                    correspondent: $correspondent,
                    documentType: $documentType,
                    tags: $tags,
                    date: $date,
                    pdfData: container.data
                )
            }
            .navigationTitle("Import")
            .interactiveDismissDisabled(isUploading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbruch") { onCancel() }.disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Button("Upload") {
                            isUploading = true
                            onUpload(container.data, container.filename, title, date, correspondent, documentType, Array(tags)) {
                                isUploading = false
                                onCancel()
                            }
                        }
                    }
                }
            }
            .onAppear {
                if title.isEmpty { title = container.filename.replacingOccurrences(of: ".pdf", with: "") }
            }
        }
    }
}
