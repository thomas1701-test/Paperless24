import SwiftUI
import CoreSpotlight
import PDFKit
import Vision
import WidgetKit

@MainActor
class AppStore: ObservableObject {

    /// Schwache Referenz auf die aktive Instanz — von App Intents (Siri/Kurzbefehle) genutzt.
    static weak var shared: AppStore?

    // MARK: - Published State

    @Published var documents: [Document] = []
    @Published var filteredDocs: [Document] = []
    @Published var allTags: [Tag] = []
    @Published var allCorrespondents: [Correspondent] = []
    @Published var allDocTypes: [DocumentType] = []
    @Published var allCustomFields: [CustomField] = []
    @Published var trashedDocs: [TrashDocument] = []
    @Published var serverViews: [SavedView] = []
    @Published var deadlines: [Deadline] = []
    @Published var isScanningDeadlines = false
    @Published var deadlineScanStatus = ""
    private var scannedDeadlineDocIds: Set<Int> = []
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
    /// Aktiv, solange eine semantische KI-Suche die Ergebnisliste bestimmt.
    @Published var semanticActive = false
    @Published var needsReLogin = false
    @Published var savedFilters: [SavedFilter] = []
    @Published var widgetOpenDocId: Int? = nil
    @Published var pickerCallbackURL: String? = nil

    // App-Intent-Aktionen (von Siri/Kurzbefehlen ausgelöst)
    @Published var requestScan = false
    @Published var requestInbox = false
    @Published var pendingSearch: String? = nil
    @Published var requestAskArchive = false

    var inboxCount: Int { documents.filter { $0.correspondent == nil }.count }

    // MARK: - Settings

    @AppStorage("isDemoMode") var isDemoMode = false

    @Published var accounts: [Account] = []
    @Published var activeAccountId: UUID? = nil

    var activeAccount: Account? {
        accounts.first { $0.id == activeAccountId }
    }

    var serverUrl: String { activeAccount?.serverUrl ?? "" }
    var username: String { activeAccount?.username ?? "" }

    // MARK: - Filter & Sort State (set by MainDocView)

    var currentSortOrder: SortOrder = .dateDesc
    var currentDateFilter: DateFilter = .all
    var currentFilterTag: Int? = nil
    var currentFilterCorr: Int? = nil
    var currentFilterType: Int? = nil
    var currentFilterCustomField: Int? = nil
    var currentFilterCustomText: String = ""
    var customStartDate: Date = Date()
    var customEndDate: Date = Date()
    var currentSearchText: String = ""

    // MARK: - Private

