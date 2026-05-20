import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers

struct MainDocView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.locale) private var locale

    @AppStorage("layoutStyle") private var layoutStyleRaw = LayoutStyle.grid.rawValue
    @AppStorage("sortOrder") private var sortOrderRaw = SortOrder.dateDesc.rawValue

    @State private var searchText = ""
    @State private var filterTag: Int? = nil
    @State private var filterCorr: Int? = nil
    @State private var filterType: Int? = nil
    @State private var filterDate: DateFilter = .all
    @State private var showScanner = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var uploadQueueItem: UploadContainer? = nil
    @State private var isSelectionMode = false
    @State private var selectedDocIDs = Set<Int>()
    @State private var isBulkSharing = false
    @State private var bulkShareURLs: [URL] = []
    @State private var showBulkShare = false
    @State private var documentToEdit: Document? = nil
    @State private var quickTagDoc: Document? = nil
    @State private var selectedDocId: Int? = nil
    @State private var deepLinkDoc: Document? = nil
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showDatePickerSheet = false
    @State private var showTagPicker = false
    @State private var showCorrPicker = false
    @State private var showTypePicker = false
    @State private var showSaveFilterSheet = false
    @State private var saveFilterName = ""
    @State private var quickLookDoc: Document? = nil

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
                        DocumentDetailView(doc: d, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }, searchQuery: searchText)
                    } else { ProgressView() }
                },
                tag: 999999, selection: $selectedDocId
            ) { EmptyView() }

            VStack(spacing: 0) {
                if let err = store.lastSyncError {
                    HStack {
                        Text("Fehler: \(err)").font(.caption).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        Button { Task { await store.loadFirstPage() } } label: {
                            Image(systemName: "arrow.clockwise").foregroundColor(.white)
                        }
                        Button { store.lastSyncError = nil } label: {
                            Image(systemName: "xmark").foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color.red)
                }
                if store.isOffline {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Offline – letzte Daten werden angezeigt")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding(6).background(Color.orange).foregroundColor(.white)
                }
                if store.isSearching {
                    HStack { ProgressView(); Text("Suche...").font(.caption) }
                        .padding(6).frame(maxWidth: .infinity).background(Color.blue.opacity(0.1))
                }
                if store.isSyncing && !store.documents.isEmpty {
                    ProgressView().padding(5).frame(maxWidth: .infinity).background(Color.blue.opacity(0.07))
                }

                if store.documents.isEmpty && store.isSyncing {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Dokumente werden geladen...").foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    filterBar.zIndex(1)
                    if store.filteredDocs.isEmpty && !store.isSyncing {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60)).foregroundColor(.gray)
                            Text("Keine Dokumente gefunden").font(.title2).foregroundColor(.gray)
                            Button("Laden erzwingen") { store.sync() }
                        }
                        Spacer()
                    } else if layoutStyle == .grid {
                        documentGrid
                            .searchable(text: $searchText)
                            .searchSuggestions {
                                if searchText.isEmpty {
                                    ForEach(store.recentSearches, id: \.self) { recent in
                                        Label(recent, systemImage: "clock").searchCompletion(recent)
                                    }
                                }
                            }
                            .onChange(of: searchText) { store.runSearch(query: $0) }
                    } else {
                        documentList
                            .searchable(text: $searchText)
                            .searchSuggestions {
                                if searchText.isEmpty {
                                    ForEach(store.recentSearches, id: \.self) { recent in
                                        Label(recent, systemImage: "clock").searchCompletion(recent)
                                    }
                                }
                            }
                            .onChange(of: searchText) { store.runSearch(query: $0) }
                    }
                }
            }
            .zIndex(0)

            if let msg = store.uploadSuccessMessage {
                Text(msg).padding().background(Color.green).foregroundColor(.white)
                    .cornerRadius(10).shadow(radius: 5).padding(.top, 10).zIndex(1)
            }
            if !store.pendingUploads.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("\(store.pendingUploads.count) Upload\(store.pendingUploads.count > 1 ? "s" : "") \(String(localized: "uploads_ausstehend", locale: locale))")
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Material.thickMaterial)
                    .shadow(radius: 3)
                }
                .zIndex(2)
                .ignoresSafeArea(edges: .bottom)
            }
            if isSelectionMode {
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        Button("Abbrechen") { isSelectionMode = false; selectedDocIDs.removeAll() }
                            .frame(maxWidth: .infinity)
                        if !selectedDocIDs.isEmpty {
                            Menu {
                                ForEach(store.allTags) { tag in
                                    Button(tag.safeName) {
                                        store.bulkAssignTags([tag.id], to: selectedDocIDs)
                                        store.haptic(.medium)
                                    }
                                }
                            } label: { Image(systemName: "tag").frame(maxWidth: .infinity) }
                            Menu {
                                ForEach(store.allCorrespondents) { corr in
                                    Button(corr.safeName) {
                                        store.bulkAssignCorrespondent(corr.id, to: selectedDocIDs)
                                        store.haptic(.medium)
                                    }
                                }
                            } label: { Image(systemName: "person").frame(maxWidth: .infinity) }
                            if isBulkSharing {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Button {
                                    Task { await bulkShare() }
                                } label: { Image(systemName: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            }
                            Button(role: .destructive) { bulkDelete() } label: {
                                Image(systemName: "trash").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .font(.system(size: 20))
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground)).shadow(radius: 2)
                }
                .zIndex(2)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
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
        .sheet(item: $quickTagDoc) { doc in
            QuickTagSheet(doc: doc)
        }
        .sheet(item: $quickLookDoc) { doc in
            QuickLookDocSheet(doc: doc)
        }
        .alert("Filter speichern", isPresented: $showSaveFilterSheet) {
            TextField("Name", text: $saveFilterName)
            Button("Speichern") {
                if !saveFilterName.isEmpty {
                    store.saveCurrentFilter(name: saveFilterName, tag: filterTag, correspondent: filterCorr, type: filterType, dateFilter: filterDate)
                    saveFilterName = ""
                }
            }
            Button("Abbrechen", role: .cancel) { saveFilterName = "" }
        } message: {
            Text("Name für diesen Filter:")
        }
        .sheet(isPresented: $showBulkShare) {
            ShareSheet(items: bulkShareURLs)
        }
        .sheet(isPresented: $showTagPicker, onDismiss: applyFilters) {
            FilterPickerSheet(
                title: "Tags",
                items: store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                selectedId: $filterTag
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCorrPicker, onDismiss: applyFilters) {
            FilterPickerSheet(
                title: "Sender",
                items: store.allCorrespondents.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                selectedId: $filterCorr
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTypePicker, onDismiss: applyFilters) {
            FilterPickerSheet(
                title: "Typen",
                items: store.allDocTypes.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                selectedId: $filterType
            )
            .presentationDetents([.medium, .large])
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
        .alert("Fehler", isPresented: Binding<Bool>(
            get: { store.importErrorMessage != nil },
            set: { if !$0 { store.importErrorMessage = nil } }
        )) {
            Button("OK") { store.importErrorMessage = nil }
        } message: {
            Text(store.importErrorMessage ?? "")
        }
        .onAppear { applyFilters(); store.sync() }
        .onChange(of: store.widgetOpenDocId) { id in
            guard let id else { return }
            store.widgetOpenDocId = nil
            if let existing = store.documents.first(where: { $0.id == id }) {
                deepLinkDoc = existing
                selectedDocId = 999999
            } else {
                Task {
                    deepLinkDoc = await store.fetchDocumentDetail(id: id)
                    selectedDocId = 999999
                }
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let idStr = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let id = Int(idStr) {
                if let existing = store.documents.first(where: { $0.id == id }) {
                    deepLinkDoc = existing
                    selectedDocId = 999999
                } else {
                    Task {
                        deepLinkDoc = await store.fetchDocumentDetail(id: id)
                        selectedDocId = 999999
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private func chipBackground(active: Bool) -> Color {
        active ? Color.accentColor : Color.accentColor.opacity(0.1)
    }

    private func chipForeground(active: Bool) -> Color {
        active ? .white : .accentColor
    }

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
                                Label(LocalizedStringKey(f.rawValue), systemImage: filterDate == f ? "checkmark" : "")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text(LocalizedStringKey(filterDate == .all ? "Zeitraum" : filterDate.rawValue))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(chipForeground(active: filterDate != .all))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(chipBackground(active: filterDate != .all))
                        .cornerRadius(8)
                    }

                    Button { showTagPicker = true } label: {
                        Group {
                            if filterTag == nil {
                                Label("Tags", systemImage: "tag")
                            } else {
                                Label(store.allTags.first { $0.id == filterTag }?.safeName ?? "Tag", systemImage: "tag")
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(chipForeground(active: filterTag != nil))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(chipBackground(active: filterTag != nil))
                        .cornerRadius(8)
                    }

                    Button { showCorrPicker = true } label: {
                        Group {
                            if filterCorr == nil {
                                Label("Sender", systemImage: "person")
                            } else {
                                Label(store.allCorrespondents.first { $0.id == filterCorr }?.safeName ?? "Sender", systemImage: "person")
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(chipForeground(active: filterCorr != nil))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(chipBackground(active: filterCorr != nil))
                        .cornerRadius(8)
                    }

                    Button { showTypePicker = true } label: {
                        Group {
                            if filterType == nil {
                                Label("Typ", systemImage: "doc")
                            } else {
                                Label(store.allDocTypes.first { $0.id == filterType }?.safeName ?? "Typ", systemImage: "doc")
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(chipForeground(active: filterType != nil))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(chipBackground(active: filterType != nil))
                        .cornerRadius(8)
                    }

                    if filterTag != nil || filterCorr != nil || filterType != nil || filterDate != .all {
                        Button {
                            showSaveFilterSheet = true
                        } label: {
                            Label("Speichern", systemImage: "bookmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.accentColor.opacity(0.1)).cornerRadius(8)
                        }
                        Button {
                            filterTag = nil; filterCorr = nil; filterType = nil; filterDate = .all
                            applyFilters(); store.haptic(.light)
                        } label: {
                            Label("Zurücksetzen", systemImage: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.red.opacity(0.1)).cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal).padding(.vertical, 5)
            }

            if !store.savedFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.savedFilters) { saved in
                            Button {
                                filterTag = saved.tag
                                filterCorr = saved.correspondent
                                filterType = saved.type
                                filterDate = saved.dateFilter
                                applyFilters()
                                store.haptic(.light)
                            } label: {
                                Label(saved.name, systemImage: "bookmark.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12)).cornerRadius(15)
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.deleteSavedFilter(id: saved.id) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 4)
                }
            }

            Divider()
        }
        .background(Material.thickMaterial)
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
    }

    // MARK: - Document Grid

    var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(store.filteredDocs) { doc in
                    if isSelectionMode {
                        DocumentCard(
                            doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
                            allTags: store.allTags, allCorrespondents: store.allCorrespondents,
                            allDocTypes: store.allDocTypes,
                            isSelected: selectedDocIDs.contains(doc.id)
                        )
                        .onTapGesture {
                            if selectedDocIDs.contains(doc.id) { selectedDocIDs.remove(doc.id) }
                            else { selectedDocIDs.insert(doc.id) }
                        }
                    } else {
                        NavigationLink(
                            destination: DocumentDetailView(doc: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }, searchQuery: searchText),
                            tag: doc.id, selection: $selectedDocId
                        ) {
                            DocumentCard(
                                doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
                                allTags: store.allTags, allCorrespondents: store.allCorrespondents,
                                allDocTypes: store.allDocTypes
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onLongPressGesture {
                            store.haptic(.medium)
                            quickLookDoc = doc
                        }
                        .contextMenu {
                            Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
                            Button { quickLookDoc = doc } label: { Label("Vorschau", systemImage: "eye") }
                            Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                        }
                        .onAppear {
                            if doc.id == store.filteredDocs.last?.id {
                                if !store.currentSearchText.isEmpty {
                                    Task { await store.loadNextSearchPage() }
                                } else {
                                    Task { await store.loadNextPage() }
                                }
                            }
                        }
                    }
                }
                if store.isLoadingMore { ProgressView().padding() }
            }
            .padding(10)
        }
        .refreshable { await store.loadFirstPage() }
    }

    // MARK: - Document List

    var documentList: some View {
        List {
            ForEach(store.filteredDocs) { doc in
                NavigationLink(
                    destination: DocumentDetailView(doc: doc, onSave: updateDocument, onDelete: { store.deleteDocument(id: $0) }, searchQuery: searchText),
                    tag: doc.id, selection: $selectedDocId
                ) {
                    DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents, serverBase: store.makeServerBase(), token: store.authToken())
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.haptic(.heavy)
                        store.deleteDocument(id: doc.id)
                    } label: { Label("Löschen", systemImage: "trash") }
                    Button { documentToEdit = doc } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button { quickTagDoc = doc; store.haptic(.light) } label: {
                        Label("Tag", systemImage: "tag.fill")
                    }.tint(.blue)
                }
                .contextMenu {
                    Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
                    Button { quickLookDoc = doc } label: { Label("Vorschau", systemImage: "eye") }
                    Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                }
                .onAppear {
                    if doc.id == store.filteredDocs.last?.id {
                        if !store.currentSearchText.isEmpty {
                            Task { await store.loadNextSearchPage() }
                        } else {
                            Task { await store.loadNextPage() }
                        }
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
        ToolbarItem(placement: .principal) {
            Text("\(store.filteredDocs.count) \(String(localized: "Dokumente", locale: locale))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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

    private func bulkShare() async {
        isBulkSharing = true
        var urls: [URL] = []
        for id in selectedDocIDs {
            guard let data = await store.loadPDFData(for: id) else { continue }
            let title = store.documents.first { $0.id == id }?.title ?? "\(id)"
            let safeName = title.replacingOccurrences(of: "/", with: "-")
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).pdf")
            try? data.write(to: tmp)
            urls.append(tmp)
        }
        bulkShareURLs = urls
        isBulkSharing = false
        if !urls.isEmpty { showBulkShare = true }
    }
}
