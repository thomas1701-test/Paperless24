import SwiftUI

struct InboxView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.locale) private var locale
    @Environment(\.palette) private var palette

    @AppStorage("layoutStyle") private var layoutStyleRaw = LayoutStyle.grid.rawValue
    /// Push-Stack. `NavigationLink(tag:selection:)` löst in einer `NavigationStack`
    /// nicht mehr aus — Tippen blieb wirkungslos.
    @State private var navPath: [Document] = []
    @State private var documentToEdit: Document? = nil
    @State private var isSelectionMode = false
    @State private var selectedIDs = Set<Int>()
    @State private var showTriage = false

    private var layoutStyle: LayoutStyle { LayoutStyle(rawValue: layoutStyleRaw) ?? .grid }

    /// Posteingang = Dokumente mit Inbox-Tag, vom Server geliefert (siehe `AppStore.loadInbox()`).
    private var inboxDocs: [Document] { store.inboxDocuments }

    /// Ohne Inbox-Tag auf dem Server gibt es nichts abzuarbeiten — dann bleiben die
    /// Erledigt-Aktionen aus, statt wirkungslos dazustehen.
    private var canComplete: Bool { !store.inboxTagIDs.isEmpty }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if store.isLoadingInbox && inboxDocs.isEmpty {
                    ProgressView("Lade...").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if inboxDocs.isEmpty {
                    emptyState
                } else if layoutStyle == .grid {
                    gridContent
                } else {
                    listContent
                }
            }
            // Dieselbe Linie wie in der Dokumentliste — auch hier ohne Platz im Layout.
            .overlay(alignment: .top) {
                if store.isLoadingInbox && !inboxDocs.isEmpty {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(palette.accent)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.isLoadingInbox)
            .navigationDestination(for: Document.self) { doc in
                DocumentPagerView(documents: inboxDocs, startId: doc.id,
                                  onSave: updateDocument,
                                  onDelete: { store.deleteDocument(id: $0) })
            }
            .task { await store.loadInbox() }
            .navigationTitle("Posteingang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $documentToEdit) { doc in
                EditDocumentView(document: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) })
            }
            .fullScreenCover(isPresented: $showTriage) {
                TriageView()
            }
        }
    }

    // MARK: - Inhalte

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray").font(.system(size: 60)).foregroundColor(.gray)
            Text("Posteingang leer").font(.title2).foregroundColor(.gray)
            Text(store.inboxTagIDs.isEmpty
                 ? "Auf dem Server ist kein Tag als Posteingang markiert."
                 : "Alle Dokumente sind bearbeitet.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(inboxDocs) { doc in
                    Group {
                        if isSelectionMode {
                            Button { toggle(doc.id) } label: { card(doc) }
                                .buttonStyle(PlainButtonStyle())
                        } else {
                            NavigationLink(value: doc) { card(doc) }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu { contextActions(for: doc) }
                        }
                    }
                }
            }
            .padding(10)
        }
        .refreshable { await store.loadInbox() }
    }

    private func card(_ doc: Document) -> some View {
        DocumentCard(
            doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
            allTags: store.allTags, allCorrespondents: store.allCorrespondents,
            isSelected: selectedIDs.contains(doc.id)
        )
    }

    private var listContent: some View {
        List {
            ForEach(inboxDocs) { doc in
                Group {
                    if isSelectionMode {
                        Button { toggle(doc.id) } label: {
                            HStack {
                                Image(systemName: selectedIDs.contains(doc.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedIDs.contains(doc.id) ? palette.accent : .secondary)
                                row(doc)
                            }
                        }
                        .foregroundColor(.primary)
                    } else {
                        NavigationLink(value: doc) { row(doc) }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if canComplete {
                        Button { store.markAsDone([doc.id]) } label: {
                            Label("Erledigt", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing) {
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
        .themedSurface(palette)
        .refreshable { await store.loadInbox() }
    }

    private func row(_ doc: Document) -> some View {
        DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents,
                    serverBase: store.makeServerBase(), token: store.authToken(),
                    allDocTypes: store.allDocTypes)
    }

    @ViewBuilder
    private func contextActions(for doc: Document) -> some View {
        if canComplete {
            Button { store.markAsDone([doc.id]) } label: {
                Label("Erledigt", systemImage: "checkmark.circle")
            }
        }
        Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: {
            Label("Löschen", systemImage: "trash")
        }
    }

    // MARK: - Werkzeugleiste

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(isSelectionMode
                 ? "\(selectedIDs.count) \(String(localized: "ausgewählt", locale: locale))"
                 : "\(inboxDocs.count) \(String(localized: "unbearbeitet", locale: locale))")
                .font(.caption).foregroundColor(.secondary)
        }
        if isSelectionMode {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Abbrechen") { isSelectionMode = false; selectedIDs.removeAll() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        selectedIDs = Set(inboxDocs.map(\.id))
                    } label: { Label("Alle auswählen", systemImage: "checkmark.circle") }

                    if !selectedIDs.isEmpty {
                        if canComplete {
                            Button {
                                store.markAsDone(selectedIDs)
                                isSelectionMode = false; selectedIDs.removeAll()
                            } label: { Label("Als erledigt markieren", systemImage: "tray.and.arrow.down") }
                        }
                        Button(role: .destructive) {
                            for id in selectedIDs { store.deleteDocument(id: id) }
                            isSelectionMode = false; selectedIDs.removeAll()
                        } label: { Label("Löschen", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if canComplete && !inboxDocs.isEmpty {
                        Button { showTriage = true } label: {
                            Label("Durchwischen", systemImage: "rectangle.stack")
                        }
                    }
                    Button { isSelectionMode = true } label: {
                        Label("Auswählen", systemImage: "checkmark.circle")
                    }
                    Button {
                        layoutStyleRaw = (layoutStyle == .grid ? LayoutStyle.list : LayoutStyle.grid).rawValue
                    } label: {
                        Label(layoutStyle == .grid ? "Als Liste" : "Als Raster",
                              systemImage: layoutStyle == .grid ? "list.bullet" : "square.grid.2x2")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    // MARK: - Aktionen

    private func toggle(_ id: Int) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func updateDocument(id: Int, title: String, date: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int], customFields: [CustomFieldEdit]) {
        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags, customFields: customFields)
    }
}
