import SwiftUI
import CoreSpotlight
import PDFKit
import Vision
import WidgetKit

@MainActor
class AppStore: ObservableObject {

    // MARK: - Published State

    @Published var documents: [Document] = []
    @Published var filteredDocs: [Document] = []
    @Published var allTags: [Tag] = []
    @Published var allCorrespondents: [Correspondent] = []
    @Published var allDocTypes: [DocumentType] = []
    @Published var pendingUploads: [PendingUpload] = []
    @Published var pendingEdits: [PendingEdit] = []

    @Published var incomingUploadContainer: UploadContainer? = nil
    @Published var importErrorMessage: String? = nil
    @Published var importStatus: String? = nil

    @Published var isOffline = false
    @Published var isSyncing = false
    @Published var isSearching = false
    @Published var lastSyncError: String? = nil

    @Published var storageSize = "..."
    @Published var cachedCount = 0
    @Published var uploadSuccessMessage: String? = nil
    @Published var isDownloadingAll = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatusText = ""

    @Published var hasNextPage = false
    @Published var isLoadingMore = false
    @Published var needsReLogin = false
    @Published var savedFilters: [SavedFilter] = []

    var inboxCount: Int { documents.filter { $0.correspondent == nil }.count }

    // MARK: - Settings

    @AppStorage("serverUrl") var serverUrl = ""
    @AppStorage("username") var username = ""
    @AppStorage("isDemoMode") var isDemoMode = false

    // MARK: - Filter & Sort State (set by MainDocView)

    var currentSortOrder: SortOrder = .dateDesc
    var currentDateFilter: DateFilter = .all
    var currentFilterTag: Int? = nil
    var currentFilterCorr: Int? = nil
    var currentFilterType: Int? = nil
    var customStartDate: Date = Date()
    var customEndDate: Date = Date()
    var currentSearchText: String = ""

    // MARK: - Private

