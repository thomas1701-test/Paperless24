import SwiftUI
import CoreSpotlight
import Translation

struct DocumentDetailView: View {
    @EnvironmentObject var store: AppStore
    let doc: Document
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int], [CustomFieldEdit]) -> Void
    let onDelete: (Int) -> Void
    var searchQuery: String = ""

    @State private var pdfData: Data? = nil
    @State private var showEdit = false
    @State private var showShare = false
    @State private var showShareLink = false
    @State private var showTranslation = false
    @State private var shareURL: URL? = nil
    @State private var selectedTab = 0
    @AppStorage("translationEnabled") private var translationEnabled = true
    @AppStorage("pdfDarkMode") private var pdfDarkMode = false
    @AppStorage("readingMode") private var readingMode = false
    @AppStorage("readingFontSize") private var readingFontSize: Double = 17
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.palette) private var palette

    /// Papierton für den Lesemodus — im Dunkeln nicht sinnvoll, dort bleibt es dunkel.
    private var readingBackground: Color {
        isDarkAppearance(mode: appearanceMode, system: systemScheme)
            ? Color(.systemBackground)
            : Color(hex: "F6EEDC")
    }
    @State private var newNote = ""
    @State private var liveDoc: Document? = nil
    @State private var loadError: String? = nil

    private var displayDoc: Document { liveDoc ?? doc }

    var body: some View {
        VStack {
            Picker("Ansicht", selection: $selectedTab) {
                Text("Dokument").tag(0)
                Text("Text").tag(1)
                Text("Info").tag(2)
                Text("Notizen").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selectedTab == 0 {
                if let data = pdfData {
                    PDFKitView(
                        data: data,
                        searchQuery: searchQuery,
                        darkened: pdfDarkMode && isDarkAppearance(mode: appearanceMode, system: systemScheme)
                    )
                } else if let loadError {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40)).foregroundColor(.orange)
                        Text("Dokument konnte nicht geladen werden")
                            .font(.headline).multilineTextAlignment(.center)
                        Text(loadError)
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Erneut versuchen") {
                            self.loadError = nil
                            loadContent()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    Spacer()
                } else {
                    Spacer(); ProgressView(); Spacer()
                }
            } else if selectedTab == 1 {
                if let content = displayDoc.content, !content.isEmpty {
                    ScrollView {
                        LinkifiedText(text: content)
                            .font(readingMode ? .system(size: readingFontSize, design: .serif) : .body)
                            .lineSpacing(readingMode ? 6 : 0)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(readingMode ? readingBackground : (palette.surface ?? Color(.systemBackground)))
                } else {
                    Spacer()
                    Text("Kein OCR-Text vorhanden").foregroundColor(.gray)
                    Spacer()
                }
            } else if selectedTab == 2 {
                DocumentInfoView(doc: displayDoc)
            } else {
                VStack {
                    List {
                        ForEach(displayDoc.safeNotes) { note in
                            VStack(alignment: .leading) {
                                Text(note.note).font(.body)
                                Text(note.created ?? "").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .onDelete(perform: deleteNote)
                    }
                    .themedSurface(palette)
                    HStack {
                        TextField("Neue Notiz...", text: $newNote).textFieldStyle(.roundedBorder)
                        Button { Task { await addNote() } } label: {
                            Image(systemName: "paperplane.fill")
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle(displayDoc.title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        if let data = pdfData {
                            ShareStaging.cleanUp()
                            shareURL = ShareStaging.stage(data, filename: "\(displayDoc.title).pdf")
                            showShare = shareURL != nil
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    Button { showShareLink = true } label: { Image(systemName: "link") }
                    if translationEnabled, let c = displayDoc.content, !c.isEmpty {
                        Button { showTranslation = true } label: { Image(systemName: "translate") }
                    }
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showShareLink) {
            ShareLinkSheet(documentId: doc.id)
        }
        .translationPresentation(isPresented: $showTranslation, text: displayDoc.content ?? "")
        .onChange(of: showTranslation) { wasShown, isShown in
            if wasShown && !isShown { store.registerReviewEvent() }
        }
        .sheet(isPresented: $showEdit) {
            EditDocumentView(document: doc, onSave: onSave, onDelete: onDelete)
        }
        .onAppear {
            loadContent()
            Task { liveDoc = await store.fetchDocumentDetail(id: doc.id) }
        }
    }

    private func addNote() async {
        guard !newNote.isEmpty else { return }
        let success = await store.addNote(docId: doc.id, text: newNote)
        if success {
            newNote = ""
            liveDoc = await store.fetchDocumentDetail(id: doc.id)
        }
    }

    private func deleteNote(at offsets: IndexSet) {
        let notes = displayDoc.safeNotes
        Task {
            for index in offsets {
                let note = notes[index]
                let success = await store.deleteNote(docId: doc.id, noteId: note.id)
                if success { liveDoc = await store.fetchDocumentDetail(id: doc.id) }
            }
        }
    }

    private func loadContent() {
        // Vor dem Download festhalten — siehe `AppStore.loadPDFData(for:)`.
        let fileURL = store.localFileURL(for: doc.id)
        if store.fileExists(docId: doc.id) {
            // Abseits des Main Threads: Ein großer Scan hielt beim Öffnen sonst die Oberfläche an.
            Task {
                pdfData = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: fileURL) }.value
            }
            return
        }
        Task {
            guard let api = makeAPI() else {
                loadError = String(localized: "Kein gültiges Login")
                return
            }
            do {
                let data = try await api.downloadDocument(id: doc.id)
                pdfData = data
                try? PersistenceService.writeFile(data, to: fileURL)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func makeAPI() -> PaperlessAPI? {
        let token = store.authToken()
        guard !token.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: store.serverUrl, token: token)
    }
}
