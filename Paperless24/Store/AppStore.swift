import SwiftUI
import CoreSpotlight
import PDFKit
import Vision
import WidgetKit
import os

@MainActor
class AppStore: ObservableObject {

    /// Schwache Referenz auf die aktive Instanz — von App Intents (Siri/Kurzbefehle) genutzt.
    static weak var shared: AppStore?

    private static let logger = Logger(subsystem: "de.tedi.paperless", category: "spotlight")

    // MARK: - Published State

    @Published var documents: [Document] = []
    @Published var filteredDocs: [Document] = []
    @Published var allTags: [Tag] = []
    @Published var allCorrespondents: [Correspondent] = []
    @Published var allDocTypes: [DocumentType] = []
    @Published var allCustomFields: [CustomField] = []
    @Published var trashedDocs: [TrashDocument] = []
    @Published var serverViews: [SavedView] = []
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
    /// Gesamtzahl der Treffer der aktuellen Server-Anfrage (`count` der Antwort). Nur gesetzt,
    /// solange ein Filter oder eine Suche aktiv ist — sonst zählt `documents`.
    @Published var queryTotalCount: Int? = nil

    /// Seitengröße der Liste, wie in den Einstellungen gewählt.
    static var listPageSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "pageSize")
        return stored > 0 ? stored : 25
    }
    /// Aktiv, solange eine semantische KI-Suche die Ergebnisliste bestimmt.
    @Published var needsReLogin = false
    @Published var savedFilters: [SavedFilter] = []
    @Published var widgetOpenDocId: Int? = nil
    @Published var pickerCallbackURL: String? = nil

    // App-Intent-Aktionen (von Siri/Kurzbefehlen ausgelöst)
    @Published var requestScan = false
    @Published var requestInbox = false
    @Published var pendingSearch: String? = nil
    @Published var requestAskArchive = false
    @Published var shouldRequestReview = false

    // MARK: - Posteingang
    //
    // paperless-ngx definiert den Posteingang über Tags mit `is_inbox_tag`. Die App hat ihn
    // früher als „Dokument ohne Sender" gelesen — in einem gepflegten Archiv sind das hunderte
    // längst bearbeitete Dokumente, während der Server selbst nur eine Handvoll meldet
    // (Issue #1: Abzeichen 542 gegenüber 1 im Dashboard).

    /// Dokumente mit Inbox-Tag, vom Server geladen (`loadInbox()`).
    @Published var inboxDocuments: [Document] = []
    @Published var isLoadingInbox = false
    /// Gesamtzahl laut Server. `nil`, solange keine Antwort vorliegt.
    @Published var inboxTotal: Int? = nil

    var inboxTagIDs: Set<Int> { Set(allTags.filter(\.isInbox).map(\.id)) }

    var inboxCount: Int { inboxTotal ?? inboxDocuments.count }

    /// Rückfallebene ohne Server: filtert die bereits geladenen Dokumente.
    private var cachedInboxDocs: [Document] {
        let ids = inboxTagIDs
        guard !ids.isEmpty else { return [] }
        return documents.filter { !ids.isDisjoint(with: $0.tags) }
    }

    /// Lädt den Posteingang beim Server. Ohne Inbox-Tag gibt es keinen Posteingang —
    /// dann ist er leer, genau wie in der Weboberfläche.
    func loadInbox() async {
        let ids = inboxTagIDs
        guard !ids.isEmpty else {
            inboxDocuments = []
            inboxTotal = 0
            return
        }
        if isDemoMode {
            inboxDocuments = cachedInboxDocs
            inboxTotal = inboxDocuments.count
            return
        }
        guard let api = api else {
            inboxDocuments = cachedInboxDocs
            return
        }
        isLoadingInbox = true
        do {
            let page = try await api.fetchDocuments(tagIDs: Array(ids), page: 1)
            inboxDocuments = page.documents.uniquedByID()
            inboxTotal = page.totalCount ?? inboxDocuments.count
        } catch {
            let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if !isCancelled { inboxDocuments = cachedInboxDocs }
        }
        reApplyPendingEditsToInbox()
        isLoadingInbox = false
    }

    /// Hält den Posteingang nach einer Bearbeitung aktuell: Wer sein Inbox-Tag verliert,
    /// verschwindet daraus, wer eins bekommt, kommt hinzu.
    private func updateInboxMembership(for doc: Document) {
        let ids = inboxTagIDs
        guard !ids.isEmpty else { return }
        let belongs = !ids.isDisjoint(with: doc.tags)
        let idx = inboxDocuments.firstIndex { $0.id == doc.id }
        if belongs {
            if let idx {
                inboxDocuments[idx] = doc
            } else {
                inboxDocuments.insert(doc, at: 0)
                if let total = inboxTotal { inboxTotal = total + 1 }
            }
        } else if let idx {
            inboxDocuments.remove(at: idx)
            if let total = inboxTotal { inboxTotal = max(0, total - 1) }
        }
    }

    /// Noch nicht übertragene Bearbeitungen auch auf den frisch geladenen Posteingang anwenden —
    /// sonst taucht ein offline bearbeitetes Dokument dort wieder mit altem Stand auf.
    private func reApplyPendingEditsToInbox() {
        guard !pendingEdits.isEmpty else { return }
        for edit in pendingEdits {
            guard let idx = inboxDocuments.firstIndex(where: { $0.id == edit.docId }) else { continue }
            inboxDocuments[idx] = edit.applied(to: inboxDocuments[idx])
        }
        let ids = inboxTagIDs
        guard !ids.isEmpty else { return }
        inboxDocuments.removeAll { ids.isDisjoint(with: $0.tags) }
        inboxTotal = inboxDocuments.count
    }

    // MARK: - Settings

    @AppStorage("isDemoMode") var isDemoMode = false

    /// Kennzahlen für den Demo-Modus — es gibt keinen Server, der sie liefern könnte.
    private var demoStatistics: PaperlessStatistics? = nil

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

    /// Tags, die ein Dokument *nicht* tragen darf.
    var currentFilterExcludedTags: Set<Int> = []
    /// Mehrfachauswahl: leere Menge = keine Einschränkung. `currentFilterTag` & Co. bleiben
    /// als Einzelwert für die Schnellfilter-Chips erhalten und werden hier mit eingerechnet.
    var currentFilterTags: Set<Int> = []
    var currentFilterCorrs: Set<Int> = []
    var currentFilterTypes: Set<Int> = []

    /// Zuletzt an den Server geschickte Anfrage — verhindert, dass `applyFilters()` bei jedem
    /// `onAppear` der Liste erneut lädt, obwohl sich nichts geändert hat.
    private var lastAppliedQuery: DocumentQuery? = nil

    /// Alle Filter und die Suche als eine Server-Anfrage.
    var activeQuery: DocumentQuery {
        let bounds = DocumentQuery.dateBounds(
            filter: currentDateFilter, customStart: customStartDate, customEnd: customEndDate
        )
        var tags = currentFilterTags
        if let single = currentFilterTag { tags.insert(single) }
        var corrs = currentFilterCorrs
        if let single = currentFilterCorr { corrs.insert(single) }
        var types = currentFilterTypes
        if let single = currentFilterType { types.insert(single) }

        return DocumentQuery(
            tagIDs: tags,
            excludedTagIDs: currentFilterExcludedTags,
            correspondentIDs: corrs,
            documentTypeIDs: types,
            createdFrom: bounds.from,
            createdTo: bounds.to,
            customFieldID: currentFilterCustomField,
            customFieldText: currentFilterCustomText,
            searchText: currentSearchText
        )
    }

    /// Filtert der Server? Offline, im Demo-Modus und auf Servern, die einen der Parameter
    /// nicht kennen, bleibt nur die lokale Einschränkung der geladenen Dokumente.
    var isServerFiltering: Bool {
        !isDemoMode && !isOffline && DocumentFilterSupport.isSupported(serverUrl)
    }

    /// Liegt in `filteredDocs` eine Server-Antwort (Filter oder Suche) statt der lokal
    /// eingeschränkten Gesamtliste? Entscheidet, wie weitergeblättert wird.
    var isQueryActive: Bool { isServerFiltering && !activeQuery.isEmpty }

    /// Zahl für die Kopfzeile der Liste.
    ///
    /// Bei aktivem Filter die Gesamtzahl der Treffer, die der Server meldet — `filteredDocs`
    /// enthält dann nur die bisher geladenen Seiten davon.
    var listCount: Int { (isQueryActive ? queryTotalCount : nil) ?? filteredDocs.count }

    // MARK: - Private

    private var api: PaperlessAPI? {
        guard let account = activeAccount, !account.serverUrl.isEmpty,
              let token = currentToken() else { return nil }
        return PaperlessAPI(serverUrl: account.serverUrl, token: token)
    }

    /// Zwischenspeicher für den Token des aktiven Kontos.
    ///
    /// Ein Keychain-Zugriff ist ein synchroner Systemaufruf. `authToken()` steht in den
    /// Listen direkt im `ForEach`-Rumpf — ohne diesen Zwischenspeicher liefe er pro
    /// gezeichneter Zelle erneut, beim Scrollen also hunderte Male auf dem Main Thread.
    /// `tokenCacheLoaded` unterscheidet „noch nicht gelesen" von „gelesen, kein Token da".
    private var tokenCache: String?
    private var tokenCacheLoaded = false

    private func currentToken() -> String? {
        if tokenCacheLoaded { return tokenCache }
        guard let account = activeAccount else { return nil }
        tokenCache = KeychainService.loadToken(for: account.serverUrl, username: account.username)
        tokenCacheLoaded = true
        return tokenCache
    }

    /// Nach jedem Kontowechsel und jeder Änderung am Keychain aufzurufen.
    func invalidateTokenCache() {
        tokenCache = nil
        tokenCacheLoaded = false
    }

    private var currentPage = 1
    private var searchTask: Task<Void, Never>? = nil
    private var autoSyncTask: Task<Void, Never>? = nil
    private var downloadTask: Task<Void, Never>? = nil
    /// Sperren gegen mehrfach parallel laufende Warteschlangen — siehe `processUploadQueue()`.
    private var isProcessingUploads = false
    private var isProcessingEdits = false

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
        ImageCache.shared.setAccount(loadedActiveId)
        loadUploadRules()

        if let id = loadedActiveId, hasValidToken() {
            // Bewusst nicht synchron: das Dekodieren von `documents.json` dauert bei großen
            // Archiven leicht einige hundert Millisekunden und verzögerte bisher den ersten
            // Frame. Die Ansicht startet leer und füllt sich, sobald die Daten da sind.
            Task { await loadFromDiskAsync(for: id) }
            calculateStorage()
            startAutoSync()
        }
    }

    // MARK: - API Access

    func makeServerBase() -> String {
        // Im Demo-Modus gibt es keine API-Instanz. Ansichten prüfen aber auf eine nicht-leere
        // Basis, bevor sie eine Miniaturansicht zeigen — die stammt dort aus dem `ImageCache`.
        if isDemoMode { return "https://demo.local" }
        return api?.serverBase ?? ""
    }

    func thumbnailURL(for docId: Int) -> String {
        api?.thumbnailURL(for: docId) ?? ""
    }

    func authToken() -> String {
        // Im Demo-Modus liegt kein Token im Keychain. Die Ansichten prüfen aber auf einen
        // nicht-leeren Token, bevor sie überhaupt eine Miniaturansicht zeigen — und die
        // kommt hier aus dem lokalen `ImageCache`, nicht vom Server.
        if isDemoMode { return "demo" }
        return currentToken() ?? ""
    }

    func hasValidToken() -> Bool {
        currentToken() != nil
    }

    // MARK: - Account Management

    func addAccount(_ account: Account) {
        invalidateTokenCache()
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
        // Token und Miniaturansichten gehören zum Konto — beides muss mitwechseln, sonst
        // zeigt die Liste die Vorschauen des vorherigen Kontos.
        invalidateTokenCache()
        ImageCache.shared.setAccount(id)
        // Die Systemsuche zeigt nur das aktive Konto. Sonst stünden die Dokumenttitel eines
        // Archivs weiter in Spotlight, während ein anderes Konto geöffnet ist.
        clearSpotlightIndex()
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []
        pendingUploads = []; pendingEdits = []; savedFilters = []
        currentSearchText = ""; currentPage = 1; currentSearchPage = 1
        autoSyncTask?.cancel()
        if hasValidToken() {
            Task { await loadFromDiskAsync(for: id) }
            calculateStorage()
            startAutoSync()
        }
    }

    func removeAccount(id: UUID) {
        guard accounts.count > 1 else { return }
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        invalidateTokenCache()
        PersistenceService.deleteAccountFiles(accountId: id)
        ImageCache.shared.deleteAccount(id)
        clearSpotlightIndex(for: id)
        accounts.removeAll { $0.id == id }
        AccountService.save(accounts)
        if activeAccountId == id {
            if let first = accounts.first {
                switchAccount(to: first.id)
            } else {
                activeAccountId = nil
                AccountService.setActiveId(nil)
                ImageCache.shared.setAccount(nil)
                documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []
                pendingUploads = []; pendingEdits = []; savedFilters = []
                autoSyncTask?.cancel()
            }
        }
    }

    // MARK: - Sync

    /// Zeitpunkt des letzten erfolgreichen Ladens — Grundlage für die Drosselung.
    private(set) var lastSuccessfulSync: Date? = nil

    /// Mindestabstand zwischen zwei automatisch ausgelösten Syncs.
    ///
    /// `MainDocView.onAppear` läuft bei jeder Rückkehr aus der Detailansicht. Ohne Drosselung
    /// lädt die App dabei jedes Mal die erste Seite neu, ersetzt die Liste und schreibt alles
    /// auf die Platte — bei jedem Zurück-Tippen.
    private static let autoSyncMinInterval: TimeInterval = 20

    /// Läuft gerade ein Sync? Verhindert, dass sich zwei Läufe überlagern.
    private var isSyncRunning = false

    func sync(silent: Bool = false) {
        guard !isDemoMode, !serverUrl.isEmpty else { return }
        guard !isSyncRunning else { return }
        if !silent { isSyncing = true }
        isSyncRunning = true
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.loadFirstPage(silent: silent) }
                group.addTask { await self.syncMetadata() }
                if !self.pendingUploads.isEmpty { group.addTask { await self.processUploadQueue() } }
                await self.processEditQueue()
            }
            isSyncRunning = false
            if silent { isSyncing = false }
        }
    }

    /// Sync beim Erscheinen der Liste — nur, wenn es etwas zu holen gibt.
    ///
    /// Beim ersten Aufbau (leere Liste) sofort und sichtbar, danach höchstens alle 20 Sekunden
    /// und dann still im Hintergrund. Zum Aktualisieren ziehen umgeht die Drosselung.
    func syncIfStale() {
        guard !isDemoMode, !serverUrl.isEmpty else { return }
        if documents.isEmpty {
            sync()
            return
        }
        if let last = lastSuccessfulSync,
           Date().timeIntervalSince(last) < Self.autoSyncMinInterval { return }
        sync(silent: true)
    }

    private func syncMetadata() async {
        guard let api = api else { return }
        // Speicherpfade gehören zu den Stammdaten; Benutzer und Gruppen werden erst dann
        // geholt, wenn jemand die Rechte tatsächlich öffnet (dafür braucht es Adminrechte).
        if let paths = try? await api.fetchStoragePaths() { allStoragePaths = paths }
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
        if let inbox = resolvedStats?.documentsInbox { inboxTotal = inbox }
        updateWidget(stats: resolvedStats)
        await loadInbox()
    }

    // MARK: - Pagination

    func loadFirstPage(silent: Bool = false) async {
        guard let api = api else {
            isSyncing = false
            needsReLogin = true
            return
        }
        // Ein stiller Sync darf die Anzeige nicht anfassen: Die Fortschrittsanzeige beim
        // Zurückkehren aus der Detailansicht war der Hauptgrund, warum das Laden ruckelig
        // wirkte — sie erschien und verschwand bei jedem Wechsel.
        if !silent { isSyncing = true }
        for attempt in 1...2 {
            do {
                let page = try await api.fetchDocuments(page: 1, ordering: orderingParam())
                // Hat der Nutzer schon nachgeladen, darf ein stiller Sync die Liste nicht auf
                // die erste Seite zurückschneiden — sie würde unter dem Finger zusammenklappen
                // und die Scrollposition verlieren. Dann wird die erste Seite eingepflegt und
                // der Blätterstand bleibt, wie er ist.
                if silent && documents.count > page.documents.count {
                    mergeFirstPage(page.documents)
                } else {
                    documents = page.documents.uniquedByID()
                    hasNextPage = page.hasNext
                    currentPage = 1
                }
                isOffline = false
                lastSyncError = nil
                reApplyPendingEdits()
                saveToDisk()
                updateFilteredDocs()
                indexDocumentsForSpotlightIfDue()
                updateArchiveIndexIncrementally()
                lastSuccessfulSync = Date()
                if !silent { isSyncing = false }
                return
            } catch APIError.unauthorized {
                if let account = activeAccount {
                    KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                }
                invalidateTokenCache()
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

    /// Pflegt die erste Server-Seite in die bestehende Liste ein.
    ///
    /// Bekannte Dokumente werden aktualisiert, neue vorn eingefügt. Was weiter hinten schon
    /// geladen war, bleibt geladen.
    private func mergeFirstPage(_ fresh: [Document]) {
        var index: [Int: Int] = [:]
        for (position, doc) in documents.enumerated() { index[doc.id] = position }

        var newcomers: [Document] = []
        for doc in fresh {
            if let position = index[doc.id] {
                documents[position] = doc
            } else {
                newcomers.append(doc)
            }
        }
        if !newcomers.isEmpty {
            documents.insert(contentsOf: newcomers, at: 0)
        }
    }

    /// Zum Aktualisieren ziehen.
    ///
    /// Aktualisiert die Gesamtliste und, wenn ein Filter oder eine Suche aktiv ist, auch die
    /// Trefferliste. Ohne den zweiten Schritt bliebe die sichtbare Liste beim Ziehen
    /// unverändert, weil sie dann aus der Server-Antwort und nicht aus `documents` kommt.
    func refreshList() async {
        await reloadVisible()
    }

    /// Verwirft Drosselung und zuletzt gestellte Anfrage.
    ///
    /// Nach einer Änderung am Bestand darf weder der Mindestabstand zwischen zwei Syncs noch
    /// die Prüfung „gleiche Anfrage wie eben" ein Nachladen verhindern.
    func invalidateLoadState() {
        lastSuccessfulSync = nil
        lastAppliedQuery = nil
    }

    /// Lädt genau das neu, was gerade sichtbar ist.
    ///
    /// `loadFirstPage()` allein genügt nicht: Es füllt `documents`, angezeigt wird bei aktivem
    /// Filter oder aktiver Suche aber `filteredDocs` — die Antwort des Servers. Wer nach einem
    /// Upload nur die Gesamtliste nachlud, sah die Trefferliste unverändert stehen und hielt
    /// das Laden zu Recht für unzuverlässig.
    func reloadVisible() async {
        invalidateLoadState()
        await loadFirstPage()
        guard isQueryActive else { return }
        await runQuery(addingToRecents: nil)
    }

    func loadNextPage() async {
        guard !isLoadingMore, hasNextPage, let api = api else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let page = try await api.fetchDocuments(page: nextPage, ordering: orderingParam())
            documents.appendUniqueByID(page.documents)
            hasNextPage = page.hasNext
            currentPage = nextPage
            updateFilteredDocs()
        } catch {
            let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if !isCancelled { lastSyncError = error.localizedDescription }
        }
        isLoadingMore = false
    }

    /// Sortierparameter für `/api/documents/`.
    ///
    /// `-id` als zweites Kriterium ist Pflicht: seit API-Version 9 ist `created` ein reines
    /// Datum ohne Uhrzeit, sehr viele Dokumente teilen sich also denselben Sortierwert. Ohne
    /// eindeutiges Zweitkriterium ordnet die Datenbank gleichrangige Zeilen bei jeder Abfrage
    /// anders — Seite 2 liefert dann Dokumente erneut, die schon auf Seite 1 standen, und
    /// andere fallen ganz aus der Liste.
    private func orderingParam() -> String {
        switch currentSortOrder {
        case .dateDesc:  return "-created,-id"
        case .dateAsc:   return "created,id"
        case .titleAZ:   return "title,id"
        case .senderAZ:  return "correspondent__name,id"
        case .addedDesc: return "-added,-id"
        case .addedAsc:  return "added,id"
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
            // Suchbegriff gelöscht: Wenn noch Filter gesetzt sind, muss die gefilterte
            // Anfrage neu laufen; sonst genügt die schon geladene Gesamtliste.
            applyFilters(debounce: false)
            return
        }
        searchTask = Task {
            isSearching = true
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await runQuery(addingToRecents: query)
            isSearching = false
        }
    }

    /// Übernimmt den aktuellen Filter- und Suchzustand.
    ///
    /// Läuft bei jeder Änderung in der Oberfläche und bei jedem `onAppear` der Liste. Eine
    /// unveränderte Anfrage löst deshalb bewusst kein erneutes Laden aus.
    func applyFilters(debounce: Bool = true) {
        let query = activeQuery

        guard isServerFiltering, !query.isEmpty else {
            // Lokale Einschränkung der geladenen Dokumente (offline, Demo, alter Server)
            // oder gar kein Filter — beides braucht keine Anfrage.
            lastAppliedQuery = nil
            updateFilteredDocs()
            return
        }
        guard query != lastAppliedQuery else {
            // Gleiche Anfrage: nur die lokale Nachbearbeitung erneuern.
            refineQueryResult()
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            if debounce {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { isSearching = false; return }
            }
            await runQuery(addingToRecents: nil)
            isSearching = false
        }
    }

    /// Holt Seite 1 der gefilterten Liste vom Server.
    ///
    /// Das Ergebnis landet in `filteredDocs`, nicht in `documents`: `documents` ist der
    /// Offline-Cache, die Quelle für Spotlight und für „Archiv fragen" und muss die
    /// *ungefilterte* Liste bleiben. Ein Filter darf den Cache nicht auf seine Treffer
    /// zusammenschrumpfen.
    private func runQuery(addingToRecents recent: String?) async {
        let query = activeQuery

        // Ohne Server — offline oder Demo — bleibt nur die lokale Liste.
        guard isServerFiltering, let api = api else {
            updateFilteredDocs()
            if let recent { addRecentSearch(recent) }
            return
        }

        do {
            let page = try await api.fetchDocuments(
                query: query, page: 1, pageSize: Self.listPageSize, ordering: orderingParam()
            )
            filteredDocs = page.documents.uniquedByID()
            searchHasNextPage = page.hasNext
            currentSearchPage = 1
            queryTotalCount = page.totalCount
            lastAppliedQuery = query
            reApplyPendingEditsToQueryResult()
            refineQueryResult()
            if let recent { addRecentSearch(recent) }
        } catch APIError.serverError(400) {
            // Der Server kennt einen der Filterparameter nicht. Für diesen Server dauerhaft
            // auf lokale Filterung zurückfallen — eine leere Liste wäre das schlechtere
            // Ergebnis als ein unvollständiger Filter mit Hinweis.
            DocumentFilterSupport.disable(serverUrl)
            lastAppliedQuery = nil
            updateFilteredDocs()
        } catch {
            let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
            if !isCancelled { lastSyncError = error.localizedDescription }
        }
    }

    /// Nachbearbeitung der Server-Antwort: der Textvergleich im eigenen Feld bleibt lokal
    /// (siehe `DocumentQuery.customFieldText`).
    private func refineQueryResult() {
        guard isQueryActive else { return }
        let query = activeQuery
        guard query.needsLocalCustomFieldMatch, let fieldId = query.customFieldID else { return }
        filteredDocs = filteredDocs.filter { doc in
            guard let entry = doc.customFields.first(where: { $0.field == fieldId }), !entry.value.isEmpty
            else { return false }
            return customFieldDisplay(entry.value, fieldId: fieldId)
                .localizedCaseInsensitiveContains(query.customFieldText)
        }
    }

    /// Noch nicht übertragene Änderungen auch auf die Trefferliste anwenden.
    private func reApplyPendingEditsToQueryResult() {
        guard !pendingEdits.isEmpty else { return }
        for edit in pendingEdits {
            guard let idx = filteredDocs.firstIndex(where: { $0.id == edit.docId }) else { continue }
            filteredDocs[idx] = edit.applied(to: filteredDocs[idx])
        }
    }

    func loadNextSearchPage() async {
        guard !isSearching, searchHasNextPage, let api = api, isQueryActive else { return }
        isSearching = true
        let nextPage = currentSearchPage + 1
        do {
            let page = try await api.fetchDocuments(
                query: activeQuery, page: nextPage,
                pageSize: Self.listPageSize, ordering: orderingParam()
            )
            filteredDocs.appendUniqueByID(page.documents)
            searchHasNextPage = page.hasNext
            currentSearchPage = nextPage
            reApplyPendingEditsToQueryResult()
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

    /// Rückmeldung der letzten Sammelaktion für die Oberfläche.
    @Published var bulkResultMessage: String? = nil
    @Published var isBulkEditing = false

    /// Tags zuweisen.
    func bulkAssignTags(_ tagIds: [Int], to docIds: Set<Int>) {
        bulkModifyTags(add: tagIds, remove: [], in: docIds)
    }

    /// Tags entfernen — mit `bulk_edit` genauso billig wie zuweisen.
    func bulkRemoveTags(_ tagIds: [Int], from docIds: Set<Int>) {
        bulkModifyTags(add: [], remove: tagIds, in: docIds)
    }

    /// Tags in einem Server-Aufruf ändern.
    ///
    /// Offline oder auf einem Server ohne `bulk_edit` bleibt die bisherige Einzel-PATCH-
    /// Warteschlange als Rückfallebene — sonst ginge die Aktion ohne Netz verloren.
    func bulkModifyTags(add: [Int], remove: [Int], in docIds: Set<Int>) {
        guard !docIds.isEmpty, !(add.isEmpty && remove.isEmpty) else { return }
        let ids = Array(docIds)

        guard let api = api, !isOffline, !isDemoMode else {
            queueTagChange(add: add, remove: remove, in: docIds)
            return
        }
        Task {
            isBulkEditing = true
            do {
                try await api.bulkModifyTags(ids: ids, add: add, remove: remove)
                applyTagChangeLocally(add: add, remove: remove, in: docIds)
                invalidateLoadState()
                bulkResultMessage = "\(ids.count) Dokument(e) geändert"
            } catch {
                // Nicht verloren geben: als Einzeländerungen in die Warteschlange, die sie
                // später erneut versucht.
                queueTagChange(add: add, remove: remove, in: docIds)
                bulkResultMessage = "In Warteschlange — \(error.localizedDescription)"
            }
            isBulkEditing = false
        }
    }

    func bulkAssignCorrespondent(_ corrId: Int, to docIds: Set<Int>) {
        guard !docIds.isEmpty else { return }
        let ids = Array(docIds)
        guard let api = api, !isOffline, !isDemoMode else {
            for id in docIds {
                guard let doc = anyLoadedDocument(id) else { continue }
                addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                               corr: corrId, type: doc.documentType, asn: doc.archiveSerialNumber,
                               tags: doc.tags, customFields: doc.customFields)
            }
            return
        }
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetCorrespondent(ids: ids, correspondent: corrId)
                mutateLoadedDocuments(ids: docIds) { $0.correspondent = corrId }
                bulkResultMessage = "\(ids.count) Dokument(e) geändert"
            } catch {
                bulkResultMessage = error.localizedDescription
            }
            isBulkEditing = false
        }
    }

    func bulkAssignDocumentType(_ typeId: Int, to docIds: Set<Int>) {
        guard !docIds.isEmpty else { return }
        let ids = Array(docIds)
        guard let api = api, !isOffline, !isDemoMode else {
            for id in docIds {
                guard let doc = anyLoadedDocument(id) else { continue }
                addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                               corr: doc.correspondent, type: typeId, asn: doc.archiveSerialNumber,
                               tags: doc.tags, customFields: doc.customFields)
            }
            return
        }
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetDocumentType(ids: ids, documentType: typeId)
                mutateLoadedDocuments(ids: docIds) { $0.documentType = typeId }
                bulkResultMessage = "\(ids.count) Dokument(e) geändert"
            } catch {
                bulkResultMessage = error.localizedDescription
            }
            isBulkEditing = false
        }
    }

    /// Eine gefilterte Seite holen, ohne `api` nach außen zu geben.
    ///
    /// Für Erweiterungen in anderen Dateien (etwa das Fristen-Radar), die eine eigene Abfrage
    /// brauchen, aber nicht den ganzen API-Client.
    func fetchPage(query: DocumentQuery, page: Int = 1, pageSize: Int = 250,
                   ordering: String? = nil) async throws -> DocumentPage {
        guard let api else { throw APIError.noData }
        return try await api.fetchDocuments(query: query, page: page, pageSize: pageSize,
                                           ordering: ordering ?? orderingParam())
    }

    /// Ist ein Server erreichbar und angemeldet?
    var hasLiveServer: Bool { api != nil && !isOffline && !isDemoMode }

    // MARK: - Eigene Felder verwalten

    /// Legt ein eigenes Feld an und nimmt es in die geladene Liste auf.
    @discardableResult
    func createCustomField(name: String, type: CustomFieldType,
                           selectOptions: [String] = []) async -> CustomField? {
        guard let api = api, !isDemoMode else { return nil }
        do {
            let field = try await api.createCustomField(
                name: name, dataType: type.rawValue, selectOptions: selectOptions
            )
            allCustomFields.append(field)
            saveToDisk()
            return field
        } catch {
            lastSyncError = error.localizedDescription
            return nil
        }
    }

    func renameCustomField(id: Int, to name: String) async -> Bool {
        guard let api = api, !isDemoMode else { return false }
        do {
            try await api.renameCustomField(id: id, name: name)
            await syncCustomFields()
            return true
        } catch {
            lastSyncError = error.localizedDescription
            return false
        }
    }

    func deleteCustomField(id: Int) async -> Bool {
        guard let api = api, !isDemoMode else { return false }
        do {
            try await api.deleteCustomField(id: id)
            allCustomFields.removeAll { $0.id == id }
            saveToDisk()
            return true
        } catch {
            lastSyncError = error.localizedDescription
            return false
        }
    }

    /// Lädt die Feldliste neu.
    func syncCustomFields() async {
        guard let api = api, !isDemoMode else { return }
        if let fields = try? await api.fetchCustomFields() {
            allCustomFields = fields
            saveToDisk()
        }
    }

    /// Sucht ein Feld nach Namen (unabhängig von Groß-/Kleinschreibung).
    func customField(named name: String) -> CustomField? {
        allCustomFields.first { $0.safeName.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Prüft die Verbindung und beschreibt das Ergebnis in einem Satz (Diagnose-Ansicht).
    func probeConnection() async -> String {
        guard !isDemoMode else { return "Demo-Modus — kein Server." }
        guard let api = api else { return "Kein Konto oder kein Token." }
        let started = Date()
        do {
            let stats = try await api.fetchStatistics()
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            isOffline = false
            let total = stats.documentsTotal.map(String.init) ?? "?"
            return "Erreichbar in \(ms) ms — \(total) Dokumente auf dem Server."
        } catch APIError.unauthorized {
            return "Antwort 401: Token abgelaufen, erneut anmelden."
        } catch APIError.serverError(let code) {
            return "Antwort \(code) vom Server."
        } catch {
            return "Nicht erreichbar: \(error.localizedDescription)"
        }
    }

    /// Vorschläge des Servers holen. Liefert `nil`, wenn der Server keine hat.
    func fetchSuggestions(for docId: Int) async -> DocumentSuggestions? {
        guard let api = api, !isOffline, !isDemoMode else { return nil }
        do {
            let suggestions = try await api.fetchSuggestions(documentId: docId)
            return suggestions.isEmpty ? nil : suggestions
        } catch {
            return nil
        }
    }

    /// Ähnliche Dokumente vom Server. Leeres Ergebnis, wenn der Server das nicht kann.
    func similarDocuments(to docId: Int) async -> [Document] {
        guard let api = api, !isOffline, !isDemoMode else { return [] }
        return (try? await api.fetchSimilarDocuments(to: docId)) ?? []
    }

    // MARK: - Speicherpfade und Berechtigungen

    @Published var allStoragePaths: [StoragePath] = []
    @Published var serverUsers: [ServerUser] = []
    @Published var serverGroups: [ServerGroup] = []

    /// Lädt Speicherpfade, Benutzer und Gruppen.
    ///
    /// Benutzer und Gruppen darf nur ein Administrator sehen; für alle anderen antwortet der
    /// Server mit 403. Das ist kein Fehler, sondern der Normalfall — die Listen bleiben dann
    /// leer und die Oberfläche bietet die Rechtevergabe gar nicht erst an.
    func syncServerMetadata() async {
        guard let api = api, !isDemoMode else { return }
        if let paths = try? await api.fetchStoragePaths() { allStoragePaths = paths }
        if let users = try? await api.fetchUsers() { serverUsers = users }
        if let groups = try? await api.fetchGroups() { serverGroups = groups }
    }

    /// Weist einen Speicherpfad zu.
    func assignStoragePath(_ pathId: Int?, to docIds: Set<Int>) {
        guard let api = api, !docIds.isEmpty, !isDemoMode else { return }
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetStoragePath(ids: Array(docIds), storagePath: pathId)
                bulkResultMessage = "\(docIds.count) Dokument(e) verschoben"
                await reloadVisible()
            } catch {
                bulkResultMessage = error.localizedDescription
            }
            isBulkEditing = false
        }
    }

    /// Setzt Besitzer und Rechte.
    func assignPermissions(owner: Int?, viewUsers: [Int], viewGroups: [Int],
                           changeUsers: [Int], changeGroups: [Int], to docIds: Set<Int>) {
        guard let api = api, !docIds.isEmpty, !isDemoMode else { return }
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetPermissions(
                    ids: Array(docIds), owner: owner,
                    viewUsers: viewUsers, viewGroups: viewGroups,
                    changeUsers: changeUsers, changeGroups: changeGroups
                )
                bulkResultMessage = "Rechte für \(docIds.count) Dokument(e) gesetzt"
            } catch {
                bulkResultMessage = error.localizedDescription
            }
            isBulkEditing = false
        }
    }

    // MARK: - Dublettenprüfung

    /// Ergebnis der Prüfung vor dem Upload.
    struct DuplicateWarning: Identifiable {
        let id = UUID()
        let document: Document
        let reason: String
        let confidence: Double
    }

    var isDuplicateCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: "duplicateCheckEnabled") as? Bool ?? true
    }

    /// Sucht im geladenen Archiv nach einem Dokument mit derselben Signatur.
    ///
    /// Arbeitet auf `documents`, also dem, was ohnehin im Speicher liegt — kein Netzverkehr,
    /// keine Wartezeit vor dem Upload. Was der Zwischenspeicher nicht kennt, fängt der Server
    /// beim Verarbeiten ab (siehe `ConsumptionTask.isDuplicate`).
    func checkForDuplicate(text: String) -> DuplicateWarning? {
        guard isDuplicateCheckEnabled, !text.isEmpty else { return nil }
        let candidate = DuplicateDetector.fingerprint(of: text)
        guard !candidate.isEmpty else { return nil }

        let known: [(documentId: Int, fingerprint: DuplicateDetector.Fingerprint)] = documents
            .compactMap { doc in
                guard let content = doc.content, !content.isEmpty else { return nil }
                return (doc.id, DuplicateDetector.fingerprint(of: content))
            }
        guard let match = DuplicateDetector.matches(for: candidate, in: known).first,
              let doc = documents.first(where: { $0.id == match.documentId }) else { return nil }
        return DuplicateWarning(document: doc, reason: match.reason, confidence: match.confidence)
    }

    // MARK: - Archiv-Seriennummer

    /// Sucht das Dokument zu einer ASN — erst im Zwischenspeicher, dann auf dem Server.
    func findDocument(asn: Int) async -> Document? {
        if let local = documents.first(where: { $0.archiveSerialNumber == asn }) { return local }
        guard let api = api, !isOffline, !isDemoMode else { return nil }
        return try? await api.fetchDocument(asn: asn)
    }

    /// Die nächste freie Archiv-Seriennummer.
    func nextFreeASN() async -> Int? {
        guard let api = api, !isOffline, !isDemoMode else {
            // Ohne Server aus dem Zwischenspeicher schätzen.
            return (documents.compactMap(\.archiveSerialNumber).max() ?? 0) + 1
        }
        guard let highest = try? await api.fetchHighestASN() else { return nil }
        return (highest ?? 0) + 1
    }

    // MARK: - Import-Regeln

    /// Regeln, die das Importformular vorbelegen. Reihenfolge entscheidet.
    ///
    /// Gesichert wird ausdrücklich über `saveUploadRules()` — die Regelliste ändert sich beim
    /// Bearbeiten mehrfach hintereinander, ein `didSet` würde bei jedem Tastendruck schreiben.
    @Published var uploadRules: [UploadRule] = []

    func loadUploadRules() {
        guard let data = UserDefaults.standard.data(forKey: "uploadRules"),
              let rules = try? JSONDecoder().decode([UploadRule].self, from: data) else { return }
        uploadRules = rules
    }

    func saveUploadRules() {
        guard let data = try? JSONEncoder().encode(uploadRules) else { return }
        UserDefaults.standard.set(data, forKey: "uploadRules")
    }

    /// Die Regel, die zu diesem Dateinamen passt.
    func uploadRule(for filename: String) -> UploadRule? {
        uploadRules.firstMatch(filename: filename)
    }

    // MARK: - Bedeutungsindex („Archiv fragen")

    @Published var archiveIndexStatus: String? = nil
    @Published var archiveIndexProgress: Double = 0
    @Published var isBuildingArchiveIndex = false

    /// Nimmt die geladenen Dokumente in den Index auf, soweit sie noch fehlen.
    ///
    /// Läuft nebenbei und leise: Wer nie „Archiv fragen" benutzt, merkt davon nichts.
    func updateArchiveIndexIncrementally() {
        // Derselbe Schalter wie für alle KI-Funktionen: Wer sie abschaltet, will auch keinen
        // Index im Hintergrund.
        guard UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true else { return }
        let payload = documents.compactMap { doc -> (id: Int, text: String)? in
            guard let content = doc.content, !content.isEmpty else { return nil }
            return (doc.id, doc.title + " " + content)
        }
        guard !payload.isEmpty else { return }
        let account = activeAccountId
        Task.detached(priority: .background) {
            await ArchiveIndex.shared.use(account: account)
            await ArchiveIndex.shared.index(payload)
        }
    }

    /// Baut den Index über das **ganze** Archiv auf — seitenweise vom Server.
    func buildFullArchiveIndex() async {
        guard !isBuildingArchiveIndex else { return }
        guard let api = api, !isDemoMode else {
            archiveIndexStatus = "Kein Server verbunden."
            return
        }
        isBuildingArchiveIndex = true
        archiveIndexProgress = 0
        archiveIndexStatus = "Index wird aufgebaut …"

        let account = activeAccountId
        await ArchiveIndex.shared.use(account: account)

        var page = 1
        var processed = 0
        var total: Int? = nil
        while true {
            guard !Task.isCancelled else { break }
            guard let result = try? await api.fetchDocuments(
                page: page, pageSize: 250, ordering: "-added,-id"
            ) else { break }
            if total == nil { total = result.totalCount }

            let payload = result.documents.compactMap { doc -> (id: Int, text: String)? in
                guard let content = doc.content, !content.isEmpty else { return nil }
                return (doc.id, doc.title + " " + content)
            }
            await ArchiveIndex.shared.index(payload)

            processed += result.documents.count
            if let total, total > 0 {
                archiveIndexProgress = min(1, Double(processed) / Double(total))
            }
            archiveIndexStatus = "\(processed) Dokumente verarbeitet …"
            guard result.hasNext else { break }
            page += 1
        }

        let indexed = await ArchiveIndex.shared.count
        archiveIndexStatus = "\(indexed) Dokumente im Index."
        archiveIndexProgress = 1
        isBuildingArchiveIndex = false
    }

    /// Anzahl der indexierten Dokumente — für die Anzeige in den Einstellungen.
    func archiveIndexCount() async -> Int {
        await ArchiveIndex.shared.use(account: activeAccountId)
        return await ArchiveIndex.shared.count
    }

    func clearArchiveIndex() async {
        await ArchiveIndex.shared.use(account: activeAccountId)
        await ArchiveIndex.shared.clear()
        archiveIndexStatus = "Index geleert."
    }

    // MARK: - Posteingang abarbeiten

    /// Nimmt Dokumente aus dem Posteingang, indem alle Inbox-Tags entfernt werden.
    ///
    /// Das ist der Schritt, den paperless-ngx erwartet und den die App vorher nicht anbot:
    /// Wer ein Dokument abarbeiten wollte, musste „Bearbeiten" öffnen und den Inbox-Tag in
    /// der Tag-Liste von Hand abwählen.
    func markAsDone(_ docIds: Set<Int>) {
        let inboxIDs = Array(inboxTagIDs)
        guard !inboxIDs.isEmpty, !docIds.isEmpty else { return }
        haptic(.medium)
        // Sofort aus dem Posteingang nehmen; der Server folgt. Bei einem Fehler landet die
        // Änderung in der Warteschlange und der nächste `loadInbox()` korrigiert die Liste.
        inboxDocuments.removeAll { docIds.contains($0.id) }
        if let total = inboxTotal { inboxTotal = max(0, total - docIds.count) }
        bulkModifyTags(add: [], remove: inboxIDs, in: docIds)
    }

    /// Trägt einen Inbox-Tag wieder ein (Rücknahme von `markAsDone`).
    func markAsUnread(_ docIds: Set<Int>) {
        guard let first = inboxTagIDs.sorted().first, !docIds.isEmpty else { return }
        bulkModifyTags(add: [first], remove: [], in: docIds)
        Task { await loadInbox() }
    }

    // MARK: - Helfer für Sammeländerungen

    /// Dasselbe Dokument kann in drei Listen liegen. Sucht es in allen.
    private func anyLoadedDocument(_ id: Int) -> Document? {
        documents.first { $0.id == id }
            ?? filteredDocs.first { $0.id == id }
            ?? inboxDocuments.first { $0.id == id }
    }

    /// Wendet eine Änderung auf alle Listen an, in denen das Dokument steckt.
    private func mutateLoadedDocuments(ids: Set<Int>, _ change: (inout Document) -> Void) {
        for idx in documents.indices where ids.contains(documents[idx].id) { change(&documents[idx]) }
        for idx in filteredDocs.indices where ids.contains(filteredDocs[idx].id) { change(&filteredDocs[idx]) }
        for idx in inboxDocuments.indices where ids.contains(inboxDocuments[idx].id) { change(&inboxDocuments[idx]) }
        saveToDisk()
    }

    private func applyTagChangeLocally(add: [Int], remove: [Int], in ids: Set<Int>) {
        mutateLoadedDocuments(ids: ids) { doc in
            var tags = Set(doc.tags)
            tags.formUnion(add)
            tags.subtract(remove)
            doc.tags = Array(tags)
        }
        let inboxIDs = inboxTagIDs
        if !inboxIDs.isEmpty {
            inboxDocuments.removeAll { inboxIDs.isDisjoint(with: $0.tags) }
            inboxTotal = inboxDocuments.count
        }
    }

    /// Rückfallebene ohne Server: als Einzeländerungen in die Warteschlange.
    private func queueTagChange(add: [Int], remove: [Int], in docIds: Set<Int>) {
        for id in docIds {
            guard let doc = anyLoadedDocument(id) else { continue }
            var tags = Set(doc.tags)
            tags.formUnion(add)
            tags.subtract(remove)
            addPendingEdit(docId: id, title: doc.title, created: doc.dateObject ?? Date(),
                           corr: doc.correspondent, type: doc.documentType,
                           asn: doc.archiveSerialNumber, tags: Array(tags),
                           customFields: doc.customFields)
        }
    }

    // MARK: - Filter & Sort

    func updateFilteredDocs() {
        // Bei aktiver Suche steht in `filteredDocs` die Antwort des Servers, nicht das
        // Ergebnis der lokalen Filter. Ein Filterlauf würde sie durch die vollständige
        // Liste ersetzen — genau das passierte beim Zurückspringen aus der Detailansicht,
        // weil `MainDocView` in `onAppear` erneut `applyFilters()` und `sync()` aufruft.
        // Der Suchbegriff stand danach noch im Feld, die Treffer waren aber weg und nur
        // Löschen und erneutes Suchen half. Änderungen an einzelnen Dokumenten pflegen
        // `removeDocumentLocally(id:)` und `addPendingEdit(...)` direkt in die Trefferliste ein.
        guard currentSearchText.isEmpty else { return }
        // Filtert der Server, steht in `filteredDocs` seine Antwort. Ein lokaler Filterlauf
        // über `documents` (= nur die geladene Seite) würde sie durch ein Teilergebnis
        // ersetzen.
        guard !isQueryActive else { return }

        // Schnellpfad: Steht kein lokaler Filter an und kommt die Liste vom Server, ist sie
        // bereits in der gewünschten Reihenfolge (`ordering`). Der lokale Sortierlauf wäre
        // reine Arbeit — und er lief bisher bei *jedem* Nachladen erneut über die inzwischen
        // gewachsene Gesamtliste.
        if !activeQuery.hasFilters && hasLiveServer {
            filteredDocs = documents
            return
        }

        let calendar = Calendar.current
        let now = Date()

        let filtered = documents.filter { doc in
            // Der lokale Filter muss dieselben Mengen auswerten wie `activeQuery`, sonst
            // zeigt dasselbe Filterset offline etwas anderes als online.
            let query = activeQuery
            let matchesTag = query.tagIDs.isSubset(of: Set(doc.tags))
            let matchesExcluded = query.excludedTagIDs.isDisjoint(with: Set(doc.tags))
            let matchesCorr = query.correspondentIDs.isEmpty
                || (doc.correspondent.map { query.correspondentIDs.contains($0) } ?? false)
            let matchesType = query.documentTypeIDs.isEmpty
                || (doc.documentType.map { query.documentTypeIDs.contains($0) } ?? false)

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
            return matchesTag && matchesExcluded && matchesCorr && matchesType
                && matchesDate && matchesCustom
        }

        // Seit API-Version 9 liefert paperless-ngx `created` nur noch als Datum ohne Uhrzeit.
        // Damit haben sehr viele Dokumente denselben Sortierwert. `sorted(by:)` ist in Swift
        // nicht stabil, gleichrangige Elemente landen also bei jedem Aufruf in anderer
        // Reihenfolge — SwiftUI verliert dadurch die Zuordnung von Zelle zu Dokument.
        // Die ID als letztes Kriterium macht die Reihenfolge eindeutig.
        func byID(_ a: Document, _ b: Document) -> Bool { a.id > b.id }

        switch currentSortOrder {
        case .dateDesc:
            filteredDocs = filtered.sorted { $0.created == $1.created ? byID($0, $1) : $0.created > $1.created }
        case .dateAsc:
            filteredDocs = filtered.sorted { $0.created == $1.created ? byID($0, $1) : $0.created < $1.created }
        case .titleAZ:
            filteredDocs = filtered.sorted {
                let order = $0.title.localizedCompare($1.title)
                return order == .orderedSame ? byID($0, $1) : order == .orderedAscending
            }
        case .senderAZ:
            // Namen einmal in ein Wörterbuch, statt sie im Vergleich zu suchen: Die lineare
            // Suche im Komparator machte aus dem Sortieren O(n · log n · m).
            let names = Dictionary(allCorrespondents.map { ($0.id, $0.safeName) },
                                   uniquingKeysWith: { a, _ in a })
            filteredDocs = filtered.sorted { doc1, doc2 in
                let n1 = doc1.correspondent.flatMap { names[$0] } ?? ""
                let n2 = doc2.correspondent.flatMap { names[$0] } ?? ""
                let order = n1.localizedCompare(n2)
                return order == .orderedSame ? byID(doc1, doc2) : order == .orderedAscending
            }
        case .addedDesc:
            filteredDocs = filtered.sorted {
                ($0.added ?? "") == ($1.added ?? "") ? byID($0, $1) : ($0.added ?? "") > ($1.added ?? "")
            }
        case .addedAsc:
            filteredDocs = filtered.sorted {
                ($0.added ?? "") == ($1.added ?? "") ? byID($0, $1) : ($0.added ?? "") < ($1.added ?? "")
            }
        }
    }

    // MARK: - Pending Edit Queue

    func addPendingEdit(docId: Int, title: String, created: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int], customFields: [CustomFieldEdit] = []) {
        // `yyyy-MM-dd` in lokaler Zeit statt UTC-Zeitstempel: `ISO8601DateFormatter` schob das
        // Datum östlich von Greenwich um einen Tag zurück (10.08. 00:00 MESZ → 09.08. 22:00 UTC).
        let iso = DateFormatting.apiDate(created)
        func apply(to doc: inout Document) {
            doc.title = title
            doc.created = iso
            doc.correspondent = corr
            doc.documentType = type
            doc.archiveSerialNumber = asn
            doc.tags = tags
            doc.customFields = customFields
        }
        if let idx = documents.firstIndex(where: { $0.id == docId }) {
            apply(to: &documents[idx])
        }
        // Während einer Suche baut `updateFilteredDocs()` die Liste nicht neu auf,
        // die Änderung muss deshalb auch in den Treffern landen.
        if let idx = filteredDocs.firstIndex(where: { $0.id == docId }) {
            apply(to: &filteredDocs[idx])
        }
        // Ein Dokument aus dem Posteingang steht nicht zwingend in `documents` — die Liste
        // dort kommt aus einer eigenen Abfrage.
        if var doc = documents.first(where: { $0.id == docId })
            ?? inboxDocuments.first(where: { $0.id == docId }) {
            apply(to: &doc)
            updateInboxMembership(for: doc)
        }
        let edit = PendingEdit(docId: docId, title: title, created: iso, correspondent: corr, documentType: type, archiveSerialNumber: asn, tags: tags, customFields: customFields)
        pendingEdits.append(edit)
        saveToDisk()
        updateFilteredDocs()
        Task { await processEditQueue() }
    }

    /// Läuft nie zweimal gleichzeitig — siehe `processUploadQueue()`.
    private func processEditQueue() async {
        guard !isDemoMode, !isProcessingEdits else { return }
        isProcessingEdits = true
        defer { isProcessingEdits = false }

        var processed: [UUID] = []
        for edit in pendingEdits {
            guard let api = api else { break }
            do {
                try await api.patchDocument(id: edit.docId, title: edit.title, created: edit.created, correspondent: edit.correspondent, documentType: edit.documentType, archiveSerialNumber: edit.archiveSerialNumber, tags: edit.tags, customFields: edit.customFields)
                processed.append(edit.id)
                showSuccessToast("Änderung gespeichert")
                registerReviewEvent()
            } catch APIError.unauthorized {
                isOffline = true; break
            } catch {
                isOffline = true; break
            }
        }
        pendingEdits.removeAll { processed.contains($0.id) }
        saveToDisk()
        // Der Server kann beim Übernehmen mehr geändert haben als die App lokal eingepflegt
        // hat (Regeln, Workflows). Bei aktivem Filter muss die Trefferliste deshalb neu
        // gestellt werden — sonst steht dort ein Stand von vor der Änderung.
        if !processed.isEmpty { invalidateLoadState() }
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

    /// Arbeitet die Warteschlange ab — garantiert nur einmal gleichzeitig.
    ///
    /// Ohne die Sperre startete der Import zwei Läufe (`addToQueue` und direkt danach `sync()`).
    /// Der erste hält bei `await uploadDocument` an, der zweite sieht dasselbe Element noch in
    /// der Liste — entfernt wird ja erst nach der Schleife — und lädt es ein zweites Mal hoch.
    private func processUploadQueue() async {
        guard !isDemoMode, !isProcessingUploads else { return }
        isProcessingUploads = true
        defer { isProcessingUploads = false }

        var processed: [UUID] = []
        var newTasks: [(String, String)] = []
        for item in pendingUploads {
            guard let api = api else { break }
            do {
                let taskId = try await api.uploadDocument(item)
                processed.append(item.id)
                if let taskId {
                    // Der Server hat die Datei angenommen — verarbeitet ist sie damit noch
                    // nicht. Die Rückmeldung kommt aus `/api/tasks/`.
                    uploadTaskStatuses.insert(
                        UploadTaskStatus(id: taskId, title: item.title, state: .waiting), at: 0
                    )
                    newTasks.append((taskId, item.title))
                } else {
                    showSuccessToast("Fertig: \(item.title)")
                }
                registerReviewEvent()
            } catch { isOffline = true; break }
        }
        pendingUploads.removeAll { processed.contains($0.id) }
        saveToDisk()
        if !processed.isEmpty { await reloadVisible() }
        for (taskId, title) in newTasks {
            Task { await followUp(taskId: taskId, title: title) }
        }
    }

    // MARK: - Verarbeitungsstatus

    /// Läufe, die die App gerade verfolgt. Sichtbar in `PendingQueueView`.
    @Published var uploadTaskStatuses: [UploadTaskStatus] = []

    /// Wie lange auf den Consumer gewartet wird, bevor die App den Auftrag nur noch als
    /// „wird verarbeitet" führt.
    private static let taskPollAttempts = 20
    private static let taskPollInterval: UInt64 = 3_000_000_000

    /// Verfolgt einen Verarbeitungsauftrag und meldet das Ergebnis.
    func followUp(taskId: String, title: String) async {
        guard let api = api else { return }
        for attempt in 1...Self.taskPollAttempts {
            // Erst warten: unmittelbar nach dem Upload steht der Auftrag noch auf PENDING.
            try? await Task.sleep(nanoseconds: Self.taskPollInterval)
            guard !Task.isCancelled else { return }

            let task: ConsumptionTask?
            do {
                task = try await api.fetchTask(taskId: taskId)
            } catch {
                // Endpunkt nicht erreichbar oder nicht erlaubt: Status aufgeben, aber den
                // Upload nicht als Fehler darstellen — angenommen wurde er ja.
                updateTask(taskId) { $0.state = .unknown; $0.message = nil }
                return
            }
            guard let task else {
                if attempt == Self.taskPollAttempts {
                    updateTask(taskId) { $0.state = .unknown }
                }
                continue
            }

            if task.isFinished {
                finish(task: task, taskId: taskId, title: title)
                return
            }
            updateTask(taskId) { $0.state = .running; $0.message = task.displayMessage }
        }
        // Zeit abgelaufen, ohne Ergebnis.
        updateTask(taskId) { $0.state = .running }
    }

    private func finish(task: ConsumptionTask, taskId: String, title: String) {
        if task.didFail {
            let duplicate = task.isDuplicate
            updateTask(taskId) {
                $0.state = duplicate ? .duplicate : .failed
                $0.message = task.displayMessage
            }
            // Ein stiller Fehlschlag ist das schlechteste Ergebnis: Der Nutzer glaubt, das
            // Dokument sei im Archiv.
            // Anführungszeichen als eigene Zeichen, nicht im Literal: ein gerades " würde
            // den String beenden.
            let label = "\u{201E}" + title + "\u{201C}"
            importErrorMessage = duplicate
                ? "\(label) wurde nicht übernommen: \(task.displayMessage)"
                : "\(label) konnte nicht verarbeitet werden: \(task.displayMessage)"
            haptic(.heavy)
        } else {
            updateTask(taskId) {
                $0.state = .succeeded
                $0.message = nil
                $0.documentId = task.relatedDocument
            }
            showSuccessToast("Verarbeitet: \(title)")
            Task { await reloadVisible() }
            // Erledigte Einträge nach kurzer Zeit aus der Liste nehmen.
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                uploadTaskStatuses.removeAll { $0.id == taskId && $0.state == .succeeded }
            }
        }
    }

    private func updateTask(_ taskId: String, _ change: (inout UploadTaskStatus) -> Void) {
        guard let idx = uploadTaskStatuses.firstIndex(where: { $0.id == taskId }) else { return }
        change(&uploadTaskStatuses[idx])
    }

    /// Räumt beendete Statusmeldungen weg (Knopf in `PendingQueueView`).
    func clearFinishedTaskStatuses() {
        uploadTaskStatuses.removeAll { $0.isFinished }
    }

    func removePendingUpload(at offsets: IndexSet) { pendingUploads.remove(atOffsets: offsets); saveToDisk() }

    /// Von positiven Momenten aufgerufen. Prüft die Gating-Regeln und setzt bei
    /// Eignung das Flag, das RootTabView in den requestReview-Aufruf übersetzt.
    /// `recordPrompt()` passiert bewusst erst dort, direkt vor `requestReview()` –
    /// so verbrennen wir keinen Versuch, falls das Flag nie konsumiert wird.
    func registerReviewEvent() {
        ReviewRequestService.shared.registerPositiveEvent()
        guard ReviewRequestService.shared.shouldRequestReview() else { return }
        shouldRequestReview = true
    }

    // MARK: - Delete Document

    func deleteDocument(id: Int) {
        Task {
            guard let api = api, let accountId = activeAccountId else { return }
            do {
                try await api.deleteDocument(id: id)
            } catch {
                // Ohne diese Prüfung verschwand das Dokument auch dann aus der Liste, wenn der
                // Server es gar nicht gelöscht hat (offline, fehlende Rechte) — und tauchte
                // beim nächsten Sync wieder auf.
                lastSyncError = error.localizedDescription
                return
            }
            removeDocumentLocally(id: id)
            saveToDisk()
            PersistenceService.deleteDocFile(docId: id, accountId: accountId)
        }
    }

    /// Nimmt ein Dokument aus beiden Listen. `filteredDocs` muss ausdrücklich mit, weil
    /// `updateFilteredDocs()` bei aktiver Suche nichts neu aufbaut.
    func removeDocumentLocally(id: Int) {
        documents.removeAll { $0.id == id }
        filteredDocs.removeAll { $0.id == id }
        if inboxDocuments.contains(where: { $0.id == id }) {
            inboxDocuments.removeAll { $0.id == id }
            if let total = inboxTotal { inboxTotal = max(0, total - 1) }
        }
        updateFilteredDocs()
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
        if isDemoMode { return demoStatistics ?? DemoDataService.makeContent().statistics }
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
            try? PersistenceService.writeFile(data, to: localFileURL(for: docId))
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
                        try? PersistenceService.writeFile(data, to: localFileURL(for: doc.id))
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

    /// Spotlight-Bereich eines Kontos.
    ///
    /// Dokument-IDs sind nur innerhalb eines Servers eindeutig. Lagen alle Konten in einem
    /// Bereich, überschrieb Dokument 42 von Server B den Eintrag von Dokument 42 aus Server A —
    /// und nach einem Kontowechsel standen fremde Dokumenttitel in der Systemsuche.
    nonisolated static func spotlightDomain(for accountId: UUID) -> String {
        "com.paperless24.docs.\(accountId.uuidString)"
    }

    /// Alter, kontoloser Bereich. Einträge daraus stammen aus früheren Programmversionen
    /// und werden beim ersten Indexlauf entsorgt.
    private static let legacySpotlightDomain = "com.paperless24.docs"

    nonisolated static func spotlightIdentifier(account: UUID, docId: Int) -> String {
        "\(account.uuidString)/\(docId)"
    }

    /// Zerlegt einen Spotlight-Bezeichner wieder in Konto und Dokument.
    nonisolated static func parseSpotlightIdentifier(_ raw: String) -> (account: UUID, docId: Int)? {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let account = UUID(uuidString: String(parts[0])),
              let docId = Int(parts[1]) else { return nil }
        return (account, docId)
    }

    /// Ausgang eines Indexlaufs — die Einstellungen zeigen ihn an.
    struct SpotlightIndexResult: Equatable {
        var indexed = 0
        var rejected = 0
        var errorMessage: String?
    }

    /// Obergrenze für den Index. Ein Archiv kann größer sein; irgendwo muss Schluss sein,
    /// sonst blättert die App minutenlang durch den Server.
    private static let spotlightDocumentLimit = 10_000

    /// Seitengröße beim Blättern für den Index — unabhängig von der Listenansicht.
    private static let spotlightFetchPageSize = 250

    /// Wie viele fehlende Vorschaubilder ein voller Indexlauf höchstens nachlädt.
    private static let spotlightThumbnailDownloads = 400

    /// Gleichzeitige Vorschaubild-Anfragen. Sechs lasten eine typische ngx-Instanz aus,
    /// ohne sie zu überfahren.
    private static let spotlightThumbnailConcurrency = 6

    /// Ob für dieses Konto schon einmal das ganze Archiv indiziert wurde.
    private var fullSpotlightIndexBuilt: Bool {
        get {
            guard let id = activeAccountId else { return true }
            return UserDefaults.standard.bool(forKey: "spotlight_full_\(id.uuidString)")
        }
        set {
            guard let id = activeAccountId else { return }
            UserDefaults.standard.set(newValue, forKey: "spotlight_full_\(id.uuidString)")
        }
    }

    /// Baut den Index im Hintergrund auf. Ohne Rückmeldung, für den Sync.
    ///
    /// Beim ersten Lauf eines Kontos wird das ganze Archiv geholt, danach reicht, was
    /// ohnehin geladen ist — sonst blätterte jeder Sync durch den kompletten Server.
    /// Neue Dokumente stehen durch die Sortierung nach Datum immer auf der ersten Seite.
    /// Zeitpunkt des letzten Spotlight-Durchlaufs.
    private var lastSpotlightRun: Date? = nil
    /// Mindestabstand zwischen zwei Durchläufen.
    ///
    /// Der Index lief bisher bei jedem `loadFirstPage()` an — also auch bei jedem stillen Sync.
    /// Ein voller Durchlauf blättert durch das ganze Archiv und lädt Vorschaubilder nach; das
    /// gehört nicht in den Weg des Nutzers.
    private static let spotlightMinInterval: TimeInterval = 15 * 60

    /// Indexiert, wenn der erste Aufbau noch fehlt oder der letzte Lauf lange her ist.
    func indexDocumentsForSpotlightIfDue() {
        if !fullSpotlightIndexBuilt {
            lastSpotlightRun = Date()
            indexDocumentsForSpotlight()
            return
        }
        if let last = lastSpotlightRun,
           Date().timeIntervalSince(last) < Self.spotlightMinInterval { return }
        lastSpotlightRun = Date()
        indexDocumentsForSpotlight()
    }

    func indexDocumentsForSpotlight() {
        let full = !fullSpotlightIndexBuilt
        Task {
            let result = await performSpotlightIndexing(fullArchive: full)
            if full && result.errorMessage == nil && result.indexed > 0 {
                fullSpotlightIndexBuilt = true
            }
        }
    }

    /// Leert den Index und baut ihn aus dem ganzen Archiv neu auf. Meldet zurück, was
    /// hängengeblieben ist.
    ///
    /// Das Löschen wird abgewartet: es läuft asynchron im Indexdienst und würde sonst
    /// die frisch geschriebenen Einträge wieder mitnehmen.
    func rebuildSpotlightIndex() async -> SpotlightIndexResult {
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteAllSearchableItems { _ in continuation.resume() }
        }
        let result = await performSpotlightIndexing(fullArchive: true)
        if result.errorMessage == nil && result.indexed > 0 { fullSpotlightIndexBuilt = true }
        return result
    }

    /// Holt für den Index das ganze Archiv vom Server. Ohne Server (Demo-Modus, offline)
    /// bleibt es bei dem, was geladen ist.
    private func documentsForIndexing(fullArchive: Bool) async -> [Document] {
        let loaded = Array(documents.prefix(Self.spotlightDocumentLimit))
        guard fullArchive, let api = api else { return loaded }

        var collected: [Document] = []
        var page = 1
        while collected.count < Self.spotlightDocumentLimit {
            guard let result = try? await api.fetchDocuments(
                page: page, pageSize: Self.spotlightFetchPageSize) else { break }
            collected.append(contentsOf: result.documents)
            guard result.hasNext else { break }
            page += 1
        }
        // Bricht das Blättern früh ab, ist die Ausbeute schlechter als das, was ohnehin
        // im Speicher liegt — dann lieber das nehmen.
        guard collected.count > loaded.count else { return loaded }
        return Array(collected.uniquedByID().prefix(Self.spotlightDocumentLimit))
    }

    private func performSpotlightIndexing(fullArchive: Bool) async -> SpotlightIndexResult {
        guard let accountId = activeAccountId else { return SpotlightIndexResult() }
        let domain = Self.spotlightDomain(for: accountId)
        let docs = await documentsForIndexing(fullArchive: fullArchive)
        let tags = allTags
        let corrs = allCorrespondents
        let types = allDocTypes

        // Reste aus der Zeit ohne Kontotrennung räumen.
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [Self.legacySpotlightDomain]) { _ in }

        // Vorschaubilder nur beim vollen Lauf nachladen — und nur bis zu dieser Grenze,
        // sonst zieht ein Neuaufbau das halbe Archiv über die Leitung.
        var downloadBudget = fullArchive ? Self.spotlightThumbnailDownloads : 0
        var missingThumbnails = 0

        // Blockweise bauen statt alles auf einmal: die Vorschaubilder hängen als Daten an
        // den Einträgen, und 10.000 davon gleichzeitig im Speicher will niemand.
        var result = SpotlightIndexResult()
        for chunk in docs.chunked(into: 100) {
            var thumbnails: [Int: Data] = [:]
            var pending: [Int] = []
            for doc in chunk {
                if let data = ImageCache.shared.thumbnailData(for: doc.id) {
                    thumbnails[doc.id] = data
                } else {
                    pending.append(doc.id)
                }
            }

            if downloadBudget > 0, let api = api, !pending.isEmpty {
                let batch = Array(pending.prefix(downloadBudget))
                downloadBudget -= batch.count
                missingThumbnails += pending.count - batch.count

                // Nacheinander dauerte ein Neuaufbau eine halbe Stunde — die Zeit steckt
                // fast vollständig im Warten auf den Server, nicht in Rechenarbeit.
                let fetched = await withTaskGroup(of: (Int, Data?).self) { group -> [Int: Data] in
                    var remaining = batch.makeIterator()
                    for _ in 0..<Self.spotlightThumbnailConcurrency {
                        guard let id = remaining.next() else { break }
                        group.addTask { (id, try? await api.fetchThumbnail(for: id)) }
                    }
                    var loaded: [Int: Data] = [:]
                    while let (id, data) = await group.next() {
                        if let data { loaded[id] = data }
                        if let next = remaining.next() {
                            group.addTask { (next, try? await api.fetchThumbnail(for: next)) }
                        }
                    }
                    return loaded
                }

                for (id, data) in fetched {
                    // Gleich in den Cache legen: die Liste zeigt sie ohnehin als Nächstes.
                    if let image = UIImage(data: data) { ImageCache.shared.saveImage(image, for: id) }
                    thumbnails[id] = data
                }
                missingThumbnails += batch.count - fetched.count
            } else {
                missingThumbnails += pending.count
            }

            let items = await Task.detached(priority: .background) { () -> [CSSearchableItem] in
                chunk.map { doc in
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

                    // Die Bytes direkt statt eines Dateipfads: einen Pfad müsste der
                    // Indexdienst selbst öffnen, was je nach Dateischutz und Zeitpunkt
                    // scheitert. Ohne Bild zeigt Spotlight nur das App-Symbol.
                    attrs.thumbnailData = thumbnails[doc.id]

                    let item = CSSearchableItem(
                        uniqueIdentifier: Self.spotlightIdentifier(account: accountId, docId: doc.id),
                        domainIdentifier: domain,
                        attributeSet: attrs)
                    item.expirationDate = .distantFuture
                    return item
                }
            }.value

            // Blockweise indizieren: `indexSearchableItems` ist pro Aufruf alles-oder-nichts.
            // Ein einziges Dokument, das dem Index nicht schmeckt, riss bisher den kompletten
            // Stapel mit — und Spotlight blieb leer.
            let error: Error? = await withCheckedContinuation { continuation in
                CSSearchableIndex.default().indexSearchableItems(items) { continuation.resume(returning: $0) }
            }
            if let error {
                Self.logger.error("Spotlight-Index fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                result.rejected += items.count
                // Erste Fehlermeldung behalten: die weiteren sind erfahrungsgemäß dieselbe.
                if result.errorMessage == nil { result.errorMessage = error.localizedDescription }
            } else {
                result.indexed += items.count
            }
        }

        if missingThumbnails > 0 {
            Self.logger.info("Spotlight: \(missingThumbnails, privacy: .public) Einträge ohne Vorschaubild")
        }
        return result
    }

    func clearSpotlightIndex() { CSSearchableIndex.default().deleteAllSearchableItems { _ in } }

    /// Entfernt die Einträge eines einzelnen Kontos aus Spotlight.
    func clearSpotlightIndex(for accountId: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [Self.spotlightDomain(for: accountId)]) { _ in }
    }

    // MARK: - Persistence

    /// Fingerabdruck des Archivs beim letzten Schreibvorgang.
    private var lastSavedArchiveSignature: Int? = nil

    /// Speichert den Stand des aktiven Kontos.
    ///
    /// Getrennt nach Dringlichkeit und Größe:
    /// * **Warteschlangen** (Uploads, Änderungen, Filter) sind klein, und ein Verlust wäre hier
    ///   am schmerzhaftesten — sie werden sofort geschrieben.
    /// * **Archiv** (Dokumente und Stammdaten) ist groß: `documents` enthält den erkannten Text
    ///   jedes Dokuments, bei einem vollen Archiv zweistellige Megabyte. Das lief bisher bei
    ///   *jedem* Sync durch `JSONEncoder` auf dem Main Thread — genau das machte das Laden
    ///   ruckelig. Jetzt kodiert ein Hintergrund-Task, und unveränderte Daten werden gar nicht
    ///   erst geschrieben.
    func saveToDisk() {
        saveQueues()
        saveArchive()
    }

    private func saveQueues() {
        guard let id = activeAccountId else { return }
        PersistenceService.save(pendingUploads, toURL: PersistenceService.accountDataURL(for: id, filename: "pending.json"))
        PersistenceService.save(pendingEdits,   toURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))
        PersistenceService.save(savedFilters,   toURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json"))
    }

    /// Schreibt Dokumente und Stammdaten, wenn sich etwas geändert hat.
    func saveArchive(force: Bool = false) {
        guard let id = activeAccountId else { return }
        let signature = archiveSignature()
        guard force || signature != lastSavedArchiveSignature else { return }
        lastSavedArchiveSignature = signature

        // Arrays sind Wertetypen — der Hintergrund-Task arbeitet auf einer eigenen Kopie und
        // kann nichts sehen, was sich danach noch ändert.
        let docs = documents
        let tags = allTags
        let corrs = allCorrespondents
        let types = allDocTypes
        let fields = allCustomFields
        Task.detached(priority: .utility) {
            PersistenceService.save(docs,   toURL: PersistenceService.accountDataURL(for: id, filename: "documents.json"))
            PersistenceService.save(tags,   toURL: PersistenceService.accountDataURL(for: id, filename: "tags.json"))
            PersistenceService.save(corrs,  toURL: PersistenceService.accountDataURL(for: id, filename: "corrs.json"))
            PersistenceService.save(types,  toURL: PersistenceService.accountDataURL(for: id, filename: "types.json"))
            PersistenceService.save(fields, toURL: PersistenceService.accountDataURL(for: id, filename: "customfields.json"))
        }
    }

    /// Billiger Vergleichswert: erkennt Änderungen an Bestand und Metadaten, ohne den ganzen
    /// erkannten Text zu hashen.
    private func archiveSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(documents.count)
        for doc in documents {
            hasher.combine(doc.id)
            hasher.combine(doc.title)
            hasher.combine(doc.created)
            hasher.combine(doc.tags)
            hasher.combine(doc.correspondent)
            hasher.combine(doc.documentType)
            hasher.combine(doc.archiveSerialNumber)
            hasher.combine(doc.customFields)
        }
        hasher.combine(allTags.count)
        hasher.combine(allCorrespondents.count)
        hasher.combine(allDocTypes.count)
        hasher.combine(allCustomFields.count)
        return hasher.finalize()
    }

    func loadFromDisk(for id: UUID) {
        apply(AccountDiskSnapshot(accountId: id))
    }

    /// Wie `loadFromDisk`, aber das Dekodieren läuft abseits des Main Threads. Beim Start und
    /// beim Kontowechsel hängen sonst mehrere hundert Millisekunden JSON-Arbeit am ersten Frame.
    private func loadFromDiskAsync(for id: UUID) async {
        let snapshot = await Task.detached(priority: .userInitiated) {
            AccountDiskSnapshot(accountId: id)
        }.value
        // Zwischenzeitlicher Kontowechsel: der Stand gehört nicht mehr zum aktiven Konto.
        guard activeAccountId == id else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: AccountDiskSnapshot) {
        documents         = snapshot.documents
        allTags           = snapshot.tags
        allCorrespondents = snapshot.correspondents
        allDocTypes       = snapshot.docTypes
        allCustomFields   = snapshot.customFields
        pendingUploads    = snapshot.pendingUploads
        pendingEdits      = snapshot.pendingEdits
        savedFilters      = snapshot.savedFilters
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
            await reloadVisible()
            showSuccessToast("Wiederhergestellt")
            registerReviewEvent()
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
                registerReviewEvent()
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
        guard let link = try? await api.createShareLink(documentId: documentId, expiration: expiration, fileVersion: fileVersion) else { return nil }
        registerReviewEvent()
        return link
    }

    func deleteShareLink(id: Int) async {
        guard let api = api else { return }
        try? await api.deleteShareLink(id: id)
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
                guard !Task.isCancelled else { return }
                // Im Hintergrund nichts anstoßen: iOS friert die Anfragen ohnehin ein, und
                // die Warteschlange wird beim nächsten Vordergrund-Sync abgearbeitet.
                guard UIApplication.shared.applicationState == .active else { continue }
                if !pendingUploads.isEmpty || !pendingEdits.isEmpty { sync(silent: true) }
            }
        }
    }

    // MARK: - Clear

    func clearLocalData() {
        for account in accounts {
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        }
        invalidateTokenCache()
        accounts = []
        activeAccountId = nil
        ImageCache.shared.setAccount(nil)
        AccountService.save([])
        AccountService.setActiveId(nil)
        isDemoMode = false
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []
        pendingUploads = []; pendingEdits = []; cachedCount = 0; storageSize = "0 MB"; lastSyncError = nil
        PersistenceService.clearAll()
        ImageCache.shared.clearAll()
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
        invalidateTokenCache()
        // Muss vor `materialize` stehen: die Demo-Miniaturansichten landen sonst im Ablageort
        // des vorherigen Kontos.
        ImageCache.shared.setAccount(demoAccount.id)

        let content = DemoDataService.makeContent()
        allTags = content.tags
        allCorrespondents = content.correspondents
        allDocTypes = content.docTypes
        allCustomFields = content.customFields
        documents = content.documents
        demoStatistics = content.statistics
        inboxDocuments = cachedInboxDocs
        inboxTotal = inboxDocuments.count

        // PDFs und Miniaturen liegen lokal, damit Liste und Detailansicht ohne Server
        // echte Seiten zeigen. Läuft im Hintergrund, die Liste steht sofort.
        let accountId = demoAccount.id
        Task.detached(priority: .userInitiated) {
            DemoDataService.materialize(accountId: accountId)
            await MainActor.run { self.calculateStorage() }
        }

        updateFilteredDocs()
        saveToDisk()
        updateWidget(stats: content.statistics)
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

        let theme = ThemeSettings(
            theme: AppTheme(rawValue: UserDefaults.standard.string(forKey: "themeId") ?? "") ?? .indigo,
            customAccentHex: UserDefaults.standard.string(forKey: "customAccentHex") ?? "3F51B5",
            amoled: UserDefaults.standard.bool(forKey: "amoledEnabled")
        )
        WidgetDataService.writeTheme(
            accentLightHex: theme.accentHex(isDark: false),
            accentDarkHex: theme.accentHex(isDark: true)
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