    private var api: PaperlessAPI? {
        guard let token = KeychainService.loadToken(for: serverUrl), !serverUrl.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: serverUrl, token: token)
    }

    private var currentPage = 1
    private var searchTask: Task<Void, Never>? = nil
    private var autoSyncTask: Task<Void, Never>? = nil
    private var downloadTask: Task<Void, Never>? = nil

    // MARK: - Init

    init() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            let savedUrl = UserDefaults.standard.string(forKey: "serverUrl") ?? ""
            if !savedUrl.isEmpty { KeychainService.deleteToken(for: savedUrl) }
        }
        if !serverUrl.isEmpty, KeychainService.loadToken(for: serverUrl) != nil {
            loadFromDisk()
            calculateStorage()
            startAutoSync()
        }
    }

    // MARK: - API Access

    func makeServerBase() -> String {
        api?.serverBase ?? ""
    }

    func thumbnailURL(for docId: Int) -> String {
        api?.thumbnailURL(for: docId) ?? ""
    }

    func authToken() -> String {
        KeychainService.loadToken(for: serverUrl) ?? ""
    }

    // MARK: - Sync

    func sync(silent: Bool = false) {
        guard !isDemoMode, !serverUrl.isEmpty else { return }
        if !silent { isSyncing = true }
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.loadFirstPage() }
                group.addTask { await self.syncMetadata() }
                if !self.pendingUploads.isEmpty { group.addTask { await self.processUploadQueue() } }
                await self.processEditQueue()
            }
        }
    }

    private func syncMetadata() async {
        guard let api = api else { return }
        async let tags = try? api.fetchTags()
        async let corrs = try? api.fetchCorrespondents()
        async let types = try? api.fetchDocumentTypes()
        async let stats = try? api.fetchStatistics()

        if let t = await tags { allTags = t }
        if let c = await corrs { allCorrespondents = c }
        if let tp = await types { allDocTypes = tp }
        saveToDisk()

        let resolvedStats = await stats
        updateWidget(stats: resolvedStats)
    }

    // MARK: - Pagination

    func loadFirstPage() async {
        guard let api = api else {
            isSyncing = false
            needsReLogin = true
            return
        }
        currentPage = 1
        isSyncing = true
        for attempt in 1...2 {
            do {
                let page = try await api.fetchDocuments(page: 1, ordering: orderingParam())
                documents = page.documents
                hasNextPage = page.hasNext
                currentPage = 1
                isOffline = false
                lastSyncError = nil
                reApplyPendingEdits()
                saveToDisk()
                updateFilteredDocs()
                indexDocumentsForSpotlight()
                isSyncing = false
                return
            } catch APIError.unauthorized {
                KeychainService.deleteToken(for: serverUrl)
                lastSyncError = "Sitzung abgelaufen, bitte neu einloggen"
                needsReLogin = true
                isSyncing = false
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    isOffline = true
                    lastSyncError = error.localizedDescription
                }
            }
        }
        isSyncing = false
    }

    func loadNextPage() async {
        guard !isLoadingMore, hasNextPage, let api = api else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let page = try await api.fetchDocuments(page: nextPage, ordering: orderingParam())
            documents.append(contentsOf: page.documents)
            hasNextPage = page.hasNext
            currentPage = nextPage
            updateFilteredDocs()
        } catch {
            lastSyncError = error.localizedDescription
        }
        isLoadingMore = false
    }

    private func orderingParam() -> String {
        switch currentSortOrder {
        case .dateDesc:  return "-created"
        case .dateAsc:   return "created"
        case .titleAZ:   return "title"
        case .senderAZ:  return "correspondent__name"
        case .addedDesc: return "-added"
        case .addedAsc:  return "added"
        }
    }

    // MARK: - Search

    private(set) var currentSearchPage = 1
    private(set) var searchHasNextPage = false
    @Published var recentSearches: [String] = []

    func runSearch(query: String) {
        currentSearchText = query
        searchTask?.cancel()
        if query.isEmpty {
            Task { await loadFirstPage() }
            return
        }
        searchTask = Task {
            isSearching = true
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            if isOffline {
                let low = query.lowercased()
                filteredDocs = documents.filter {
                    $0.title.localizedCaseInsensitiveContains(low) ||
                    ($0.content?.localizedCaseInsensitiveContains(low) ?? false)
                }
                isSearching = false
                return
            }

            guard let api = api else { isSearching = false; return }
            do {
                let page = try await api.searchDocuments(query: query, page: 1)
                filteredDocs = page.documents
                searchHasNextPage = page.hasNext
                currentSearchPage = 1
                addRecentSearch(query)
            } catch {
                let isCancelled = (error is CancellationError) ||
                    (error as? URLError)?.code == .cancelled
                if !isCancelled { lastSyncError = error.localizedDescription }
            }
            isSearching = false
        }
    }

    func loadNextSearchPage() async {
        guard !isSearching, searchHasNextPage, let api = api, !currentSearchText.isEmpty else { return }
        isSearching = true
        let nextPage = currentSearchPage + 1
        do {
            let page = try await api.searchDocuments(query: currentSearchText, page: nextPage)
            filteredDocs.append(contentsOf: page.documents)
            searchHasNextPage = page.hasNext
            currentSearchPage = nextPage
        } catch {
            let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if !isCancelled { lastSyncError = error.localizedDescription }
        }
        isSearching = false
    }

    func addRecentSearch(_ query: String) {
        var searches = recentSearches
        searches.removeAll { $0.lowercased() == query.lowercased() }
        searches.insert(query, at: 0)
        recentSearches = Array(searches.prefix(8))
    }

    func bulkAssignTags(_ tagIds: [Int], to docIds: Set<Int>) {
        for id in docIds {
            guard let doc = documents.first(where: { $0.id == id }) else { continue }
            let merged = Array(Set(doc.tags).union(Set(tagIds)))
            addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                           corr: doc.correspondent, type: doc.documentType, asn: doc.archiveSerialNumber, tags: merged)
        }
    }

    func bulkAssignCorrespondent(_ corrId: Int, to docIds: Set<Int>) {
        for id in docIds {
            guard let doc = documents.first(where: { $0.id == id }) else { continue }
            addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                           corr: corrId, type: doc.documentType, asn: doc.archiveSerialNumber, tags: doc.tags)
        }
    }

    // MARK: - Filter & Sort

    func updateFilteredDocs() {
        let calendar = Calendar.current
        let now = Date()

        let filtered = documents.filter { doc in
            let matchesTag = currentFilterTag == nil || doc.tags.contains(currentFilterTag!)
            let matchesCorr = currentFilterCorr == nil || doc.correspondent == currentFilterCorr
            let matchesType = currentFilterType == nil || doc.documentType == currentFilterType

            var matchesDate = true
            if currentDateFilter != .all, let date = doc.dateObject {
                switch currentDateFilter {
                case .lastMonth:
                    if let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) {
                        matchesDate = date >= oneMonthAgo
                    }
                case .thisYear:
                    if let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now)) {
                        matchesDate = date >= startOfYear
                    }
                case .custom:
                    let start = calendar.startOfDay(for: customStartDate)
                    let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
                    matchesDate = date >= start && date <= end
                case .all:
                    break
                }
            }
            return matchesTag && matchesCorr && matchesType && matchesDate
        }

        switch currentSortOrder {
        case .dateDesc:  filteredDocs = filtered.sorted { $0.created > $1.created }
        case .dateAsc:   filteredDocs = filtered.sorted { $0.created < $1.created }
        case .titleAZ:   filteredDocs = filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .senderAZ:
            filteredDocs = filtered.sorted { doc1, doc2 in
                let n1 = allCorrespondents.first(where: { $0.id == doc1.correspondent })?.safeName ?? ""
                let n2 = allCorrespondents.first(where: { $0.id == doc2.correspondent })?.safeName ?? ""
                return n1.localizedCompare(n2) == .orderedAscending
            }
        case .addedDesc: filteredDocs = filtered.sorted { ($0.added ?? "") > ($1.added ?? "") }
        case .addedAsc:  filteredDocs = filtered.sorted { ($0.added ?? "") < ($1.added ?? "") }
        }
    }

    // MARK: - Pending Edit Queue

    func addPendingEdit(docId: Int, title: String, created: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int]) {
        let iso = ISO8601DateFormatter().string(from: created)
        if let idx = documents.firstIndex(where: { $0.id == docId }) {
            documents[idx].title = title
            documents[idx].created = iso
            documents[idx].correspondent = corr
            documents[idx].documentType = type
            documents[idx].archiveSerialNumber = asn
            documents[idx].tags = tags
        }
        let edit = PendingEdit(docId: docId, title: title, created: iso, correspondent: corr, documentType: type, archiveSerialNumber: asn, tags: tags)
        pendingEdits.append(edit)
        saveToDisk()
        updateFilteredDocs()
        Task { await processEditQueue() }
    }

    private func processEditQueue() async {
        guard !isDemoMode else { return }
        var remaining = pendingEdits
        var processed: [UUID] = []
        for edit in remaining {
            guard let api = api else { break }
            do {
                try await api.patchDocument(id: edit.docId, title: edit.title, created: edit.created, correspondent: edit.correspondent, documentType: edit.documentType, archiveSerialNumber: edit.archiveSerialNumber, tags: edit.tags)
                processed.append(edit.id)
                showSuccessToast("Änderung gespeichert")
            } catch APIError.unauthorized {
                isOffline = true; break
            } catch {
                isOffline = true; break
            }
        }
        pendingEdits.removeAll { processed.contains($0.id) }
        saveToDisk()
    }

    func removePendingEdit(at offsets: IndexSet) { pendingEdits.remove(atOffsets: offsets); saveToDisk() }

    func reApplyPendingEdits() {
        for edit in pendingEdits {
            if let idx = documents.firstIndex(where: { $0.id == edit.docId }) {
                documents[idx].title = edit.title
                documents[idx].created = edit.created
                documents[idx].correspondent = edit.correspondent
                documents[idx].documentType = edit.documentType
                documents[idx].archiveSerialNumber = edit.archiveSerialNumber
                documents[idx].tags = edit.tags
            }
        }
    }

    // MARK: - Upload Queue

    func addToQueue(data: Data, filename: String, title: String, created: Date, corr: Int?, type: Int?, tags: [Int]) {
        let item = PendingUpload(data: data, filename: filename, title: title, created: created, correspondent: corr, documentType: type, tags: tags)
        pendingUploads.append(item)
        saveToDisk()
        showSuccessToast("In Warteschlange")
        Task { await processUploadQueue() }
    }

    private func processUploadQueue() async {
        guard !isDemoMode else { return }
        var processed: [UUID] = []
        for item in pendingUploads {
            guard let api = api else { break }
            do {
                try await api.uploadDocument(item)
                processed.append(item.id)
                showSuccessToast("Fertig: \(item.title)")
            } catch { isOffline = true; break }
        }
        pendingUploads.removeAll { processed.contains($0.id) }
        saveToDisk()
        if !processed.isEmpty { await loadFirstPage() }
    }

    func removePendingUpload(at offsets: IndexSet) { pendingUploads.remove(atOffsets: offsets); saveToDisk() }

    // MARK: - Delete Document

    func deleteDocument(id: Int) {
        Task {
            guard let api = api else { return }
            try? await api.deleteDocument(id: id)
            documents.removeAll { $0.id == id }
            updateFilteredDocs()
            PersistenceService.deleteDocFile(docId: id)
        }
    }

    // MARK: - Notes

    func addNote(docId: Int, text: String) async -> Bool {
        guard let api = api else { return false }
        do { try await api.addNote(docId: docId, text: text); return true }
        catch { return false }
    }

    func deleteNote(docId: Int, noteId: Int) async -> Bool {
        guard let api = api else { return false }
        do { try await api.deleteNote(docId: docId, noteId: noteId); return true }
        catch { return false }
    }

    func fetchDocumentDetail(id: Int) async -> Document? {
        guard let api = api else { return nil }
        return try? await api.fetchDocumentDetail(id: id)
    }

    // MARK: - Metadata CRUD

    func createTag(name: String) async -> Int? {
        guard !isDemoMode, let api = api else { return nil }
        let id = try? await api.createTag(name: name)
        await syncMetadata()
        return id
    }

    func createCorrespondent(name: String) async -> Int? {
        guard !isDemoMode, let api = api else { return nil }
        let id = try? await api.createCorrespondent(name: name)
        await syncMetadata()
        return id
    }

    func createDocumentType(name: String) async -> Int? {
        guard !isDemoMode, let api = api else { return nil }
        let id = try? await api.createDocumentType(name: name)
        await syncMetadata()
        return id
    }

    func deleteTag(id: Int) {
        Task { guard let api = api else { return }; try? await api.deleteTag(id: id); await syncMetadata() }
    }

    func deleteCorrespondent(id: Int) {
        Task { guard let api = api else { return }; try? await api.deleteCorrespondent(id: id); await syncMetadata() }
    }

    func deleteDocumentType(id: Int) {
        Task { guard let api = api else { return }; try? await api.deleteDocumentType(id: id); await syncMetadata() }
    }

    func fetchStatistics() async -> PaperlessStatistics? {
        guard let api = api else { return nil }
        return try? await api.fetchStatistics()
    }

    // MARK: - Offline / Download

    func fileExists(docId: Int) -> Bool { PersistenceService.fileExists(docId: docId) }
    func localFileURL(for docId: Int) -> URL { PersistenceService.docFileURL(for: docId) }

    func loadPDFData(for docId: Int) async -> Data? {
        if fileExists(docId: docId) { return try? Data(contentsOf: localFileURL(for: docId)) }
        guard let api = api else { return nil }
        if let data = try? await api.downloadDocument(id: docId) {
            try? data.write(to: localFileURL(for: docId))
            return data
        }
        return nil
    }

    func deleteLocalFile(docId: Int) {
        PersistenceService.deleteDocFile(docId: docId)
        calculateStorage()
    }

    func startFullDownload() {
        guard let api = api else { return }
        isDownloadingAll = true
        downloadProgress = 0.0
        downloadStatusText = "Lade Dokumentliste..."
        downloadTask = Task {
            let allDocs: [Document]
            do {
                allDocs = try await api.fetchAllDocuments()
            } catch {
                isDownloadingAll = false
                downloadStatusText = "Fehler: \(error.localizedDescription)"
                return
            }
            for (index, doc) in allDocs.enumerated() {
                guard isDownloadingAll, !Task.isCancelled else { break }
                downloadProgress = Double(index) / Double(allDocs.count)
                downloadStatusText = "Lade \(index + 1) von \(allDocs.count)..."
                if !fileExists(docId: doc.id) {
                    if let data = try? await api.downloadDocument(id: doc.id) {
                        try? data.write(to: localFileURL(for: doc.id))
                    }
                }
            }
            isDownloadingAll = false
            downloadStatusText = Task.isCancelled ? "Abgebrochen" : "Fertig"
            calculateStorage()
        }
    }

    func stopDownload() {
        downloadTask?.cancel()
        isDownloadingAll = false
        downloadStatusText = "Abgebrochen"
    }

    func calculateStorage() {
        Task.detached(priority: .background) {
            let result = PersistenceService.calculateStorage()
            await MainActor.run {
                self.storageSize = result.sizeString
                self.cachedCount = result.cachedCount
            }
        }
    }

    // MARK: - PDF

    func rotatePDF(data: Data) -> Data? {
        guard let pdf = PDFDocument(data: data) else { return nil }
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i) { page.rotation = (page.rotation + 90) % 360 }
        }
        return pdf.dataRepresentation()
    }

    // MARK: - Spotlight

    func indexDocumentsForSpotlight() {
        Task.detached(priority: .background) {
            var items: [CSSearchableItem] = []
            let docs = await self.documents.prefix(1000)
            let tags = await self.allTags
            let corrs = await self.allCorrespondents
            let types = await self.allDocTypes

            for doc in docs {
                let attrs = CSSearchableItemAttributeSet(contentType: .pdf)
                attrs.title = doc.title
                attrs.contentDescription = "Erstellt: \(doc.created)"
                if let content = doc.content { attrs.textContent = String(content.prefix(15000)) }

                var keywords: [String] = [doc.title]
                if let cid = doc.correspondent, let corr = corrs.first(where: { $0.id == cid }) {
                    attrs.authorNames = [corr.safeName]; keywords.append(corr.safeName)
                }
                doc.tags.forEach { tid in if let tag = tags.first(where: { $0.id == tid }) { keywords.append(tag.safeName) } }
                if let tid = doc.documentType, let type = types.first(where: { $0.id == tid }) { keywords.append(type.safeName) }
                attrs.keywords = keywords

                let thumbURL = ImageCache.shared.getFilePath(for: doc.id)
                if FileManager.default.fileExists(atPath: thumbURL.path) { attrs.thumbnailURL = thumbURL }

                let item = CSSearchableItem(uniqueIdentifier: "\(doc.id)", domainIdentifier: "com.paperless24.docs", attributeSet: attrs)
                item.expirationDate = .distantFuture
                items.append(item)
            }
            CSSearchableIndex.default().indexSearchableItems(items) { _ in }
        }
    }

    func clearSpotlightIndex() { CSSearchableIndex.default().deleteAllSearchableItems { _ in } }

    // MARK: - Persistence

    func saveToDisk() {
        PersistenceService.save(documents, to: "documents.json")
        PersistenceService.save(allTags, to: "tags.json")
        PersistenceService.save(allCorrespondents, to: "corrs.json")
        PersistenceService.save(allDocTypes, to: "types.json")
        PersistenceService.save(pendingUploads, to: "pending.json")
        PersistenceService.save(pendingEdits, to: "edits.json")
        PersistenceService.save(savedFilters, to: "savedfilters.json")
    }

    func loadFromDisk() {
        documents = PersistenceService.load([Document].self, from: "documents.json") ?? []
        allTags = PersistenceService.load([Tag].self, from: "tags.json") ?? []
        allCorrespondents = PersistenceService.load([Correspondent].self, from: "corrs.json") ?? []
        allDocTypes = PersistenceService.load([DocumentType].self, from: "types.json") ?? []
        pendingUploads = PersistenceService.load([PendingUpload].self, from: "pending.json") ?? []
        pendingEdits = PersistenceService.load([PendingEdit].self, from: "edits.json") ?? []
        savedFilters = PersistenceService.load([SavedFilter].self, from: "savedfilters.json") ?? []
        updateFilteredDocs()
    }

    func saveCurrentFilter(name: String, tag: Int?, correspondent: Int?, type: Int?, dateFilter: DateFilter) {
        let f = SavedFilter(name: name, tag: tag, correspondent: correspondent, type: type, dateFilter: dateFilter)
        savedFilters.append(f)
        saveToDisk()
    }

    func deleteSavedFilter(id: UUID) {
        savedFilters.removeAll { $0.id == id }
        saveToDisk()
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: - Auto Sync

    func startAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !pendingUploads.isEmpty || !pendingEdits.isEmpty { sync(silent: true) }
            }
        }
    }

    // MARK: - Clear

    func clearLocalData() {
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []
        pendingUploads = []; pendingEdits = []; cachedCount = 0; storageSize = "0 MB"; lastSyncError = nil
        PersistenceService.clearAll()
        ImageCache.shared.clearCache()
        clearSpotlightIndex()
        autoSyncTask?.cancel()
    }

    // MARK: - Import

    func handleImportData(data: Data, filename: String) {
        importStatus = "Verarbeite..."
        incomingUploadContainer = UploadContainer(data: data, filename: filename)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            importStatus = nil
        }
    }

    func handleIncomingFile(url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            handleImportData(data: data, filename: url.lastPathComponent)
        } catch {
            importErrorMessage = "Fehler: \(error.localizedDescription)"
        }
    }

    // MARK: - Demo

    func setupDemoData() {
        isDemoMode = true
        serverUrl = "demo.local"
        username = "demo"
        allTags = [Tag(id: 1, name: "Rechnung", color: "#ff0000")]
        allCorrespondents = [Correspondent(id: 1, name: "Amazon")]
        allDocTypes = [DocumentType(id: 1, name: "Rechnung")]
        documents = [Document(id: 1, title: "Demo", content: "Text", created: "2026-01-26", added: nil, correspondent: 1, documentType: 1, archiveSerialNumber: 100, tags: [1])]
        updateFilteredDocs()
        saveToDisk()
    }

    // MARK: - Widget

    func updateWidget(stats: PaperlessStatistics? = nil) {
        let enabled = UserDefaults(suiteName: "group.com.Thomas.paperless")?.bool(forKey: "widget_enabled") ?? true
        guard enabled else { return }

        let widgetDocs = documents.prefix(5).map { doc in
            WidgetDocument(
                id: doc.id,
                title: doc.title,
                created: doc.created,
                correspondent: allCorrespondents.first { $0.id == doc.correspondent }?.safeName
            )
        }

        WidgetDataService.write(
            docs: Array(widgetDocs),
            inboxCount: stats?.documentsInbox ?? 0,
            totalCount: stats?.documentsTotal ?? documents.count,
            lastSync: Date(),
            enabled: enabled
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Toast

    func showSuccessToast(_ msg: String) {
        uploadSuccessMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if uploadSuccessMessage == msg { uploadSuccessMessage = nil }
        }
    }
}
