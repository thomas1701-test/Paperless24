import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers

struct MainDocView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.locale) private var locale
    @Environment(\.palette) private var palette

    @AppStorage("layoutStyle") private var layoutStyleRaw = LayoutStyle.grid.rawValue
    @AppStorage("sortOrder") private var sortOrderRaw = SortOrder.dateDesc.rawValue
    @AppStorage("gridItemSize") private var gridItemSize: Double = 130
    @AppStorage("batchScanEnabled") private var batchScanEnabled = true

    @State private var searchText = ""
    @State private var filterTag: Int? = nil
    @State private var filterCorr: Int? = nil
    @State private var filterType: Int? = nil
    /// Mehrfach- und Negativfilter aus `AdvancedFilterSheet`. Die Chips oben halten
    /// weiterhin je einen Wert; `AppStore.activeQuery` führt beides zusammen.
    @State private var advTags = Set<Int>()
    @State private var excludedTags = Set<Int>()
    @State private var advCorrs = Set<Int>()
    @State private var advTypes = Set<Int>()
    @State private var showAdvancedFilter = false
    @State private var showASNScanner = false
    @State private var showPermissions = false
    @State private var filterCustomField: Int? = nil
    @State private var filterCustomText = ""
    @State private var showCustomFieldSheet = false
    @State private var filterDate: DateFilter = .all
    @State private var showScanner = false
    @State private var showAirScan = false
    @State private var showBatchScan = false
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
    /// Push-Stack der Kompakt-Ansicht (iPhone). Ersetzt die frühere
    /// `NavigationLink(tag:selection:)`-Konstruktion, die in einer `NavigationStack`
    /// nicht mehr auslöst — Tippen auf eine Zeile blieb wirkungslos.
    @State private var navPath: [Document] = []
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showDatePickerSheet = false
    @State private var showTagPicker = false
    @State private var showCorrPicker = false
    @State private var showTypePicker = false
    @State private var showSaveFilterSheet = false
    @State private var saveFilterName = ""
    @State private var quickLookDoc: Document? = nil
    @State private var splitDoc: Document? = nil

    private var layoutStyle: LayoutStyle { LayoutStyle(rawValue: layoutStyleRaw) ?? .grid }
    private var sortOrder: SortOrder { SortOrder(rawValue: sortOrderRaw) ?? .dateDesc }

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Die Dreispalten-Ansicht ist eine iPad- und Mac-Ansicht. Die Größenklasse allein reicht
    /// als Bedingung nicht: iPhone Plus und Pro Max melden im Querformat ebenfalls `.regular`.
    /// Auf dem Telefon klappt der `NavigationSplitView` dann zu einer Spalte zusammen, und
    /// `splitDoc` zu setzen bewirkt gar nichts — der Tipp läuft ins Leere.
    private var usesSplitLayout: Bool {
        hSize == .regular && UIDevice.current.userInterfaceIdiom != .phone
    }

    var body: some View {
        if usesSplitLayout {
            // iPad / Mac: dreispaltig — Filter links, Dokumentbrowser Mitte, Detail rechts.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                filterSidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } content: {
                content
                    .navigationSplitViewColumnWidth(min: 420, ideal: 560)
            } detail: {
                detailColumn
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $navPath) {
                content
                    .navigationDestination(for: Document.self) { doc in
                        // Pager statt Einzelansicht: von hier aus lässt sich zum nächsten
                        // Dokument der Liste wischen.
                        DocumentPagerView(
                            documents: store.filteredDocs,
                            startId: doc.id,
                            onSave: updateDocument,
                            onDelete: { store.deleteDocument(id: $0) },
                            searchQuery: searchText
                        )
                    }
            }
        }
    }

    @ViewBuilder var detailColumn: some View {
        if let doc = splitDoc {
            NavigationStack {
                DocumentDetailView(
                    doc: doc,
                    onSave: updateDocument,
                    onDelete: { store.deleteDocument(id: $0); splitDoc = nil },
                    searchQuery: searchText
                )
                .id(doc.id)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50)).foregroundColor(.secondary)
                Text("Dokument auswählen").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.surface ?? Color(.systemGroupedBackground))
        }
    }

    var content: some View {
        ZStack(alignment: .top) {
            if let surface = palette.surface {
                surface.ignoresSafeArea()
            } else if !usesSplitLayout, palette.hasGradient {
                LinearGradient(
                    gradient: Gradient(colors: palette.gradient.map { $0.opacity(0.05) }),
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

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
                // Eine Zeile mit fester Höhe für Suche *und* Sync. Vorher waren das zwei
                // Bausteine, die im Stack auftauchten und verschwanden — jedes Mal rutschte
                // die ganze Liste um ihre Höhe nach unten und wieder zurück. Genau das ließ
                // Laden und Aktualisieren holprig wirken.
                activityStrip

                if store.pickerCallbackURL != nil {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.white)
                        Text("Dokument für Vermietoo auswählen")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            store.pickerCallbackURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                }

                if store.documents.isEmpty && store.isSyncing {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Dokumente werden geladen...").foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    if !usesSplitLayout { filterBar.zIndex(1) }
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
                    } else {
                        documentList
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
                            // Weitere Sammelaktionen hinter einem Menü, damit die Leiste nicht
                            // zur Symbolsammlung wird.
                            Menu {
                                Menu("Typ zuweisen") {
                                    ForEach(store.allDocTypes) { type in
                                        Button(type.safeName) {
                                            store.bulkAssignDocumentType(type.id, to: selectedDocIDs)
                                        }
                                    }
                                }
                                Menu("Tag entfernen") {
                                    ForEach(store.allTags) { tag in
                                        Button(tag.safeName) {
                                            store.bulkRemoveTags([tag.id], from: selectedDocIDs)
                                        }
                                    }
                                }
                                if !store.allStoragePaths.isEmpty {
                                    Menu("Speicherpfad") {
                                        Button("Keiner") { store.assignStoragePath(nil, to: selectedDocIDs) }
                                        ForEach(store.allStoragePaths) { path in
                                            Button(path.safeName) {
                                                store.assignStoragePath(path.id, to: selectedDocIDs)
                                            }
                                        }
                                    }
                                }
                                Button {
                                    showPermissions = true
                                } label: { Label("Rechte …", systemImage: "person.badge.key") }
                                if !store.inboxTagIDs.isEmpty {
                                    Button {
                                        store.markAsDone(selectedDocIDs)
                                        isSelectionMode = false; selectedDocIDs.removeAll()
                                    } label: { Label("Als erledigt markieren", systemImage: "tray.and.arrow.down") }
                                }
                            } label: { Image(systemName: "ellipsis.circle").frame(maxWidth: .infinity) }
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
                            if store.pickerCallbackURL != nil {
                                Button {
                                    let docs = store.documents.filter { selectedDocIDs.contains($0.id) }
                                    store.selectDocumentsForPicker(docs: docs)
                                    isSelectionMode = false; selectedDocIDs.removeAll()
                                } label: {
                                    Image(systemName: "doc.badge.plus").frame(maxWidth: .infinity)
                                        .foregroundStyle(.purple)
                                }
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
        .navigationTitle(usesSplitLayout
                         ? Text("\(store.listCount) \(String(localized: "Dokumente", locale: locale))")
                         : Text(""))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .searchSuggestions {
            if searchText.isEmpty {
                ForEach(store.recentSearches, id: \.self) { recent in
                    Label(recent, systemImage: "clock").searchCompletion(recent)
                }
            }
        }
        .onChange(of: searchText) { store.runSearch(query: $0) }
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
        .alert("Ansicht speichern", isPresented: $showSaveFilterSheet) {
            TextField("Name", text: $saveFilterName)
            Button("Speichern") {
                if !saveFilterName.isEmpty {
                    store.createServerView(name: saveFilterName, tag: filterTag, corr: filterCorr,
                                           type: filterType, dateFilter: filterDate,
                                           start: customStartDate, end: customEndDate, sort: sortOrder)
                    saveFilterName = ""
                }
            }
            Button("Abbrechen", role: .cancel) { saveFilterName = "" }
        } message: {
            Text("Name für diese Ansicht (wird auf dem Server gespeichert):")
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsSheet(documentIds: selectedDocIDs)
        }
        .sheet(isPresented: $showASNScanner) {
            ASNScannerSheet { doc in
                // In den Push-Stack legen, damit „Zurück" wieder in der Liste landet.
                navPath.append(doc)
            }
        }
        .sheet(isPresented: $showAdvancedFilter, onDismiss: applyFilters) {
            AdvancedFilterSheet(
                tags: $advTags, excludedTags: $excludedTags,
                correspondents: $advCorrs, documentTypes: $advTypes
            )
        }
        .sheet(isPresented: $showCustomFieldSheet, onDismiss: applyFilters) {
            CustomFieldFilterSheet(selectedField: $filterCustomField, text: $filterCustomText)
                .presentationDetents([.medium])
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
            NavigationStack {
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
        .sheet(isPresented: $showAirScan) {
            AirScanView()
        }
        .sheet(isPresented: $showBatchScan) {
            BatchScanView()
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
        // `onAppear` läuft auch bei jeder Rückkehr aus der Detailansicht. Ein voller Sync
        // pro Zurück-Tippen ist verschwendete Arbeit und sichtbares Zucken in der Liste.
        .onAppear { applyFilters(); store.syncIfStale() }
        .onChange(of: store.pendingSearch) { q in
            guard let q else { return }
            store.pendingSearch = nil
            searchText = q
            store.runSearch(query: q)
        }
        .onChange(of: store.widgetOpenDocId) { id in
            guard let id else { return }
            store.widgetOpenDocId = nil
            if let existing = store.documents.first(where: { $0.id == id }) {
                openDeepLink(existing)
            } else {
                Task { if let d = await store.fetchDocumentDetail(id: id) { openDeepLink(d) } }
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let entry = AppStore.parseSpotlightIdentifier(raw),
                  // Ein Eintrag aus einem anderen Konto darf hier nichts öffnen: die ID
                  // gehört zu einem fremden Server und träfe im aktiven Archiv ein
                  // völlig anderes Dokument.
                  entry.account == store.activeAccountId else { return }
            if let existing = store.documents.first(where: { $0.id == entry.docId }) {
                openDeepLink(existing)
            } else {
                Task { if let d = await store.fetchDocumentDetail(id: entry.docId) { openDeepLink(d) } }
            }
        }
    }

    /// Öffnet ein Dokument aus Widget/Spotlight — im iPad-Modus in der Detailspalte, sonst per Push.
    private func openDeepLink(_ doc: Document) {
        if usesSplitLayout {
            splitDoc = doc
        } else {
            navPath = [doc]
        }
    }

    // MARK: - Filter Sidebar (iPad / Mac)

    private var hasActiveFilter: Bool {
        filterTag != nil || filterCorr != nil || filterType != nil
            || filterDate != .all || filterCustomField != nil || advancedFilterCount > 0
    }

    /// Anzahl der Einschränkungen aus „Mehr Filter".
    private var advancedFilterCount: Int {
        advTags.count + excludedTags.count + advCorrs.count + advTypes.count
    }

    /// Setzt alle Filter zurück — Chips *und* „Mehr Filter". Ohne den zweiten Teil blieb nach
    /// „Zurücksetzen" eine unsichtbare Einschränkung stehen.
    private func resetFilters() {
        filterTag = nil; filterCorr = nil; filterType = nil; filterDate = .all
        filterCustomField = nil; filterCustomText = ""
        advTags = []; excludedTags = []; advCorrs = []; advTypes = []
        applyFilters(); store.haptic(.light)
    }

    @ViewBuilder
    private func sidebarPickerRow(_ title: LocalizedStringKey, systemImage: String, value: String?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let value {
                Text(value).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    var filterSidebar: some View {
        List {
            Section("Zeitraum") {
                ForEach(DateFilter.allCases) { f in
                    Button {
                        filterDate = f
                        if f == .custom { showDatePickerSheet = true } else { applyFilters() }
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(f.rawValue))
                            Spacer()
                            if filterDate == f {
                                Image(systemName: "checkmark").foregroundStyle(palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Filter") {
                Button { showTagPicker = true } label: {
                    sidebarPickerRow("Tags", systemImage: "tag",
                                     value: store.allTags.first { $0.id == filterTag }?.safeName)
                }
                .buttonStyle(.plain)

                Button { showCorrPicker = true } label: {
                    sidebarPickerRow("Sender", systemImage: "person",
                                     value: store.allCorrespondents.first { $0.id == filterCorr }?.safeName)
                }
                .buttonStyle(.plain)

                Button { showTypePicker = true } label: {
                    sidebarPickerRow("Typ", systemImage: "doc",
                                     value: store.allDocTypes.first { $0.id == filterType }?.safeName)
                }
                .buttonStyle(.plain)

                if !store.allCustomFields.isEmpty {
                    Button { showCustomFieldSheet = true } label: {
                        sidebarPickerRow("Feld", systemImage: "character.textbox",
                                         value: filterCustomField.flatMap { store.customField(id: $0)?.safeName })
                    }
                    .buttonStyle(.plain)
                    Button { showAdvancedFilter = true } label: {
                        sidebarPickerRow("Mehr Filter", systemImage: "line.3.horizontal.decrease.circle",
                                         value: advancedFilterCount > 0 ? "\(advancedFilterCount)" : nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !store.serverViews.isEmpty {
                Section("Gespeicherte Ansichten") {
                    ForEach(store.serverViews) { view in
                        Button {
                            let p = store.parse(view)
                            filterTag = p.tag
                            filterCorr = p.corr
                            filterType = p.type
                            filterDate = p.dateFilter
                            if let s = p.customStart { customStartDate = s }
                            if let e = p.customEnd { customEndDate = e }
                            sortOrderRaw = p.sort.rawValue
                            applyFilters()
                            store.haptic(.light)
                        } label: {
                            Label(view.safeName, systemImage: "bookmark.fill")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteServerView(id: view.id) } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if hasActiveFilter {
                Section {
                    Button { showSaveFilterSheet = true } label: {
                        Label("Speichern", systemImage: "bookmark")
                    }
                    Button(role: .destructive) {
                        resetFilters()
                    } label: {
                        Label("Zurücksetzen", systemImage: "xmark.circle.fill")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .themedSurface(palette)
        .navigationTitle("Filter")
    }

    /// Statuszeile mit gleichbleibender Höhe.
    ///
    /// Sie ist immer im Layout, nur ihr Inhalt wechselt. Ein- und ausgeblendete Zeilen
    /// verschieben sonst den gesamten Inhalt darunter.
    @ViewBuilder
    private var activityStrip: some View {
        let active = store.isSearching || (store.isSyncing && !store.documents.isEmpty)
        HStack(spacing: 6) {
            if active {
                ProgressView().controlSize(.small)
                Text(store.isSearching ? "Suche…" : "Aktualisieren…")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(height: 18)
        .frame(maxWidth: .infinity)
        .background(active ? palette.accent.opacity(0.07) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    // MARK: - Filter Bar

    private func chipBackground(active: Bool) -> Color {
        palette.chipBackground(active: active)
    }

    private func chipForeground(active: Bool) -> Color {
        palette.chipForeground(active: active)
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

                    if !store.allCustomFields.isEmpty {
                        Button { showCustomFieldSheet = true } label: {
                            Group {
                                if filterCustomField == nil {
                                    Label("Feld", systemImage: "character.textbox")
                                } else {
                                    Label(store.customField(id: filterCustomField!)?.safeName ?? "Feld",
                                          systemImage: "character.textbox")
                                }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(chipForeground(active: filterCustomField != nil))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(chipBackground(active: filterCustomField != nil))
                            .cornerRadius(8)
                        }
                    }

                    Button { showAdvancedFilter = true } label: {
                        Label(advancedFilterCount > 0 ? "Mehr (\(advancedFilterCount))" : "Mehr",
                              systemImage: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(chipForeground(active: advancedFilterCount > 0))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(chipBackground(active: advancedFilterCount > 0))
                            .cornerRadius(8)
                    }

                    if hasActiveFilter {
                        Button {
                            showSaveFilterSheet = true
                        } label: {
                            Label("Speichern", systemImage: "bookmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(palette.accent)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(palette.accent.opacity(0.1)).cornerRadius(8)
                        }
                        Button {
                            resetFilters()
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

            if !store.serverViews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.serverViews) { view in
                            Button {
                                let p = store.parse(view)
                                filterTag = p.tag
                                filterCorr = p.corr
                                filterType = p.type
                                filterDate = p.dateFilter
                                if let s = p.customStart { customStartDate = s }
                                if let e = p.customEnd { customEndDate = e }
                                sortOrderRaw = p.sort.rawValue
                                applyFilters()
                                store.haptic(.light)
                            } label: {
                                Label(view.safeName, systemImage: "bookmark.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(palette.accent.opacity(0.12)).cornerRadius(15)
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.deleteServerView(id: view.id) } label: {
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridItemSize), spacing: 10)], spacing: 10) {
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
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if store.pickerCallbackURL != nil {
                                    Button {
                                        store.selectDocumentForPicker(doc: doc)
                                    } label: { docCard(doc) }
                                    .buttonStyle(PlainButtonStyle())
                                } else if usesSplitLayout {
                                    // Kein Button: auf iPad startet .onDrag schon beim kurzen Druck
                                    // und verschluckt den Button-Tap. TapGesture koexistiert mit Drag.
                                    docCard(doc)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(palette.accent, lineWidth: splitDoc?.id == doc.id ? 3 : 0)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            splitDoc = doc; store.haptic(.light)
                                        }
                                        .onDrag { dragProvider(for: doc) }
                                        .contextMenu { docContextMenu(doc) }
                                } else {
                                    // Wie im iPad-Zweig: kein Button und kein .onDrag. Beide
                                    // starten ihre Erkennung schon beim kurzen Druck und
                                    // verschlucken den Tap. Zusätzlich konkurrierten hier drei
                                    // Long-Press-Erkenner (.onDrag, .onLongPressGesture,
                                    // .contextMenu) — dadurch ging das Kontextmenü an der
                                    // falschen Kachel auf. Die Vorschau steckt im Kontextmenü.
                                    // Drag entfällt auf dem iPhone bewusst: es gibt dort kein
                                    // Ablegeziel, weder Detailspalte noch zweite App.
                                    docCard(doc)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            store.haptic(.light)
                                            navPath.append(doc)
                                        }
                                        .contextMenu { docContextMenu(doc) }
                                }
                            }
                            .onAppear {
                                if doc.id == store.filteredDocs.last?.id {
                                    if store.isQueryActive {
                                        Task { await store.loadNextSearchPage() }
                                    } else {
                                        Task { await store.loadNextPage() }
                                    }
                                }
                            }

                            if store.pickerCallbackURL != nil {
                                Text("Auswählen")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple)
                                    .clipShape(Capsule())
                                    .padding(6)
                            }
                        }
                    }
                }
                if store.isLoadingMore { ProgressView().padding() }
            }
            .padding(10)
        }
        .refreshable { await store.refreshList() }
    }

    // MARK: - Document List

    var documentList: some View {
        List {
            ForEach(store.filteredDocs) { doc in
                ZStack(alignment: .trailing) {
                    Group {
                        if store.pickerCallbackURL != nil {
                            Button {
                                store.selectDocumentForPicker(doc: doc)
                            } label: {
                                DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents, serverBase: store.makeServerBase(), token: store.authToken(), allDocTypes: store.allDocTypes, searchQuery: searchText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if usesSplitLayout {
                            // Siehe Grid: Button + .onDrag frisst den Tap auf iPad.
                            DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents, serverBase: store.makeServerBase(), token: store.authToken(), allDocTypes: store.allDocTypes, searchQuery: searchText)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                splitDoc = doc; store.haptic(.light)
                            }
                            .onDrag { dragProvider(for: doc) }
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
                            .contextMenu { docContextMenu(doc) }
                        } else {
                            // Kein .onDrag: siehe Raster — es beansprucht den Druck für sich,
                            // bevor die Zeile ihn als Tap auswerten kann.
                            NavigationLink(value: doc) {
                                DocumentRow(doc: doc, allTags: store.allTags, allCorrespondents: store.allCorrespondents, serverBase: store.makeServerBase(), token: store.authToken(), allDocTypes: store.allDocTypes, searchQuery: searchText)
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
                            .contextMenu { docContextMenu(doc) }
                        }
                    }
                    .onAppear {
                        if doc.id == store.filteredDocs.last?.id {
                            if store.isQueryActive {
                                Task { await store.loadNextSearchPage() }
                            } else {
                                Task { await store.loadNextPage() }
                            }
                        }
                    }

                    if store.pickerCallbackURL != nil {
                        Text("Auswählen")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple)
                            .clipShape(Capsule())
                            .padding(.trailing, 8)
                    }
                }
                .listRowBackground(
                    usesSplitLayout && splitDoc?.id == doc.id
                        ? palette.accent.opacity(0.12)
                        : Color?.none
                )
            }
        }
        .listStyle(.plain)
        .themedSurface(palette)
        .refreshable { await store.refreshList() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if !usesSplitLayout {
            ToolbarItem(placement: .principal) {
                Text("\(store.listCount) \(String(localized: "Dokumente", locale: locale))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button { showScanner = true } label: { Label("Scan", systemImage: "camera") }
                Button { showPhotoPicker = true } label: { Label("Foto", systemImage: "photo") }
                Button { showFilePicker = true } label: { Label("Datei", systemImage: "folder") }
                Button { showAirScan = true } label: { Label("Netzwerkscanner", systemImage: "scanner") }
                if batchScanEnabled {
                    Button { showBatchScan = true } label: { Label("Stapel scannen", systemImage: "doc.on.doc") }
                }
                Divider()
                // Kein Import, sondern der Weg zurück: vom Papier zum Dokument in der App.
                Button { showASNScanner = true } label: {
                    Label("ASN scannen", systemImage: "barcode.viewfinder")
                }
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

    @ViewBuilder private func docCard(_ doc: Document) -> some View {
        DocumentCard(
            doc: doc, serverBase: store.makeServerBase(), token: store.authToken(),
            allTags: store.allTags, allCorrespondents: store.allCorrespondents,
            allDocTypes: store.allDocTypes
        )
    }

    @ViewBuilder private func docContextMenu(_ doc: Document) -> some View {
        Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button { quickLookDoc = doc } label: { Label("Vorschau", systemImage: "eye") }
        Button(role: .destructive) { store.deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
    }

    private func dragProvider(for doc: Document) -> NSItemProvider {
        if store.fileExists(docId: doc.id),
           let provider = NSItemProvider(contentsOf: store.localFileURL(for: doc.id)) {
            provider.suggestedName = doc.title
            return provider
        }
        return NSItemProvider(object: doc.title as NSString)
    }

    private func applyFilters() {
        store.currentFilterTag = filterTag
        store.currentFilterCorr = filterCorr
        store.currentFilterType = filterType
        store.currentFilterTags = advTags
        store.currentFilterCorrs = advCorrs
        store.currentFilterTypes = advTypes
        store.currentFilterExcludedTags = excludedTags
        store.currentFilterCustomField = filterCustomField
        store.currentFilterCustomText = filterCustomText
        store.currentDateFilter = filterDate
        store.customStartDate = customStartDate
        store.customEndDate = customEndDate
        store.currentSortOrder = sortOrder
        // Entscheidet selbst, ob der Server gefragt werden muss oder die geladene Liste
        // lokal eingeschränkt wird — und lädt bei unveränderter Anfrage nicht erneut.
        store.applyFilters()
    }

    private func updateDocument(id: Int, title: String, date: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int], customFields: [CustomFieldEdit]) {
        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags, customFields: customFields)
    }

    private func bulkDelete() {
        for id in selectedDocIDs { store.deleteDocument(id: id) }
        isSelectionMode = false
        selectedDocIDs.removeAll()
    }

    private func bulkShare() async {
        isBulkSharing = true
        // Ablagen der vorherigen Freigabe wegräumen, bevor die neue entsteht.
        ShareStaging.cleanUp()
        var urls: [URL] = []
        for id in selectedDocIDs {
            guard let data = await store.loadPDFData(for: id) else { continue }
            let title = store.documents.first { $0.id == id }?.title ?? "\(id)"
            if let url = ShareStaging.stage(data, filename: "\(title).pdf") { urls.append(url) }
        }
        bulkShareURLs = urls
        isBulkSharing = false
        if !urls.isEmpty { showBulkShare = true }
    }
}
