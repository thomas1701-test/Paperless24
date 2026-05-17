import SwiftUI
import CoreSpotlight

struct DocumentDetailView: View {
    @EnvironmentObject var store: AppStore
    let doc: Document
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int]) -> Void
    let onDelete: (Int) -> Void
    var searchQuery: String = ""

    @State private var pdfData: Data? = nil
    @State private var showEdit = false
    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var selectedTab = 0
    @State private var newNote = ""
    @State private var liveDoc: Document? = nil

    private var displayDoc: Document { liveDoc ?? doc }

    var body: some View {
        VStack {
            Picker("Ansicht", selection: $selectedTab) {
                Text("Dokument").tag(0)
                Text("Text").tag(1)
                Text("Notizen").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selectedTab == 0 {
                if let data = pdfData { PDFKitView(data: data, searchQuery: searchQuery) }
                else { Spacer(); ProgressView(); Spacer() }
            } else if selectedTab == 1 {
                if let content = displayDoc.content, !content.isEmpty {
                    ScrollView {
                        Text(content)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Spacer()
                    Text("Kein OCR-Text vorhanden").foregroundColor(.gray)
                    Spacer()
                }
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
                            let safeName = displayDoc.title.replacingOccurrences(of: "/", with: "-")
                            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).pdf")
                            try? data.write(to: tmp)
                            shareURL = tmp
                            showShare = true
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
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
        if store.fileExists(docId: doc.id) {
            pdfData = try? Data(contentsOf: store.localFileURL(for: doc.id))
            return
        }
        Task {
            guard let api = makeAPI() else { return }
            if let data = try? await api.downloadDocument(id: doc.id) {
                pdfData = data
                try? data.write(to: store.localFileURL(for: doc.id))
            }
        }
    }

    private func makeAPI() -> PaperlessAPI? {
        let token = store.authToken()
        guard !token.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: store.serverUrl, token: token)
    }
}
