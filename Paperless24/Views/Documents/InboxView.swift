import SwiftUI

struct InboxView: View {
    @EnvironmentObject var store: AppStore

    @AppStorage("layoutStyle") private var layoutStyleRaw = LayoutStyle.grid.rawValue
    @State private var selectedDocId: Int? = nil
    @State private var documentToEdit: Document? = nil

    private var layoutStyle: LayoutStyle { LayoutStyle(rawValue: layoutStyleRaw) ?? .grid }

    private var inboxDocs: [Document] {
        store.documents.filter { $0.correspondent == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isSyncing && store.documents.isEmpty {
                    ProgressView("Lade...").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if inboxDocs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray").font(.system(size: 60)).foregroundColor(.gray)
                        Text("Posteingang leer").font(.title2).foregroundColor(.gray)
                        Text("Alle Dokumente haben einen Sender.")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if layoutStyle == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                            ForEach(inboxDocs) { doc in
                                NavigationLink(
                                    destination: DocumentDetailView(doc: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }),
                                    tag: doc.id, selection: $selectedDocId
                                ) {
                                    DocumentCard(
                                        doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
                                        allTags: store.allTags, allCorrespondents: store.allCorrespondents
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
                                    Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .refreshable { await store.loadFirstPage() }
                } else {
                    List {
                        ForEach(inboxDocs) { doc in
                            NavigationLink(
                                destination: DocumentDetailView(doc: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }),
                                tag: doc.id, selection: $selectedDocId
                            ) {
                                DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents, serverBase: store.makeServerBase(), token: store.authToken())
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.haptic(.heavy); store.deleteDocument(id: doc.id) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                                Button { documentToEdit = doc } label: {
                                    Label("Bearbeiten", systemImage: "pencil")
                                }.tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.loadFirstPage() }
                }
            }
            .navigationTitle("Posteingang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(inboxDocs.count) \(String(localized: "unbearbeitet"))")
                        .font(.caption).foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        layoutStyleRaw = (layoutStyle == .grid ? LayoutStyle.list : LayoutStyle.grid).rawValue
                    } label: {
                        Image(systemName: layoutStyle == .grid ? "list.bullet" : "square.grid.2x2")
                    }
                }
            }
            .sheet(item: $documentToEdit) { doc in
                EditDocumentView(document: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) })
            }
        }
    }

    private func updateDocument(id: Int, title: String, date: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int]) {
        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags)
    }
}