    private var api: PaperlessAPI? {
        guard let account = activeAccount,
              let token = KeychainService.loadToken(for: account.serverUrl, username: account.username),
              !account.serverUrl.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: account.serverUrl, token: token)
    }

    private var currentPage = 1
    private var searchTask: Task<Void, Never>? = nil
    private var autoSyncTask: Task<Void, Never>? = nil
    private var downloadTask: Task<Void, Never>? = nil

    // MARK: - Init

    init() {
        Self.shared = self
        var loadedAccounts = AccountService.load()
        var loadedActiveId = AccountService.activeId()

        // Migration: Single-Account → Multi-Account (runs exactly once)
        if loadedAccounts.isEmpty && !UserDefaults.standard.bool(forKey: "migrated_to_v2") {
            let legacyUrl = UserDefaults.standard.string(forKey: "serverUrl") ?? ""
            let legacyUser = UserDefaults.standard.string(forKey: "username") ?? ""
            if !legacyUrl.isEmpty, !legacyUser.isEmpty,
               let token = KeychainService.loadLegacyToken(for: legacyUrl) {
                let account = Account(id: UUID(), serverUrl: legacyUrl, username: legacyUser)
                KeychainService.saveToken(token, for: legacyUrl, username: legacyUser)
                KeychainService.deleteLegacyToken(for: legacyUrl)
                PersistenceService.migrateLegacyDocFiles(to: account.id)
                let fm = FileManager.default
                for filename in ["documents.json", "tags.json", "corrs.json", "types.json",
                                 "pending.json", "edits.json", "savedfilters.json"] {
                    let oldURL = PersistenceService.legacyDataURL(filename)
                    let newURL = PersistenceService.accountDataURL(for: account.id, filename: filename)
                    guard fm.fileExists(atPath: oldURL.path) else { continue }
                    if fm.fileExists(atPath: newURL.path) { try? fm.removeItem(at: newURL) }
                    try? fm.moveItem(at: oldURL, to: newURL)
                }
                loadedAccounts = [account]
                loadedActiveId = account.id
                AccountService.save(loadedAccounts)
                AccountService.setActiveId(loadedActiveId)
            }
            UserDefaults.standard.removeObject(forKey: "serverUrl")
            UserDefaults.standard.removeObject(forKey: "username")
            UserDefaults.standard.set(true, forKey: "migrated_to_v2")
        }

        accounts = loadedAccounts
        activeAccountId = loadedActiveId

        if let id = loadedActiveId,
           let account = loadedAccounts.first(where: { $0.id == id }),
           KeychainService.loadToken(for: account.serverUrl, username: account.username) != nil {
            loadFromDisk(for: id)
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
        guard let account = activeAccount else { return "" }
        return KeychainService.loadToken(for: account.serverUrl, username: account.username) ?? ""
    }

    func hasValidToken() -> Bool {
        guard let account = activeAccount else { return false }
        return KeychainService.loadToken(for: account.serverUrl, username: account.username) != nil
    }

    // MARK: - Account Management

    func addAccount(_ account: Account) {
        if let existing = accounts.first(where: {
            $0.serverUrl == account.serverUrl && $0.username == account.username
        }) {
            switchAccount(to: existing.id)
            return
        }
        accounts.append(account)
        AccountService.save(accounts)
        switchAccount(to: account.id)
    }

    func switchAccount(to id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        AccountService.setActiveId(id)
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []; deadlines = []; scannedDeadlineDocIds = []
        pendingUploads = []; pendingEdits = []; savedFilters = []
        currentSearchText = ""; currentPage = 1; currentSearchPage = 1
        autoSyncTask?.cancel()
        if KeychainService.loadToken(for: serverUrl, username: username) != nil {
            loadFromDisk(for: id)
            calculateStorage()
            startAutoSync()
        }
    }

    func removeAccount(id: UUID) {
        guard accounts.count > 1 else { return }
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        PersistenceService.deleteAccountFiles(accountId: id)
        accounts.removeAll { $0.id == id }
        AccountService.save(accounts)
        if activeAccountId == id {
            if let first = accounts.first {
                switchAccount(to: first.id)
            } else {
                activeAccountId = nil
                AccountService.setActiveId(nil)
                documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []; deadlines = []; scannedDeadlineDocIds = []
                pendingUploads = []; pendingEdits = []; savedFilters = []
                autoSyncTask?.cancel()
            }
        }
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
        async let fields = try? api.fetchCustomFields()
        async let views = try? api.fetchSavedViews()
        async let stats = try? api.fetchStatistics()

        if let t = await tags { allTags = t }
        if let c = await corrs { allCorrespondents = c }
        if let tp = await types { allDocTypes = tp }
        if let f = await fields { allCustomFields = f }
        if let v = await views {
            serverViews = v
            migrateLocalFiltersToServer()
        }
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
                semanticActive = false
                reApplyPendingEdits()
                saveToDisk()
                updateFilteredDocs()
                indexDocumentsForSpotlight()
                autoScanNewDeadlines()
                isSyncing = false
                return
            } catch APIError.unauthorized {
                if let account = activeAccount {
                    KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                }
                lastSyncError = "Sitzung abgelaufen, bitte neu einloggen"
                needsReLogin = true
                isSyncing = false
                return
            } catch {
                // Abgebrochene Requests (z. B. bei Pull-to-Refresh, wenn SwiftUI den Task
                // abbricht) sind kein echter Fehler – nicht in den Offline-Modus wechseln.
                let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
                if isCancelled {
                    isSyncing = false
                    return
                }
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
            let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if !isCancelled { lastSyncError = error.localizedDescription }
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
        semanticActive = false
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
                           corr: doc.correspondent, type: doc.documentType, asn: doc.archiveSerialNumber,
                           tags: merged, customFields: doc.customFields)
        }
    }

    func bulkAssignCorrespondent(_ corrId: Int, to docIds: Set<Int>) {
        for id in docIds {
            guard let doc = documents.first(where: { $0.id == id }) else { continue }
            addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                           corr: corrId, type: doc.documentType, asn: doc.archiveSerialNumber,
                           tags: doc.tags, customFields: doc.customFields)
        }
    }

    // MARK: - Filter & Sort

    /// Semantische KI-Suche: rangiert die aktuell gefilterten Dokumente nach inhaltlicher Nähe.
    func runSemanticSearch(_ query: String) {
        semanticActive = true
        let base = filteredDocs.isEmpty ? documents : filteredDocs
        filteredDocs = SemanticRanker.rank(query, in: base)
    }

    func updateFilteredDocs() {
        // Während eine semantische Suche aktiv ist, die Ergebnisliste nicht überschreiben.
        guard !semanticActive else { return }
        let calendar = Calendar.current
        let now = Date()

        let filtered = documents.filter { doc in
            let matchesTag = currentFilterTag == nil || doc.tags.contains(currentFilterTag!)
            let matchesCorr = currentFilterCorr == nil || doc.correspondent == currentFilterCorr
            let matchesType = currentFilterType == nil || doc.documentType == currentFilterType

            var matchesCustom = true
            if let fieldId = currentFilterCustomField {
                if let entry = doc.customFields.first(where: { $0.field == fieldId }), !entry.value.isEmpty {
                    if !currentFilterCustomText.isEmpty {
                        matchesCustom = customFieldDisplay(entry.value, fieldId: fieldId)
                            .localizedCaseInsensitiveContains(currentFilterCustomText)
                    }
                } else {
                    matchesCustom = false
                }
            }

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
            return matchesTag && matchesCorr && matchesType && matchesDate && matchesCustom
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

    func addPendingEdit(docId: Int, title: String, created: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int], customFields: [CustomFieldEdit] = []) {
        let iso = ISO8601DateFormatter().string(from: created)
        if let idx = documents.firstIndex(where: { $0.id == docId }) {
            documents[idx].title = title
            documents[idx].created = iso
            documents[idx].correspondent = corr
            documents[idx].documentType = type
            documents[idx].archiveSerialNumber = asn
            documents[idx].tags = tags
            documents[idx].customFields = customFields
        }
        let edit = PendingEdit(docId: docId, title: title, created: iso, correspondent: corr, documentType: type, archiveSerialNumber: asn, tags: tags, customFields: customFields)
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
                try await api.patchDocument(id: edit.docId, title: edit.title, created: edit.created, correspondent: edit.correspondent, documentType: edit.documentType, archiveSerialNumber: edit.archiveSerialNumber, tags: edit.tags, customFields: edit.customFields)
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
                documents[idx].customFields = edit.customFields
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
            guard let api = api, let accountId = activeAccountId else { return }
            try? await api.deleteDocument(id: id)
            documents.removeAll { $0.id == id }
            updateFilteredDocs()
            PersistenceService.deleteDocFile(docId: id, accountId: accountId)
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

    func fileExists(docId: Int) -> Bool {
        guard let id = activeAccountId else { return false }
        return PersistenceService.fileExists(docId: docId, accountId: id)
    }

    func localFileURL(for docId: Int) -> URL {
        guard let id = activeAccountId else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("doc_\(docId).pdf")
        }
        return PersistenceService.docFileURL(for: docId, accountId: id)
    }

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
        guard let id = activeAccountId else { return }
        PersistenceService.deleteDocFile(docId: docId, accountId: id)
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
        guard let id = activeAccountId else { return }
        Task.detached(priority: .background) {
            let result = PersistenceService.calculateStorage(accountId: id)
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
        guard let id = activeAccountId else { return }
        PersistenceService.save(documents,         toURL: PersistenceService.accountDataURL(for: id, filename: "documents.json"))
        PersistenceService.save(allTags,           toURL: PersistenceService.accountDataURL(for: id, filename: "tags.json"))
        PersistenceService.save(allCorrespondents, toURL: PersistenceService.accountDataURL(for: id, filename: "corrs.json"))
        PersistenceService.save(allDocTypes,       toURL: PersistenceService.accountDataURL(for: id, filename: "types.json"))
        PersistenceService.save(allCustomFields,   toURL: PersistenceService.accountDataURL(for: id, filename: "customfields.json"))
        PersistenceService.save(pendingUploads,    toURL: PersistenceService.accountDataURL(for: id, filename: "pending.json"))
        PersistenceService.save(pendingEdits,      toURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))
        PersistenceService.save(savedFilters,      toURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json"))
        PersistenceService.save(deadlines,         toURL: PersistenceService.accountDataURL(for: id, filename: "deadlines.json"))
        PersistenceService.save(Array(scannedDeadlineDocIds), toURL: PersistenceService.accountDataURL(for: id, filename: "deadlinescanned.json"))
    }

    func loadFromDisk(for id: UUID) {
        documents         = PersistenceService.load([Document].self,      fromURL: PersistenceService.accountDataURL(for: id, filename: "documents.json"))    ?? []
        allTags           = PersistenceService.load([Tag].self,            fromURL: PersistenceService.accountDataURL(for: id, filename: "tags.json"))         ?? []
        allCorrespondents = PersistenceService.load([Correspondent].self,  fromURL: PersistenceService.accountDataURL(for: id, filename: "corrs.json"))        ?? []
        allDocTypes       = PersistenceService.load([DocumentType].self,   fromURL: PersistenceService.accountDataURL(for: id, filename: "types.json"))        ?? []
        allCustomFields   = PersistenceService.load([CustomField].self,    fromURL: PersistenceService.accountDataURL(for: id, filename: "customfields.json")) ?? []
        pendingUploads    = PersistenceService.load([PendingUpload].self,  fromURL: PersistenceService.accountDataURL(for: id, filename: "pending.json"))      ?? []
        pendingEdits      = PersistenceService.load([PendingEdit].self,    fromURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))        ?? []
        savedFilters      = PersistenceService.load([SavedFilter].self,    fromURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json")) ?? []
        deadlines         = PersistenceService.load([Deadline].self,       fromURL: PersistenceService.accountDataURL(for: id, filename: "deadlines.json"))      ?? []
        scannedDeadlineDocIds = Set(PersistenceService.load([Int].self,    fromURL: PersistenceService.accountDataURL(for: id, filename: "deadlinescanned.json")) ?? [])
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

    // MARK: - Custom Fields

    func customField(id: Int) -> CustomField? { allCustomFields.first { $0.id == id } }

    /// Menschlich lesbare Darstellung eines Custom-Field-Werts (Select-Labels, Dokumenttitel aufgelöst).
    func customFieldDisplay(_ value: CFValue, fieldId: Int) -> String {
        let field = customField(id: fieldId)
        switch value {
        case .none: return "—"
        case .bool(let b): return b ? "Ja" : "Nein"
        case .integer(let i): return "\(i)"
        case .number(let d): return String(format: "%g", d)
        case .text(let s):
            if field?.type == .select, let opt = field?.extraData?.selectOptions?.first(where: { $0.id == s }) {
                return opt.safeLabel
            }
            return s
        case .ints(let ids):
            // documentlink: Titel auflösen, wo möglich
            return ids.map { id in documents.first(where: { $0.id == id })?.title ?? "#\(id)" }.joined(separator: ", ")
        case .strings(let arr): return arr.joined(separator: ", ")
        }
    }

    // MARK: - Tag-Hierarchie

    func childTags(of parentId: Int?) -> [Tag] {
        allTags.filter { $0.parent == parentId }.sorted { $0.safeName.localizedCompare($1.safeName) == .orderedAscending }
    }

    /// Flache Liste mit Tiefenangabe für eingerückte Darstellung.
    func hierarchicalTags() -> [(tag: Tag, depth: Int)] {
        var result: [(Tag, Int)] = []
        func walk(parent: Int?, depth: Int) {
            for tag in childTags(of: parent) {
                result.append((tag, depth))
                walk(parent: tag.id, depth: depth + 1)
            }
        }
        walk(parent: nil, depth: 0)
        // Tags, deren Parent nicht (mehr) existiert, hängen wir hinten an, damit nichts verloren geht.
        let included = Set(result.map { $0.0.id })
        for tag in allTags where !included.contains(tag.id) {
            result.append((tag, 0))
        }
        return result
    }

    // MARK: - Papierkorb

    func loadTrash() async {
        guard let api = api else { return }
        if let items = try? await api.fetchTrash() { trashedDocs = items }
    }

    func restoreFromTrash(ids: [Int]) {
        Task {
            guard let api = api else { return }
            try? await api.restoreFromTrash(ids: ids)
            await loadTrash()
            await loadFirstPage()
            showSuccessToast("Wiederhergestellt")
        }
    }

    func emptyTrash(ids: [Int]) {
        Task {
            guard let api = api else { return }
            try? await api.emptyTrash(ids: ids)
            await loadTrash()
            showSuccessToast("Endgültig gelöscht")
        }
    }

    // MARK: - Server Saved Views

    struct ParsedView {
        var tag: Int? = nil
        var corr: Int? = nil
        var type: Int? = nil
        var dateFilter: DateFilter = .all
        var customStart: Date? = nil
        var customEnd: Date? = nil
        var sort: SortOrder = .dateDesc
    }

    func loadSavedViews() async {
        guard let api = api else { return }
        if let v = try? await api.fetchSavedViews() {
            serverViews = v
            migrateLocalFiltersToServer()
        }
    }

    /// Übersetzt eine Server-View in unseren lokalen Filterzustand.
    func parse(_ view: SavedView) -> ParsedView {
        var p = ParsedView()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        for rule in view.filterRules {
            guard let raw = rule.value else { continue }
            switch rule.ruleType {
            case FilterRuleType.correspondent: p.corr = Int(raw)
            case FilterRuleType.documentType:  p.type = Int(raw)
            case FilterRuleType.hasTagAll:     p.tag = Int(raw)
            case FilterRuleType.createdAfter:
                if let d = df.date(from: String(raw.prefix(10))) { p.dateFilter = .custom; p.customStart = d }
            case FilterRuleType.createdBefore:
                if let d = df.date(from: String(raw.prefix(10))) { p.dateFilter = .custom; p.customEnd = d }
            default: break
            }
        }
        switch view.sortField {
        case "title":                p.sort = .titleAZ
        case "correspondent__name":  p.sort = .senderAZ
        case "added":                p.sort = (view.sortReverse ?? true) ? .addedDesc : .addedAsc
        default:                     p.sort = (view.sortReverse ?? true) ? .dateDesc : .dateAsc
        }
        return p
    }

    private func buildRules(tag: Int?, corr: Int?, type: Int?, dateFilter: DateFilter, start: Date, end: Date) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        if let tag { rules.append(["rule_type": FilterRuleType.hasTagAll, "value": "\(tag)"]) }
        if let corr { rules.append(["rule_type": FilterRuleType.correspondent, "value": "\(corr)"]) }
        if let type { rules.append(["rule_type": FilterRuleType.documentType, "value": "\(type)"]) }

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        switch dateFilter {
        case .all: break
        case .lastMonth:
            if let d = cal.date(byAdding: .month, value: -1, to: Date()) {
                rules.append(["rule_type": FilterRuleType.createdAfter, "value": df.string(from: d)])
            }
        case .thisYear:
            if let d = cal.date(from: cal.dateComponents([.year], from: Date())) {
                rules.append(["rule_type": FilterRuleType.createdAfter, "value": df.string(from: d)])
            }
        case .custom:
            rules.append(["rule_type": FilterRuleType.createdAfter, "value": df.string(from: start)])
            rules.append(["rule_type": FilterRuleType.createdBefore, "value": df.string(from: end)])
        }
        return rules
    }

    private func sortField(for order: SortOrder) -> (field: String, reverse: Bool) {
        switch order {
        case .dateDesc:  return ("created", true)
        case .dateAsc:   return ("created", false)
        case .titleAZ:   return ("title", false)
        case .senderAZ:  return ("correspondent__name", false)
        case .addedDesc: return ("added", true)
        case .addedAsc:  return ("added", false)
        }
    }

    func createServerView(name: String, tag: Int?, corr: Int?, type: Int?, dateFilter: DateFilter, start: Date, end: Date, sort: SortOrder) {
        guard !isDemoMode, let api = api else { return }
        let rules = buildRules(tag: tag, corr: corr, type: type, dateFilter: dateFilter, start: start, end: end)
        let s = sortField(for: sort)
        Task {
            if let view = try? await api.createSavedView(name: name, sortField: s.field, sortReverse: s.reverse, rules: rules) {
                serverViews.append(view)
                showSuccessToast("Ansicht gespeichert")
            }
        }
    }

    func deleteServerView(id: Int) {
        Task {
            guard let api = api else { return }
            try? await api.deleteSavedView(id: id)
            serverViews.removeAll { $0.id == id }
        }
    }

    /// Hebt bestehende lokale Filter einmalig auf den Server und leert danach die lokale Liste.
    private func migrateLocalFiltersToServer() {
        guard !savedFilters.isEmpty, !isDemoMode, let api = api else { return }
        let toMigrate = savedFilters
        Task {
            for f in toMigrate {
                let rules = buildRules(tag: f.tag, corr: f.correspondent, type: f.type,
                                       dateFilter: f.dateFilter, start: Date(), end: Date())
                if let view = try? await api.createSavedView(name: f.name, sortField: "created", sortReverse: true, rules: rules) {
                    serverViews.append(view)
                }
            }
            savedFilters.removeAll()
            saveToDisk()
        }
    }

    // MARK: - Share Links

    func fetchShareLinks(documentId: Int) async -> [DocShareLink] {
        guard let api = api else { return [] }
        return (try? await api.fetchShareLinks(documentId: documentId)) ?? []
    }

    func createShareLink(documentId: Int, expiration: Date?, fileVersion: String) async -> DocShareLink? {
        guard let api = api else { return nil }
        return try? await api.createShareLink(documentId: documentId, expiration: expiration, fileVersion: fileVersion)
    }

    func deleteShareLink(id: Int) async {
        guard let api = api else { return }
        try? await api.deleteShareLink(id: id)
    }

    // MARK: - Fristen-Radar

    var fristenRadarEnabled: Bool { UserDefaults.standard.object(forKey: "fristenRadarEnabled") as? Bool ?? true }

    /// Neue, noch nicht gescannte Dokumente automatisch prüfen (gedeckelt, im Hintergrund).
    func autoScanNewDeadlines() {
        guard fristenRadarEnabled, AIService.shared.isAvailable, !isDemoMode, !isScanningDeadlines else { return }
        let pending = documents.filter { $0.content?.isEmpty == false && !scannedDeadlineDocIds.contains($0.id) }
        guard !pending.isEmpty else { return }
        Task { await scanDeadlines(Array(pending.prefix(10))) }
    }

    /// Manueller Komplett-Scan aller noch nicht gescannten Dokumente.
    func scanAllForDeadlines() {
        guard AIService.shared.isAvailable, !isScanningDeadlines else { return }
        let pending = documents.filter { $0.content?.isEmpty == false && !scannedDeadlineDocIds.contains($0.id) }
        Task { await scanDeadlines(pending) }
    }

    private func scanDeadlines(_ docs: [Document]) async {
        guard !docs.isEmpty else { return }
        isScanningDeadlines = true
        for (index, doc) in docs.enumerated() {
            deadlineScanStatus = "Prüfe \(index + 1) von \(docs.count) …"
            let extracted = await AIService.shared.extractDeadlines(text: doc.content ?? "")
            for e in extracted {
                deadlines.append(Deadline(docId: doc.id, docTitle: doc.title, typeRaw: e.type.rawValue, date: e.date, detail: e.detail))
            }
            scannedDeadlineDocIds.insert(doc.id)
        }
        deadlines.sort { $0.date < $1.date }
        saveToDisk()
        isScanningDeadlines = false
        deadlineScanStatus = ""
    }

    func removeDeadline(_ id: UUID) {
        deadlines.removeAll { $0.id == id }
        saveToDisk()
    }

    func draftCancellation(for deadline: Deadline) async -> String? {
        guard let doc = documents.first(where: { $0.id == deadline.docId }) else { return nil }
        let name = UserDefaults.standard.string(forKey: "senderName") ?? ""
        let address = UserDefaults.standard.string(forKey: "senderAddress") ?? ""
        return await AIService.shared.draftCancellation(documentText: doc.content ?? doc.title,
                                                         senderName: name, senderAddress: address)
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
        for account in accounts {
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        }
        accounts = []
        activeAccountId = nil
        AccountService.save([])
        AccountService.setActiveId(nil)
        isDemoMode = false
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []; deadlines = []; scannedDeadlineDocIds = []
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
        let demoAccount = Account(id: UUID(), serverUrl: "demo.local", username: "demo")
        accounts = [demoAccount]
        activeAccountId = demoAccount.id
        AccountService.save(accounts)
        AccountService.setActiveId(demoAccount.id)
        allTags = [Tag(id: 1, name: "Rechnung", color: "#ff0000", parent: nil)]
        allCorrespondents = [Correspondent(id: 1, name: "Amazon")]
        allDocTypes = [DocumentType(id: 1, name: "Rechnung")]
        documents = [Document(id: 1, title: "Demo", content: "Text", created: "2026-01-26",
                              added: nil, correspondent: 1, documentType: 1,
                              archiveSerialNumber: 100, tags: [1])]
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

    func triggerOpenDocument(id: Int) {
        widgetOpenDocId = id
    }

    func selectDocumentForPicker(doc: Document) {
        selectDocumentsForPicker(docs: [doc])
    }

    /// Übergibt ein oder mehrere Dokumente an Vermietoo (Mehrfachauswahl).
    func selectDocumentsForPicker(docs: [Document]) {
        guard let callbackURLStr = pickerCallbackURL,
              let callbackURL = URL(string: callbackURLStr), !docs.isEmpty else { return }

        pickerCallbackURL = nil

        Task {
            guard let api = api else { return }
            // Bei Einzelauswahl: PDF wie bisher über die Exchange-Pasteboard übergeben.
            if docs.count == 1, let only = docs.first,
               let pdfData = try? await api.downloadDocument(id: only.id) {
                let pasteboard = UIPasteboard(name: UIPasteboard.Name("PaperlessExchange"), create: true)
                pasteboard?.setData(pdfData, forPasteboardType: "com.paperless24.data")
            }

            var components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            for doc in docs {
                items.append(URLQueryItem(name: "id", value: "\(doc.id)"))
            }
            if docs.count == 1 {
                items.append(URLQueryItem(name: "title", value: docs[0].title))
            }
            components?.queryItems = items
            if let finalURL = components?.url {
                await MainActor.run { UIApplication.shared.open(finalURL) }
            }
        }
    }

    // MARK: - Hintergrund-Benachrichtigung

    /// Lädt die Inbox-Zahl und liefert sie zurück, wenn sie seit dem letzten Check gestiegen ist.
    /// Wird vom BGAppRefreshTask genutzt. Gibt die neue Zahl zurück, sonst nil.
    func checkInboxForNotification() async -> Int? {
        guard let api = api, let stats = try? await api.fetchStatistics() else { return nil }
        let current = stats.documentsInbox ?? 0
        let last = UserDefaults.standard.integer(forKey: "lastNotifiedInbox")
        UserDefaults.standard.set(current, forKey: "lastNotifiedInbox")
        return current > last ? current : nil
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
