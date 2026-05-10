import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers

struct MainDocView: View {
    @EnvironmentObject var store: AppStore
    let onLogout: () -> Void

    @AppStorage("layoutStyle") private var layoutStyleRaw = LayoutStyle.grid.rawValue
    @AppStorage("sortOrder") private var sortOrderRaw = SortOrder.dateDesc.rawValue

    @State private var searchText = ""
    @State private var filterTag: Int? = nil
    @State private var filterCorr: Int? = nil
    @State private var filterType: Int? = nil
    @State private var filterDate: DateFilter = .all
    @State private var showSettings = false
    @State private var showScanner = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var uploadQueueItem: UploadContainer? = nil
    @State private var isSelectionMode = false
    @State private var selectedDocIDs = Set<Int>()
    @State private var documentToEdit: Document? = nil
    @State private var selectedDocId: Int? = nil
    @State private var deepLinkDoc: Document? = nil
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showDatePickerSheet = false

    private var layoutStyle: LayoutStyle { LayoutStyle(rawValue: layoutStyleRaw) ?? .grid }
    private var sortOrder: SortOrder { SortOrder(rawValue: sortOrderRaw) ?? .dateDesc }

    var body: some View {
        NavigationStack { content }
    }

    var content: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)]),
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            NavigationLink(
                destination: Group {
                    if let d = deepLinkDoc {
                        DocumentDetailView(doc: d, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) })
                    } else { ProgressView() }
                },
                tag: 999999, selection: $selectedDocId
            ) { EmptyView() }

            VStack(spacing: 0) {
                if let err = store.lastSyncError {
                    Text("Fehler: \(err)").font(.caption).foregroundColor(.white)
                        .padding().background(Color.red)
                        .onTapGesture { store.lastSyncError = nil }
                }
                if store.isOffline { Text("Offline").frame(maxWidth: .infinity).background(Color.orange) }
                if store.isSearching {
                    HStack { ProgressView(); Text("Suche...") }
                        .padding().frame(maxWidth: .infinity).background(Color.blue.opacity(0.1))
                }
                if store.isSyncing {
                    ProgressView().padding(5).frame(maxWidth: .infinity).background(Color.blue.opacity(0.1))
                }

                if store.filteredDocs.isEmpty && !store.isSyncing {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60)).foregroundColor(.gray)
                        Text("Keine Dokumente gefunden").font(.title2).foregroundColor(.gray)
                        Button("Laden erzwingen") { store.sync() }
                    }
                    Spacer()
                } else {
                    filterBar.zIndex(1)
                    if layoutStyle == .grid {
                        documentGrid
                            .searchable(text: $searchText)
                            .onChange(of: searchText) { store.runSearch(query: $0) }
                    } else {
                        documentList
                            .searchable(text: $searchText)
                            .onChange(of: searchText) { store.runSearch(query: $0) }
                    }
                }
            }
            .zIndex(0)

            if let msg = store.uploadSuccessMessage {
                Text(msg).padding().background(Color.green).foregroundColor(.white)
                    .cornerRadius(10).shadow(radius: 5).padding(.top, 10).zIndex(1)
            }
            if isSelectionMode {
                VStack {
                    Spacer()
                    HStack {
                        Button("Abbrechen") { isSelectionMode = false }
                        Spacer()
                        Button("Löschen") { bulkDelete() }
                    }
                    .padding().background(Color(.systemBackground)).shadow(radius: 2)
                }
                .zIndex(2)
            }
        }
        .navigationTitle("Bibliothek")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings, onLogout: onLogout)
        }
        .sheet(item: $uploadQueueItem) { container in
            UploadDocumentView(container: container, onUpload: { d, f, t, date, co, ty, ta, comp in
                store.addToQueue(data: d, filename: f, title: t, created: date, corr: co, type: ty, tags: ta)
                comp()
                store.sync()
            }, onCancel: { uploadQueueItem = nil })
        }
        .sheet(item: $documentToEdit) { doc in
            EditDocumentView(document: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) })
        }
        .sheet(isPresented: $showDatePickerSheet) {
            NavigationView {
                Form {
                    DatePicker("Startdatum", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("Enddatum", selection: $customEndDate, displayedComponents: .date)
                }
                .navigationTitle("Zeitraum wählen")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { showDatePickerSheet = false; applyFilters() }
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(isPresented: $showScanner) { data in
                store.handleImportData(data: data, filename: "Scan_\(Date().timeIntervalSince1970).pdf")
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(isPresented: $showPhotoPicker) { data in
                store.handleImportData(data: data, filename: "Photo_\(Date().timeIntervalSince1970).pdf")
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if let url = try? result.get().first { store.handleIncomingFile(url: url) }
        }
        .onReceive(store.$incomingUploadContainer) { container in
            if let c = container { uploadQueueItem = c; store.incomingUploadContainer = nil }
        }
        .alert(item: Binding<String?>(
            get: { store.importErrorMessage },
            set: { store.importErrorMessage = $0 }
        )) { msg in
            Alert(title: Text("Fehler"), message: Text(msg), dismissButton: .default(Text("OK")))
        }
        .onAppear { store.sync() }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let idStr = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let id = Int(idStr) {
                Task {
                    deepLinkDoc = await store.fetchDocumentDetail(id: id)
                    selectedDocId = 999999
                }
            }
        }
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(DateFilter.allCases) { f in
                            Button {
                                filterDate = f
                                if f == .custom { showDatePickerSheet = true } else { applyFilters() }
                            } label: {
                                Label(f.rawValue, systemImage: filterDate == f ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text(filterDate == .all ? "Zeitraum" : filterDate.rawValue)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Material.thickMaterial).cornerRadius(20)
                    }

                    Menu {
                        Button("Alle") { filterTag = nil; applyFilters() }
                        ForEach(store.allTags) { t in
                            Button(t.safeName) { filterTag = t.id; applyFilters() }
                        }
                    } label: {
                        Label(filterTag == nil ? "Tags" : "Tag Aktiv", systemImage: "tag")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Material.thickMaterial).cornerRadius(20)
                    }

                    Menu {
                        Button("Alle") { filterCorr = nil; applyFilters() }
                        ForEach(store.allCorrespondents) { c in
                            Button(c.safeName) { filterCorr = c.id; applyFilters() }
                        }
                    } label: {
                        Label(filterCorr == nil ? "Sender" : "Sender Aktiv", systemImage: "person")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Material.thickMaterial).cornerRadius(20)
                    }

                    Menu {
                        Button("Alle") { filterType = nil; applyFilters() }
                        ForEach(store.allDocTypes) { t in
                            Button(t.safeName) { filterType = t.id; applyFilters() }
                        }
                    } label: {
                        Label(filterType == nil ? "Typ" : "Typ Aktiv", systemImage: "doc")
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Material.thickMaterial).cornerRadius(20)
                    }
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            Divider()
        }
        .background(Material.thickMaterial)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
    }

    // MARK: - Document Grid

    var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 15)], spacing: 15) {
                ForEach(store.filteredDocs) { doc in
                    if isSelectionMode {
                        DocumentCard(
                            doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
                            allTags: store.allTags, allCorrespondents: store.allCorrespondents,
                            isSelected: selectedDocIDs.contains(doc.id)
                        )
                        .onTapGesture {
                            if selectedDocIDs.contains(doc.id) { selectedDocIDs.remove(doc.id) }
                            else { selectedDocIDs.insert(doc.id) }
                        }
                    } else {
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
                        .onAppear {
                            if doc.id == store.filteredDocs.last?.id {
                                Task { await store.loadNextPage() }
                            }
                        }
                    }
                }
                if store.isLoadingMore { ProgressView().padding() }
            }
            .padding()
        }
        .refreshable { await store.loadFirstPage() }
    }

    // MARK: - Document List

    var documentList: some View {
        List {
            ForEach(store.filteredDocs) { doc in
                NavigationLink(
                    destination: DocumentDetailView(doc: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }),
                    tag: doc.id, selection: $selectedDocId
                ) {
                    DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents)
                }
                .swipeActions {
                    Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                    Button { documentToEdit = doc } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                }
                .contextMenu {
                    Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
                    Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                }
                .onAppear {
                    if doc.id == store.filteredDocs.last?.id {
                        Task { await store.loadNextPage() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.loadFirstPage() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button { showScanner = true } label: { Label("Scan", systemImage: "camera") }
                Button { showPhotoPicker = true } label: { Label("Foto", systemImage: "photo") }
                Button { showFilePicker = true } label: { Label("Datei", systemImage: "folder") }
            } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button { isSelectionMode.toggle() } label: { Text(isSelectionMode ? "Fertig" : "Wählen") }
                Menu {
                    ForEach(SortOrder.allCases) { order in
                        Button { sortOrderRaw = order.rawValue; applyFilters() } label: {
                            Label(order.label, systemImage: sortOrder == order ? "checkmark" : "")
                        }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                Button {
                    layoutStyleRaw = (layoutStyle == .grid ? LayoutStyle.list : LayoutStyle.grid).rawValue
                } label: {
                    Image(systemName: layoutStyle == .grid ? "list.bullet" : "square.grid.2x2")
                }
                Button { showSettings = true } label: { Image(systemName: "gear") }
            }
        }
    }

    // MARK: - Helpers

    private func applyFilters() {
        store.currentFilterTag = filterTag
        store.currentFilterCorr = filterCorr
        store.currentFilterType = filterType
        store.currentDateFilter = filterDate
        store.customStartDate = customStartDate
        store.customEndDate = customEndDate
        store.currentSortOrder = sortOrder
        store.updateFilteredDocs()
    }

    private func updateDocument(id: Int, title: String, date: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int]) {
        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags)
    }

    private func bulkDelete() {
        for id in selectedDocIDs { store.deleteDocument(id: id) }
        isSelectionMode = false
        selectedDocIDs.removeAll()
    }
}
