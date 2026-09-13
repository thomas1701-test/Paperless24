import SwiftUI

struct UploadDocumentView: View {
    @EnvironmentObject var store: AppStore
    let container: UploadContainer
    /// Die Daten, die tatsächlich hochgeladen werden — nach dem Bearbeiten der Seiten kann
    /// das eine andere Fassung sein als die übergebene.
    @State private var payload: Data? = nil
    @State private var showPageEditor = false
    let onUpload: (Data, String, String, Date, Int?, Int?, [Int], @escaping () -> Void) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var correspondent: Int?
    @State private var documentType: Int?
    @State private var tags: Set<Int> = []
    @State private var isUploading = false
    /// Name der Regel, die vorbelegt hat — als Hinweis im Formular.
    @State private var appliedRuleName: String? = nil
    /// Treffer der Dublettenprüfung — Warnung, keine Sperre.
    @State private var duplicate: AppStore.DuplicateWarning? = nil
    @State private var isCheckingDuplicate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorschau") {
                    HStack {
                        Image(systemName: "doc.text.fill").font(.largeTitle).foregroundColor(.red)
                        Text(container.filename).lineLimit(1)
                        if isCheckingDuplicate {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                    Button {
                        showPageEditor = true
                    } label: {
                        Label(payload == nil ? "Seiten bearbeiten" : "Seiten bearbeitet ✓",
                              systemImage: "doc.on.doc")
                    }
                }

                if let duplicate {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Schon im Archiv?", systemImage: "doc.on.doc.fill")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Text(duplicate.document.title).font(.subheadline).lineLimit(2)
                            // Der Grund macht die Warnung prüfbar — ohne ihn bliebe nur
                            // Vertrauen in eine Zahl.
                            Text("Übereinstimmung: \(duplicate.reason)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } footer: {
                        Text("Nur ein Hinweis — hochladen lässt es sich trotzdem. Der Server "
                             + "prüft beim Verarbeiten noch einmal selbst.")
                    }
                }

                Section {
                    TextField("Titel", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Meta")
                } footer: {
                    if let appliedRuleName, !appliedRuleName.isEmpty {
                        Label("Vorbelegt durch Regel \(appliedRuleName)", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                }

                MetadataFormSection(
                    correspondent: $correspondent,
                    documentType: $documentType,
                    tags: $tags,
                    date: $date,
                    pdfData: payload ?? container.data
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
                            onUpload(payload ?? container.data, container.filename, title, date, correspondent, documentType, Array(tags)) {
                                isUploading = false
                                onCancel()
                            }
                        }
                    }
                }
            }
            .onAppear(perform: prefill)
            .task { await checkForDuplicate() }
            .sheet(isPresented: $showPageEditor) {
                PageEditorView(data: payload ?? container.data) { edited in
                    payload = edited
                    // Nach dem Bearbeiten erneut prüfen: Wer die erste Seite entfernt hat, hat
                    // womöglich ein ganz anderes Dokument vor sich.
                    Task { await checkForDuplicate() }
                }
            }
        }
    }

    /// Prüft vor dem Upload, ob dasselbe Dokument schon im Archiv liegt.
    ///
    /// Läuft über die Texterkennung der ersten Seite — mehr braucht es nicht, Belegnummer und
    /// Betrag stehen dort. Schlägt sie fehl, passiert schlicht nichts.
    private func checkForDuplicate() async {
        guard store.isDuplicateCheckEnabled else { return }
        isCheckingDuplicate = true
        let text = await OCRService.recognizeFirstPage(ofPDF: payload ?? container.data)
        duplicate = await store.checkForDuplicate(text: text)
        isCheckingDuplicate = false
    }

    /// Formular vorbelegen.
    ///
    /// Erst die passende Import-Regel, dann der Dateiname als Titel. Die Regel füllt nur
    /// Felder, die noch leer sind — wer den Dialog schon bearbeitet hat, soll seine Eingabe
    /// nicht von einer Regel überschrieben bekommen.
    private func prefill() {
        if let rule = store.uploadRule(for: container.filename) {
            if correspondent == nil { correspondent = rule.correspondent }
            if documentType == nil { documentType = rule.documentType }
            if tags.isEmpty { tags = Set(rule.tags) }
            if title.isEmpty, let ruleTitle = rule.title(for: container.filename, date: date) {
                title = ruleTitle
            }
            appliedRuleName = rule.name
        }
        if title.isEmpty {
            title = (container.filename as NSString).deletingPathExtension
        }
    }
}
