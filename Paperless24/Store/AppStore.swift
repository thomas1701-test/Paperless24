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
        let epoch = accountEpoch
        do {
            let page = try await api.fetchDocuments(tagIDs: Array(ids), page: 1)
            guard isCurrent(epoch) else { return }
            inboxDocuments = page.documents.uniquedByID()
            inboxTotal = page.totalCount ?? inboxDocuments.count
        } catch {
            guard isCurrent(epoch) else { return }
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
        for edit in pendingEdits where edit.failureReason == nil {
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
    /// Sortierung, in der `lastAppliedQuery` beantwortet wurde. Die Sortierung gehört nicht
    /// zur Anfrage — ohne diesen Wert galt ein Sortierwechsel als „gleiche Anfrage" und die
    /// Trefferliste blieb, wie sie war.
    private var lastAppliedQueryOrder: SortOrder? = nil
    /// Sortierung, in der `documents` vom Server kam; `nil`, solange die Liste nur von der
    /// Platte stammt. Weicht sie von `currentSortOrder` ab, muss neu geladen werden: Mit 25
    /// geladenen Dokumenten sind die neuesten 25 nach „Hinzugefügt" andere als die 25
    /// neuesten nach Belegdatum.
    private var listSortOrder: SortOrder? = nil

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
    /// Je Konto: Ein noch laufender Durchlauf des vorherigen Kontos hält den neuen nicht auf.
    private var uploadQueueEpoch: Int? = nil
    private var editQueueEpoch: Int? = nil
    /// Einträge, die gerade übertragen werden — über Epochen hinweg. Wechselt man mitten in einem
    /// Upload weg und gleich wieder zurück, liefe sonst ein zweiter Durchlauf desselben Kontos an
    /// und schickte dieselbe Datei noch einmal.
    private var queueItemsInFlight = Set<UUID>()

    /// Das Laden des Plattenstands für das aktive Konto — `sync()` wartet darauf.
    private var diskLoadTask: Task<Void, Never>? = nil
    /// Für welches Konto der Plattenstand übernommen ist. `nil`, solange er noch lädt.
    ///
    /// Vorher schrieb `saveToDisk()` auch dann, wenn die Warteschlangen noch gar nicht gelesen
    /// waren: Beim Start sah `MainDocView` eine leere Liste, stieß `sync()` an, und die leeren
    /// Arrays überschrieben `pending.json` und `edits.json`, bevor der Snapshot sie las.
    /// Offline gespeicherte Scans und Änderungen waren danach weg.
    private var diskStateAccountId: UUID? = nil

    // MARK: - Kontowechsel

    /// Zählt jeden Wechsel des aktiven Kontos: Wechsel, Entfernen, Abmelden, Demo.
    ///
    /// Jeder Weg, der nach einem `await` Zustand schreibt, merkt sich die Epoche vorher und
    /// prüft sie danach (`isCurrent`). Vorher liefen Sync, Suche, Spotlight und die
    /// Warteschlangen nach einem Kontowechsel einfach weiter: Antworten von Konto A landeten in
    /// Liste, Plattencache und Spotlight von Konto B, und die Warteschlangen schickten Dateien
    /// und Änderungen von A an den Server von B — dort trafen sie Dokumente mit derselben ID.
    private var accountEpoch = 0

    private func isCurrent(_ epoch: Int) -> Bool { epoch == accountEpoch }

    /// Spotlight-Lauf des aktiven Kontos — beim Wechsel abgebrochen.
    ///
    /// Der Sync wird bewusst *nicht* abgebrochen: Er enthält die Warteschlangen, und ein
    /// gekappter Upload kann beim Server längst angekommen sein. Die Datei bliebe dann in der
    /// Warteschlange und ginge später ein zweites Mal hinaus. Stattdessen läuft der alte Lauf
    /// gegen seinen eigenen Server zu Ende, und `isCurrent` hält seine Ergebnisse vom neuen
    /// Konto fern.
    private var spotlightTask: Task<Void, Never>? = nil

    /// Beendet alles, was zum bisherigen Konto gehört, und leert dessen flüchtigen Zustand.
    /// Muss vor dem Umschalten von `activeAccountId` laufen.
    private func beginNewAccountEpoch() {
        accountEpoch += 1
        searchTask?.cancel(); searchTask = nil
        autoSyncTask?.cancel(); autoSyncTask = nil
        downloadTask?.cancel(); downloadTask = nil
        spotlightTask?.cancel(); spotlightTask = nil
        runningSyncEpoch = nil
        uploadQueueEpoch = nil
        editQueueEpoch = nil

        isSyncing = false; isSearching = false; isLoadingMore = false; isLoadingInbox = false
        isBulkEditing = false; isDownloadingAll = false; isBuildingArchiveIndex = false
        uploadProgress = nil; uploadTaskStatuses = []
        isOffline = false; lastSyncError = nil
        inboxDocuments = []; inboxTotal = nil
        recentSearches = []; queryTotalCount = nil; hasNextPage = false
        allStoragePaths = []; serverUsers = []; serverGroups = []
        lastAppliedQuery = nil; lastSuccessfulSync = nil
        lastAppliedQueryOrder = nil; listSortOrder = nil
        lastSpotlightRun = nil; spotlightFullRunScheduled = false
        archiveIndexStatus = nil; archiveIndexProgress = 0
        lastSavedArchiveSignature = nil
    }

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
            diskLoadTask = Task { await loadFromDiskAsync(for: id) }
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
        beginNewAccountEpoch()
        activeAccountId = id
        AccountService.setActiveId(id)
        // Token und Miniaturansichten gehören zum Konto — beides muss mitwechseln, sonst
        // zeigt die Liste die Vorschauen des vorherigen Kontos.
        invalidateTokenCache()
        ImageCache.shared.setAccount(id)
        loadUploadRules()
        // Die Systemsuche zeigt nur das aktive Konto. Sonst stünden die Dokumenttitel eines
        // Archivs weiter in Spotlight, während ein anderes Konto geöffnet ist.
        clearSpotlightIndex()
        WidgetDataService.clearContent()
        WidgetCenter.shared.reloadAllTimelines()
        // Vor dem Leeren: Bis der Stand des neuen Kontos gelesen ist, darf nichts geschrieben
        // werden — die leeren Arrays landeten sonst in dessen Dateien.
        diskStateAccountId = nil
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []
        pendingUploads = []; pendingEdits = []; savedFilters = []
        currentSearchText = ""; currentPage = 1; currentSearchPage = 1
        diskLoadTask = nil
        if hasValidToken() {
            diskLoadTask = Task { await loadFromDiskAsync(for: id) }
            calculateStorage()
            startAutoSync()
        }
    }

    func removeAccount(id: UUID) {
        guard accounts.count > 1 else { return }
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        // Laufende Arbeit zuerst beenden: Sie legte sonst den eben gelöschten Kontoordner
        // wieder an.
        if activeAccountId == id { beginNewAccountEpoch() }
        KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        UserDefaults.standard.removeObject(forKey: uploadRulesKey(id))
        // Kopfzeilen und Zertifikat hängen am Server, nicht am Benutzer — nur entfernen, wenn
        // kein anderes Konto denselben Server nutzt.
        let server = PaperlessAPI.normalizedBase(account.serverUrl)
        if !accounts.contains(where: { $0.id != id && PaperlessAPI.normalizedBase($0.serverUrl) == server }) {
            ServerCredentials.removeAll(for: server)
        }
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
                beginNewAccountEpoch()
                activeAccountId = nil
                AccountService.setActiveId(nil)
                ImageCache.shared.setAccount(nil)
                diskStateAccountId = nil
                diskLoadTask = nil
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

    /// Epoche des laufenden Syncs. Verhindert, dass sich zwei Läufe desselben Kontos
    /// überlagern — ein abgebrochener Lauf des vorherigen Kontos blockiert den neuen nicht.
    private var runningSyncEpoch: Int? = nil

    func sync(silent: Bool = false) {
        guard !isDemoMode, !serverUrl.isEmpty else { return }
        let epoch = accountEpoch
        guard runningSyncEpoch != epoch else { return }
        if !silent { isSyncing = true }
        runningSyncEpoch = epoch
        Task {
            // Erst den Plattenstand abwarten: Sonst sieht der Lauf eine leere Warteschlange,
            // lädt nichts hoch und schreibt den leeren Stand zurück.
            await diskLoadTask?.value
            if isCurrent(epoch) {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.loadFirstPage(silent: silent) }
                    group.addTask { await self.syncMetadata() }
                    if !self.pendingUploads.isEmpty { group.addTask { await self.processUploadQueue() } }
                    await self.processEditQueue()
                }
            }
            guard isCurrent(epoch) else { return }
            runningSyncEpoch = nil
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
        let epoch = accountEpoch
        // Speicherpfade gehören zu den Stammdaten; Benutzer und Gruppen werden erst dann
        // geholt, wenn jemand die Rechte tatsächlich öffnet (dafür braucht es Adminrechte).
        //
        // Mit in den parallelen Block: Davor stand das als eigenes `await` und verzögerte
        // jeden Sync um eine volle Runde zum Server — beim Start am deutlichsten.
        async let paths = try? api.fetchStoragePaths()
        async let tags = try? api.fetchTags()
        async let corrs = try? api.fetchCorrespondents()
        async let types = try? api.fetchDocumentTypes()
        async let fields = try? api.fetchCustomFields()
        async let views = try? api.fetchSavedViews()
        async let stats = try? api.fetchStatistics()

        // Erst alles abwarten, dann in einem Zug übernehmen — und nur, wenn das Konto noch
        // dasselbe ist.
        let (p, t, c, tp, f, v, resolvedStats) = await (paths, tags, corrs, types, fields, views, stats)
        guard isCurrent(epoch) else { return }
        if let p { allStoragePaths = p }
        if let t { allTags = t }
        if let c { allCorrespondents = c }
        if let tp { allDocTypes = tp }
        if let f { allCustomFields = f }
        if let v {
            serverViews = v
            migrateLocalFiltersToServer()
        }
        saveToDisk()

        if let inbox = resolvedStats?.documentsInbox {
            inboxTotal = inbox
            // Was die App gerade gesehen hat, muss der Hintergrundlauf nicht mehr melden — und
            // nach dem Abarbeiten meldet er neue Dokumente wieder. Vorher blieb der Wert auf dem
            // Höchststand stehen: Nach 5 gemeldeten und abgearbeiteten kam bei 3 neuen nichts.
            UserDefaults.standard.set(inbox, forKey: BackgroundData.lastInboxKey)
        }
        updateWidget(stats: resolvedStats)
        await loadInbox()
    }

    // MARK: - Pagination

    func loadFirstPage(silent: Bool = false) async {
        // Im Demo-Modus gibt es keinen Server und damit keinen Token. Das ist kein
        // abgelaufener Login — wer hier zum Aktualisieren zog, landete auf dem
        // Anmeldebildschirm.
        guard !isDemoMode else {
            updateFilteredDocs()
            isSyncing = false
            return
        }
        // Ohne Konto ist auch nichts abgelaufen; dann ist schlicht noch nichts eingerichtet.
        guard activeAccount != nil, !serverUrl.isEmpty else {
            isSyncing = false
            return
        }
        guard let api = api, let account = activeAccount else {
            isSyncing = false
            needsReLogin = true
            return
        }
        let epoch = accountEpoch
        // Ein stiller Sync darf die Anzeige nicht anfassen: Die Fortschrittsanzeige beim
        // Zurückkehren aus der Detailansicht war der Hauptgrund, warum das Laden ruckelig
        // wirkte — sie erschien und verschwand bei jedem Wechsel.
        if !silent { isSyncing = true }
        let order = currentSortOrder
        for attempt in 1...2 {
            do {
                let page = try await api.fetchDocuments(page: 1, ordering: orderingParam(order))
                guard isCurrent(epoch) else { return }
                // Inzwischen umsortiert: Diese Antwort hat die alte Reihenfolge, die Anfrage in
                // der neuen läuft schon (`reloadIfSortOrderChanged`).
                guard order == currentSortOrder else {
                    if !silent { isSyncing = false }
                    return
                }
                // Hat der Nutzer schon nachgeladen, darf ein stiller Sync die Liste nicht auf
                // die erste Seite zurückschneiden — sie würde unter dem Finger zusammenklappen
                // und die Scrollposition verlieren. Dann wird die erste Seite eingepflegt und
                // der Blätterstand bleibt, wie er ist. Nur bei gleicher Sortierung: Sonst
                // passt die erste Seite nicht vor den Rest.
                if silent && documents.count > page.documents.count && listSortOrder == order {
                    mergeFirstPage(page.documents)
                } else {
                    documents = page.documents.uniquedByID()
                    hasNextPage = page.hasNext
                    currentPage = 1
                }
                listSortOrder = order
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
                // Den Token des Kontos löschen, dessen Anfrage abgelehnt wurde — nicht den des
                // inzwischen aktiven.
                KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                guard isCurrent(epoch) else { return }
                invalidateTokenCache()
                lastSyncError = "Sitzung abgelaufen, bitte neu einloggen"
                needsReLogin = true
                isSyncing = false
                return
            } catch {
                // Abgebrochene Requests (z. B. bei Pull-to-Refresh, wenn SwiftUI den Task
                // abbricht) sind kein echter Fehler – nicht in den Offline-Modus wechseln.
                let isCancelled = (error is CancellationError) || (error as? URLError)?.code == .cancelled
                guard isCurrent(epoch) else { return }
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
        guard !isDemoMode else {
            updateFilteredDocs()
            return
        }
        await loadFirstPage()
        guard isQueryActive else { return }
        await runQuery(addingToRecents: nil)
    }

    func loadNextPage() async {
        guard !isLoadingMore, hasNextPage, let api = api else { return }
        // Seite 2 einer anderen Sortierung passt nicht hinter Seite 1 — erst neu laden.
        guard listSortOrder == nil || listSortOrder == currentSortOrder else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        let epoch = accountEpoch
        let order = currentSortOrder
        do {
            let page = try await api.fetchDocuments(page: nextPage, ordering: orderingParam(order))
            guard isCurrent(epoch) else { return }
            guard order == currentSortOrder else { isLoadingMore = false; return }
            documents.appendUniqueByID(page.documents)
            hasNextPage = page.hasNext
            currentPage = nextPage
            updateFilteredDocs()
        } catch {
            guard isCurrent(epoch) else { return }
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
    private func orderingParam(_ order: SortOrder? = nil) -> String {
        switch order ?? currentSortOrder {
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
            guard !Task.isCancelled else { return }
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
            // oder gar kein Filter — beides braucht keine Anfrage. Außer die Sortierung wurde
            // umgestellt: Dann gehört eine andere erste Seite vom Server in die Liste.
            lastAppliedQuery = nil
            lastAppliedQueryOrder = nil
            updateFilteredDocs()
            reloadIfSortOrderChanged()
            return
        }
        guard query != lastAppliedQuery || currentSortOrder != lastAppliedQueryOrder else {
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
            guard !Task.isCancelled else { return }
            isSearching = false
        }
    }

    /// Sortierung umgestellt, die geladene Liste hat aber noch die alte Server-Reihenfolge.
    ///
    /// Vorher passierte beim Umstellen gar nichts: `updateFilteredDocs()` übernahm die Liste
    /// unverändert, weil sie „schon sortiert vom Server" kam. `updateFilteredDocs()` hat die
    /// geladenen Dokumente inzwischen lokal umsortiert (sofort sichtbar); die erste Seite in
    /// der neuen Reihenfolge kommt jetzt vom Server.
    private func reloadIfSortOrderChanged() {
        guard hasLiveServer, let loaded = listSortOrder, loaded != currentSortOrder else { return }
        Task { await loadFirstPage() }
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

        let epoch = accountEpoch
        let order = currentSortOrder
        do {
            let page = try await api.fetchDocuments(
                query: query, page: 1, pageSize: Self.listPageSize, ordering: orderingParam(order)
            )
            guard isCurrent(epoch), order == currentSortOrder else { return }
            filteredDocs = page.documents.uniquedByID()
            searchHasNextPage = page.hasNext
            currentSearchPage = 1
            queryTotalCount = page.totalCount
            lastAppliedQuery = query
            lastAppliedQueryOrder = order
            reApplyPendingEditsToQueryResult()
            refineQueryResult()
            if let recent { addRecentSearch(recent) }
        } catch APIError.serverError(400) {
            guard isCurrent(epoch) else { return }
            // Der Server kennt einen der Filterparameter nicht. Für diesen Server dauerhaft
            // auf lokale Filterung zurückfallen — eine leere Liste wäre das schlechtere
            // Ergebnis als ein unvollständiger Filter mit Hinweis.
            DocumentFilterSupport.disable(serverUrl)
            lastAppliedQuery = nil
            updateFilteredDocs()
        } catch {
            guard isCurrent(epoch) else { return }
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
        for edit in pendingEdits where edit.failureReason == nil {
            guard let idx = filteredDocs.firstIndex(where: { $0.id == edit.docId }) else { continue }
            filteredDocs[idx] = edit.applied(to: filteredDocs[idx])
        }
    }

    func loadNextSearchPage() async {
        guard !isSearching, searchHasNextPage, let api = api, isQueryActive,
              lastAppliedQueryOrder == currentSortOrder else { return }
        isSearching = true
        let nextPage = currentSearchPage + 1
        let epoch = accountEpoch
        let order = currentSortOrder
        do {
            let page = try await api.fetchDocuments(
                query: activeQuery, page: nextPage,
                pageSize: Self.listPageSize, ordering: orderingParam(order)
            )
            guard isCurrent(epoch) else { return }
            guard order == currentSortOrder else { isSearching = false; return }
            filteredDocs.appendUniqueByID(page.documents)
            searchHasNextPage = page.hasNext
            currentSearchPage = nextPage
            reApplyPendingEditsToQueryResult()
        } catch {
            guard isCurrent(epoch) else { return }
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

    /// Rückmeldung einer Sammelaktion.
    ///
    /// Vorher landete sie in `bulkResultMessage`, das keine Ansicht anzeigte: Scheiterte
    /// „Tags zuweisen" oder „Rechte setzen", erfuhr der Nutzer nichts davon.
    func reportBulkResult(_ message: String, failed: Bool) {
        if failed {
            lastSyncError = message
            haptic(.heavy)
        } else {
            showSuccessToast(message)
        }
    }
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
        let epoch = accountEpoch
        Task {
            isBulkEditing = true
            do {
                try await api.bulkModifyTags(ids: ids, add: add, remove: remove)
                guard isCurrent(epoch) else { return }
                applyTagChangeLocally(add: add, remove: remove, in: docIds)
                invalidateLoadState()
                reportBulkResult("\(ids.count) Dokument(e) geändert", failed: false)
            } catch {
                // Die Warteschlange gehört inzwischen einem anderen Konto — dort hat die
                // Änderung nichts verloren.
                guard isCurrent(epoch) else { return }
                // Nicht verloren geben: als Einzeländerungen in die Warteschlange, die sie
                // später erneut versucht.
                queueTagChange(add: add, remove: remove, in: docIds)
                reportBulkResult("Offline gespeichert – wird später übertragen", failed: false)
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
        let epoch = accountEpoch
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetCorrespondent(ids: ids, correspondent: corrId)
                guard isCurrent(epoch) else { return }
                mutateLoadedDocuments(ids: docIds) { $0.correspondent = corrId }
                reportBulkResult("\(ids.count) Dokument(e) geändert", failed: false)
            } catch {
                reportBulkResult(error.localizedDescription, failed: true)
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
        let epoch = accountEpoch
        Task {
            isBulkEditing = true
            do {
                try await api.bulkSetDocumentType(ids: ids, documentType: typeId)
                guard isCurrent(epoch) else { return }
                mutateLoadedDocuments(ids: docIds) { $0.documentType = typeId }
                reportBulkResult("\(ids.count) Dokument(e) geändert", failed: false)
            } catch {
                reportBulkResult(error.localizedDescription, failed: true)
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
        let epoch = accountEpoch
        do {
            let field = try await api.createCustomField(
                name: name, dataType: type.rawValue, selectOptions: selectOptions
            )
            guard isCurrent(epoch) else { return nil }
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
        let epoch = accountEpoch
        do {
            try await api.deleteCustomField(id: id)
            guard isCurrent(epoch) else { return false }
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
        let epoch = accountEpoch
        if let fields = try? await api.fetchCustomFields(), isCurrent(epoch) {
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
        let epoch = accountEpoch
        do {
            let stats = try await api.fetchStatistics()
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if isCurrent(epoch) { isOffline = false }
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
        let epoch = accountEpoch
        async let paths = try? api.fetchStoragePaths()
        async let users = try? api.fetchUsers()
        async let groups = try? api.fetchGroups()
        let (p, u, g) = await (paths, users, groups)
        guard isCurrent(epoch) else { return }
        if let p { allStoragePaths = p }
        if let u { serverUsers = u }
        if let g { serverGroups = g }
    }

    /// Weist einen Speicherpfad zu.
    func assignStoragePath(_ pathId: Int?, to docIds: Set<Int>) {
        guard let api = api, !docIds.isEmpty, !isDemoMode else { return }
        Task {
            isBulkEditing = true
            do {
                let epoch = accountEpoch
                try await api.bulkSetStoragePath(ids: Array(docIds), storagePath: pathId)
                guard isCurrent(epoch) else { return }
                reportBulkResult("\(docIds.count) Dokument(e) verschoben", failed: false)
                await reloadVisible()
            } catch {
                reportBulkResult(error.localizedDescription, failed: true)
            }
            isBulkEditing = false
        }
    }

    /// Was mit dem Besitzer geschehen soll.
    enum OwnerChoice: Hashable {
        /// Jedes Dokument behält seinen bisherigen Besitzer.
        case unchanged
        /// Kein Besitzer — in paperless-ngx sieht ein solches Dokument **jeder** Benutzer.
        case nobody
        case user(Int)
    }

    /// Setzt Besitzer und Rechte.
    ///
    /// `set_permissions` schreibt den Besitzer immer mit: ngx führt `update(owner=owner)` aus.
    /// Früher ging „unverändert" als `owner: null` hinaus — der Besitzer wurde entfernt, und
    /// besitzerlose Dokumente sind für alle Benutzer der Instanz sichtbar. Für „unverändert"
    /// werden die Besitzer deshalb erst gelesen und die Dokumente je Besitzer gesetzt.
    func assignPermissions(owner: OwnerChoice, viewUsers: [Int], viewGroups: [Int],
                           changeUsers: [Int], changeGroups: [Int], to docIds: Set<Int>) {
        guard let api = api, !docIds.isEmpty, !isDemoMode else { return }
        Task {
            isBulkEditing = true
            do {
                let byOwner: [Int?: [Int]]
                switch owner {
                case .unchanged:
                    let owners = try await api.fetchOwners(ids: Array(docIds))
                    // Fehlt auch nur ein Besitzer, lieber nichts tun als raten: Ein geratenes
                    // `nil` macht das Dokument öffentlich.
                    guard Set(owners.keys) == docIds else { throw APIError.noData }
                    byOwner = Dictionary(grouping: Array(docIds)) { owners[$0] ?? nil }
                case .nobody:
                    byOwner = [nil: Array(docIds)]
                case .user(let id):
                    byOwner = [id: Array(docIds)]
                }
                for (ownerId, ids) in byOwner {
                    try await api.bulkSetPermissions(
                        ids: ids, owner: ownerId,
                        viewUsers: viewUsers, viewGroups: viewGroups,
                        changeUsers: changeUsers, changeGroups: changeGroups
                    )
                }
                reportBulkResult("Rechte für \(docIds.count) Dokument(e) gesetzt", failed: false)
            } catch {
                reportBulkResult(error.localizedDescription, failed: true)
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
    func checkForDuplicate(text: String) async -> DuplicateWarning? {
        guard isDuplicateCheckEnabled, !text.isEmpty else { return nil }
        let documents = documents
        // Fingerabdrücke aller geladenen Dokumente abseits des Main Threads — vorher synchron,
        // bei jedem Öffnen des Importformulars.
        let match = await Task.detached(priority: .userInitiated) { () -> (documentId: Int, reason: String, confidence: Double)? in
            let candidate = DuplicateDetector.fingerprint(of: text)
            guard !candidate.isEmpty else { return nil }
            let known: [(documentId: Int, fingerprint: DuplicateDetector.Fingerprint)] = documents
                .compactMap { doc in
                    guard let content = doc.content, !content.isEmpty else { return nil }
                    return (doc.id, DuplicateDetector.fingerprint(of: content))
                }
            guard let first = DuplicateDetector.matches(for: candidate, in: known).first else { return nil }
            return (first.documentId, first.reason, first.confidence)
        }.value
        guard let match, let doc = documents.first(where: { $0.id == match.documentId }) else { return nil }
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
        // `try?` machte aus „Server antwortet nicht" und „noch keine ASN vergeben" dasselbe `nil` —
        // in einem Archiv ohne jede ASN lieferte „Nächste freie" deshalb nichts statt 1.
        let highest: Int?
        do {
            highest = try await api.fetchHighestASN()
        } catch {
            return nil
        }
        return (highest ?? 0) + 1
    }

    // MARK: - Import-Regeln

    /// Regeln, die das Importformular vorbelegen. Reihenfolge entscheidet.
    ///
    /// Gesichert wird ausdrücklich über `saveUploadRules()` — die Regelliste ändert sich beim
    /// Bearbeiten mehrfach hintereinander, ein `didSet` würde bei jedem Tastendruck schreiben.
    @Published var uploadRules: [UploadRule] = []

    /// Je Konto: Regeln verweisen auf Sender, Typen und Tags über deren IDs — und die gelten nur
    /// auf einem Server. Vorher galten die Regeln für alle Konten; auf dem zweiten Server belegte
    /// „Kontoauszug" dann einen ganz anderen Sender vor.
    private func uploadRulesKey(_ account: UUID) -> String { "uploadRules.\(account.uuidString)" }

    func loadUploadRules() {
        guard let account = activeAccountId else { uploadRules = []; return }
        let defaults = UserDefaults.standard
        var data = defaults.data(forKey: uploadRulesKey(account))
        if data == nil, let legacy = defaults.data(forKey: "uploadRules") {
            // Umzug: Die bisherigen, kontolosen Regeln gehören zu dem Konto, das sie beim ersten
            // Start dieser Version öffnet.
            defaults.set(legacy, forKey: uploadRulesKey(account))
            defaults.removeObject(forKey: "uploadRules")
            data = legacy
        }
        uploadRules = data.flatMap { try? JSONDecoder().decode([UploadRule].self, from: $0) } ?? []
    }

    func saveUploadRules() {
        guard let account = activeAccountId,
              let data = try? JSONEncoder().encode(uploadRules) else { return }
        UserDefaults.standard.set(data, forKey: uploadRulesKey(account))
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
        guard !documents.isEmpty else { return }

        // Das Array selbst ist ein Wertetyp und wird beim Übergeben nicht kopiert. Die Texte
        // zusammenzusetzen passiert bewusst *im* Hintergrund-Task: Vorher lief das hier auf
        // dem Main Thread und baute bei jedem Laden eine Zeichenkette aus dem erkannten Text
        // aller geladenen Dokumente — bei einem vollen Archiv zweistellige Megabyte, mitten
        // im Bildaufbau.
        let snapshot = documents
        let account = activeAccountId
        Task.detached(priority: .background) {
            // Nur weiterarbeiten, wenn der Index überhaupt in Gebrauch ist. Wer „Archiv
            // fragen" nie benutzt, soll dafür auch keine Rechenzeit und keinen Akku zahlen —
            // der erste Aufbau passiert bewusst auf Knopfdruck in den Einstellungen.
            guard await ArchiveIndex.shared.count(account: account) > 0 else { return }
            let payload = snapshot.compactMap { doc -> (id: Int, text: String)? in
                guard let content = doc.content, !content.isEmpty else { return nil }
                return (doc.id, doc.title + " " + content)
            }
            guard !payload.isEmpty else { return }
            await ArchiveIndex.shared.index(payload, account: account)
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
        let epoch = accountEpoch

        var page = 1
        var processed = 0
        var total: Int? = nil
        while true {
            guard !Task.isCancelled, isCurrent(epoch) else { break }
            guard let result = try? await api.fetchDocuments(
                page: page, pageSize: 250, ordering: "-added,-id"
            ), isCurrent(epoch) else { break }
            if total == nil { total = result.totalCount }

            let payload = result.documents.compactMap { doc -> (id: Int, text: String)? in
                guard let content = doc.content, !content.isEmpty else { return nil }
                return (doc.id, doc.title + " " + content)
            }
            await ArchiveIndex.shared.index(payload, account: account, persist: false)
            guard isCurrent(epoch) else { break }

            processed += result.documents.count
            if let total, total > 0 {
                archiveIndexProgress = min(1, Double(processed) / Double(total))
            }
            archiveIndexStatus = "\(processed) Dokumente verarbeitet …"
            guard result.hasNext else { break }
            page += 1
        }

        // Einmal am Ende schreiben — auch nach einem Abbruch, damit das Erreichte bleibt.
        await ArchiveIndex.shared.flush(account: account)
        let indexed = await ArchiveIndex.shared.count(account: account)
        // Nach einem Kontowechsel hat `beginNewAccountEpoch()` die Anzeige schon zurückgesetzt.
        guard isCurrent(epoch) else { return }
        archiveIndexStatus = "\(indexed) Dokumente im Index."
        archiveIndexProgress = 1
        isBuildingArchiveIndex = false
    }

    /// Anzahl der indexierten Dokumente — für die Anzeige in den Einstellungen.
    func archiveIndexCount() async -> Int {
        await ArchiveIndex.shared.count(account: activeAccountId)
    }

    func clearArchiveIndex() async {
        await ArchiveIndex.shared.clear(account: activeAccountId)
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
        // Nur wenn die Liste auch in der *aktuellen* Sortierung geladen wurde — nach einem
        // Sortierwechsel wird lokal umsortiert, bis die neue erste Seite da ist.
        if !activeQuery.hasFilters && hasLiveServer && (listSortOrder == nil || listSortOrder == currentSortOrder) {
            filteredDocs = documents
            return
        }

        let calendar = Calendar.current
        let now = Date()
        // Der lokale Filter muss dieselben Mengen auswerten wie `activeQuery`, sonst zeigt
        // dasselbe Filterset offline etwas anderes als online. Einmal gebaut — vorher entstand
        // die Anfrage samt Datumsgrenzen für jedes einzelne Dokument neu.
        let query = activeQuery

        let filtered = documents.filter { doc in
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
        let customFields = normalizedForServer(customFields)
        var edit = PendingEdit(docId: docId, title: title, created: iso, correspondent: corr, documentType: type, archiveSerialNumber: asn, tags: tags, customFields: customFields)
        // Ausgangsstand, gegen den verglichen wird: das Dokument, wie die App es gerade zeigt —
        // inklusive noch nicht übertragener früherer Änderungen.
        if let original = anyLoadedDocument(docId) {
            let changed = PendingEdit.changedFields(
                from: original, title: title, created: iso, correspondent: corr,
                documentType: type, archiveSerialNumber: asn, tags: tags, customFields: customFields
            )
            // Speichern ohne Änderung: nichts zu tun, keine Anfrage.
            guard !changed.isEmpty else { return }
            edit.changedFields = changed
            edit.existingFieldIDs = original.customFields.map(\.field)
        }
        func apply(to doc: inout Document) {
            doc = edit.applied(to: doc)
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
        pendingEdits.append(edit)
        saveToDisk()
        updateFilteredDocs()
        Task { await processEditQueue() }
    }

    /// Läuft nie zweimal gleichzeitig — siehe `processUploadQueue()`.
    private func processEditQueue() async {
        let epoch = accountEpoch
        guard !isDemoMode, editQueueEpoch != epoch,
              let api = api, let accountId = activeAccountId else { return }
        editQueueEpoch = epoch
        defer { if editQueueEpoch == epoch { editQueueEpoch = nil } }

        // `api` gehört zum Konto, dessen Warteschlange hier abgearbeitet wird — einmal gebunden.
        // Vorher entstand es in jeder Runde neu und zeigte nach einem Kontowechsel auf den
        // Server des neuen Kontos.
        var processed: [UUID] = []
        var rejected: [UUID: String] = [:]
        for edit in pendingEdits where edit.failureReason == nil && !queueItemsInFlight.contains(edit.id) {
            guard isCurrent(epoch) else { break }
            queueItemsInFlight.insert(edit.id)
            defer { queueItemsInFlight.remove(edit.id) }
            do {
                try await api.patchDocument(edit)
                processed.append(edit.id)
                guard isCurrent(epoch) else { break }
            } catch APIError.rejected(let code, let reason) {
                guard isCurrent(epoch) else { break }
                // Der Server lehnt genau diese Änderung ab (Dokument gelöscht, ungültiger
                // Feldwert, keine Rechte). Markieren und mit der nächsten weitermachen — vorher
                // hielt ein solcher Eintrag die Warteschlange für immer an.
                rejected[edit.id] = APIError.rejected(code, reason).localizedDescription
            } catch APIError.unauthorized {
                // Kein Netzproblem, sondern eine abgelaufene Anmeldung. Die Nachfrage übernimmt
                // der nächste Sync (`loadFirstPage`); hier nur anhalten.
                break
            } catch {
                if isCurrent(epoch) { isOffline = true }
                break
            }
        }
        guard isCurrent(epoch) else {
            // Das Konto wurde gewechselt. Was bis dahin übertragen ist, gehört aus der
            // Warteschlange des alten Kontos — sonst ginge es beim nächsten Mal erneut hinaus.
            if activeAccountId == accountId {
                // Hin- und zurückgewechselt: Die Warteschlange ist wieder die im Speicher.
                pendingEdits.removeAll { processed.contains($0.id) }
                saveToDisk()
            } else {
                PersistenceService.removeQueued(PendingEdit.self, ids: Set(processed),
                                                filename: "edits.json", accountId: accountId)
            }
            return
        }
        // Eine abgelehnte Änderung, auf die später eine erfolgreiche am selben Dokument folgt,
        // ist überholt: Der PATCH trägt den vollständigen Stand. Bliebe sie stehen, würde
        // „erneut versuchen" den neueren Stand mit dem älteren überschreiben.
        let succeeded = Set(processed)
        var lastSuccess: [Int: Int] = [:]
        for (index, edit) in pendingEdits.enumerated() where succeeded.contains(edit.id) {
            lastSuccess[edit.docId] = index
        }
        let superseded = Set(pendingEdits.enumerated().compactMap { index, edit -> UUID? in
            guard edit.failureReason != nil || rejected[edit.id] != nil,
                  let later = lastSuccess[edit.docId], index < later else { return nil }
            return edit.id
        })
        pendingEdits.removeAll { succeeded.contains($0.id) || superseded.contains($0.id) }
        for (id, reason) in rejected {
            guard let idx = pendingEdits.firstIndex(where: { $0.id == id }) else { continue }
            pendingEdits[idx].failureReason = reason
        }
        saveToDisk()
        // Eine Rückmeldung für den ganzen Durchlauf. Vorher gab es je Änderung einen eigenen Toast
        // samt 4-Sekunden-Task und Bewertungs-Ereignis — bei 50 Sammeländerungen ein Dauerfeuer.
        if !processed.isEmpty {
            showSuccessToast(processed.count == 1 ? "Änderung gespeichert" : "\(processed.count) Änderungen gespeichert")
            registerReviewEvent()
        }
        let stillRejected = rejected.keys.filter { !superseded.contains($0) }.count
        if stillRejected > 0 {
            lastSyncError = stillRejected == 1
                ? "Eine Änderung wurde vom Server abgelehnt – Details unter Einstellungen › Warteschlange."
                : "\(stillRejected) Änderungen wurden vom Server abgelehnt – Details unter Einstellungen › Warteschlange."
        }
        // Der Server kann beim Übernehmen mehr geändert haben als die App lokal eingepflegt
        // hat (Regeln, Workflows). Bei aktivem Filter muss die Trefferliste deshalb neu
        // gestellt werden — sonst steht dort ein Stand von vor der Änderung. Nach einer
        // Ablehnung zeigt die Liste lokal Werte, die der Server nie übernommen hat.
        if !processed.isEmpty || !rejected.isEmpty { invalidateLoadState() }
    }

    func removePendingEdit(at offsets: IndexSet) { pendingEdits.remove(atOffsets: offsets); saveToDisk() }

    /// Abgelehnte Uploads und Änderungen erneut versuchen (Knopf in `PendingQueueView`).
    func retryRejectedQueueItems() {
        for idx in pendingUploads.indices { pendingUploads[idx].failureReason = nil }
        for idx in pendingEdits.indices { pendingEdits[idx].failureReason = nil }
        saveToDisk()
        sync(silent: true)
    }

    /// Gibt es etwas, das die Warteschlange noch versuchen würde?
    var hasRetryableQueueItems: Bool {
        pendingUploads.contains { $0.failureReason == nil }
            || pendingEdits.contains { $0.failureReason == nil }
    }

    /// Noch nicht übertragene Änderungen auf die Gesamtliste anwenden. Abgelehnte bleiben
    /// außen vor — die Liste soll nicht zeigen, was der Server nie übernommen hat.
    func reApplyPendingEdits() {
        for edit in pendingEdits where edit.failureReason == nil {
            if let idx = documents.firstIndex(where: { $0.id == edit.docId }) {
                documents[idx] = edit.applied(to: documents[idx])
            }
        }
    }

    /// Bringt Feldwerte in die Form, die paperless-ngx annimmt.
    ///
    /// Beträge: ngx erwartet `EUR12.50` oder `12.50`. Wer auf einer deutschen Tastatur
    /// „12,50 €" eintippt, bekam bisher eine Ablehnung (400) — und die blockierte früher die
    /// ganze Warteschlange.
    func normalizedForServer(_ fields: [CustomFieldEdit]) -> [CustomFieldEdit] {
        fields.map { entry in
            guard customField(id: entry.field)?.type == .monetary,
                  case .text(let raw) = entry.value else { return entry }
            return CustomFieldEdit(field: entry.field, value: Self.normalizedMonetary(raw))
        }
    }

    nonisolated static func normalizedMonetary(_ raw: String) -> CFValue {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .none }
        // Führender Währungscode (`EUR12,50`) bleibt erhalten, alles andere außer Ziffern und
        // Trennzeichen fällt weg (`€`, Leerzeichen).
        var code = ""
        if text.count >= 3, text.prefix(3).allSatisfy({ $0.isASCII && $0.isUppercase }) {
            code = String(text.prefix(3))
            text = String(text.dropFirst(3))
        }
        var number = text.filter { $0.isASCII && ($0.isNumber || $0 == "," || $0 == "." || $0 == "-") }
        // „1.234,56" → Tausenderpunkt weg, Komma wird Dezimalpunkt.
        if number.contains(",") {
            number = number.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(number) else { return .text(raw) }
        return .text(code + String(format: "%.2f", value))
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
        let epoch = accountEpoch
        guard !isDemoMode, uploadQueueEpoch != epoch,
              let api = api, let accountId = activeAccountId else { return }
        uploadQueueEpoch = epoch
        defer { if uploadQueueEpoch == epoch { uploadQueueEpoch = nil } }

        var processed: [UUID] = []
        var rejected: [(id: UUID, title: String, reason: String)] = []
        var newTasks: [(String, String)] = []
        // Endet der Durchlauf, egal wie, läuft kein Upload mehr. Vorher blieb die Anzeige nach
        // einem Fehler auf „Lädt hoch" stehen.
        defer { if isCurrent(epoch) { uploadProgress = nil } }
        // `api` einmal gebunden — siehe `processEditQueue()`. Vorher gingen die Dateien von
        // Konto A nach einem Wechsel an den Server von Konto B.
        for item in pendingUploads where item.failureReason == nil && !queueItemsInFlight.contains(item.id) {
            guard isCurrent(epoch) else { break }
            queueItemsInFlight.insert(item.id)
            defer { queueItemsInFlight.remove(item.id) }
            do {
                uploadProgress = 0
                let title = item.title
                let taskId = try await api.uploadDocument(item) { [weak self] fraction in
                    Task { @MainActor in
                        // Nur den laufenden Upload melden — der nächste beginnt wieder bei 0.
                        // Ein Rückruf, der erst nach dem Ende ankommt, darf die Anzeige nicht
                        // wieder einschalten.
                        guard let self, self.isCurrent(epoch), self.uploadProgress != nil else { return }
                        self.uploadProgress = fraction
                        self.uploadProgressTitle = title
                    }
                }
                processed.append(item.id)
                guard isCurrent(epoch) else { break }
                uploadProgress = nil
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
            } catch APIError.rejected(let code, let reason) {
                guard isCurrent(epoch) else { break }
                // Datei zu groß, Typ nicht erlaubt, keine Rechte: Ein neuer Versuch ändert daran
                // nichts. Markieren und die übrigen weiter hochladen.
                uploadProgress = nil
                rejected.append((item.id, item.title, APIError.rejected(code, reason).localizedDescription))
            } catch APIError.unauthorized {
                break
            } catch {
                if isCurrent(epoch) { isOffline = true }
                break
            }
        }
        guard isCurrent(epoch) else {
            if activeAccountId == accountId {
                pendingUploads.removeAll { processed.contains($0.id) }
                saveToDisk()
            } else {
                PersistenceService.removeQueued(PendingUpload.self, ids: Set(processed),
                                                filename: "pending.json", accountId: accountId)
            }
            return
        }
        pendingUploads.removeAll { processed.contains($0.id) }
        for entry in rejected {
            guard let idx = pendingUploads.firstIndex(where: { $0.id == entry.id }) else { continue }
            pendingUploads[idx].failureReason = entry.reason
        }
        saveToDisk()
        if let first = rejected.first {
            let label = "\u{201E}" + first.title + "\u{201C}"
            importErrorMessage = rejected.count == 1
                ? "\(label) wurde nicht hochgeladen. \(first.reason)"
                : "\(rejected.count) Dateien wurden nicht hochgeladen, darunter \(label). \(first.reason)"
            haptic(.heavy)
        }
        if !processed.isEmpty { await reloadVisible() }
        for (taskId, title) in newTasks {
            Task { await followUp(taskId: taskId, title: title) }
        }
    }

    // MARK: - Uploads, die noch unterwegs sind

    /// Ein Upload zwischen „abgeschickt" und „im Archiv".
    ///
    /// Fasst beide Zwischenstufen zusammen: die eigene Warteschlange (noch nicht beim Server)
    /// und die Verarbeitung auf dem Server. Für den Nutzer ist das derselbe Zustand — das
    /// Dokument ist unterwegs — und gehört deshalb an dieselbe Stelle in der Liste.
    struct InFlightUpload: Identifiable, Equatable {
        enum Phase: Equatable { case queued, processing, failed, duplicate }
        let id: String
        let title: String
        var phase: Phase
        var detail: String?
        var canDismiss = true

        var isProblem: Bool { phase == .failed || phase == .duplicate }
    }

    /// Was gerade unterwegs ist — in der Reihenfolge, in der es angestoßen wurde.
    var inFlightUploads: [InFlightUpload] {
        let queued = pendingUploads.map {
            // Abgelehnte bleiben in der Warteschlange, bis der Nutzer entscheidet — ausblenden
            // hieße hier löschen, und das gehört nicht hinter ein kleines x.
            $0.failureReason == nil
                ? InFlightUpload(id: "queued-\($0.id.uuidString)", title: $0.title, phase: .queued)
                : InFlightUpload(id: "queued-\($0.id.uuidString)", title: $0.title, phase: .failed,
                                 detail: $0.failureReason, canDismiss: false)
        }
        let onServer = uploadTaskStatuses.compactMap { status -> InFlightUpload? in
            switch status.state {
            case .waiting, .running:
                return InFlightUpload(id: status.id, title: status.title,
                                      phase: .processing, detail: status.message)
            case .failed:
                return InFlightUpload(id: status.id, title: status.title,
                                      phase: .failed, detail: status.message)
            case .duplicate:
                return InFlightUpload(id: status.id, title: status.title,
                                      phase: .duplicate, detail: status.message)
            case .succeeded, .unknown:
                // Erledigt: Das echte Dokument steht jetzt in der Liste, der Platzhalter hat
                // seinen Zweck erfüllt.
                return nil
            }
        }
        return queued + onServer
    }

    /// Nimmt einen einzelnen Eintrag aus der Anzeige (Fehler oder Dublette bestätigen).
    func dismissInFlight(_ id: String) {
        uploadTaskStatuses.removeAll { $0.id == id }
    }

    // MARK: - Verarbeitungsstatus

    /// Läufe, die die App gerade verfolgt. Sichtbar in `PendingQueueView`.
    @Published var uploadTaskStatuses: [UploadTaskStatus] = []

    /// Sendefortschritt des laufenden Uploads (0…1), sonst `nil`.
    @Published var uploadProgress: Double? = nil
    @Published var uploadProgressTitle: String = ""

    /// Fortschritt der laufenden Arbeit — wenn er sich beziffern lässt.
    ///
    /// `nil` heißt: Es läuft etwas, aber niemand kann sagen, wie weit. Eine einzelne Abfrage
    /// ist unterwegs oder fertig; dazwischen gibt es nichts zu messen. Dann zeigt die
    /// Oberfläche eine unbestimmte Linie. Einen Prozentwert zu erfinden, wo keiner existiert,
    /// wäre eine Lüge an der auffälligsten Stelle der App.
    var activityProgress: Double? {
        if isDownloadingAll { return downloadProgress }
        if isBuildingArchiveIndex { return archiveIndexProgress }
        if let uploadProgress { return uploadProgress }
        return nil
    }

    /// Was gerade läuft, in Worten.
    var activityLabel: String {
        if isDownloadingAll { return downloadStatusText.isEmpty ? "Lädt herunter" : downloadStatusText }
        if isBuildingArchiveIndex { return "Index" }
        if uploadProgress != nil {
            return uploadProgressTitle.isEmpty ? "Lädt hoch" : "Lädt hoch: \(uploadProgressTitle)"
        }
        if isSearching { return "Suche" }
        if isBulkEditing { return "Wird übertragen" }
        return "Aktualisieren"
    }

    /// Läuft überhaupt etwas, das angezeigt werden soll?
    var isActivityRunning: Bool {
        isSearching || isSyncing || isBulkEditing || isDownloadingAll
            || isBuildingArchiveIndex || uploadProgress != nil
    }

    /// Wie lange auf den Consumer gewartet wird, bevor die App den Auftrag nur noch als
    /// „wird verarbeitet" führt.
    private static let taskPollAttempts = 20
    private static let taskPollInterval: UInt64 = 3_000_000_000

    /// Verfolgt einen Verarbeitungsauftrag und meldet das Ergebnis.
    func followUp(taskId: String, title: String) async {
        guard let api = api else { return }
        let epoch = accountEpoch
        for attempt in 1...Self.taskPollAttempts {
            // Erst warten: unmittelbar nach dem Upload steht der Auftrag noch auf PENDING.
            try? await Task.sleep(nanoseconds: Self.taskPollInterval)
            guard !Task.isCancelled, isCurrent(epoch) else { return }

            let task: ConsumptionTask?
            do {
                task = try await api.fetchTask(taskId: taskId)
                guard isCurrent(epoch) else { return }
            } catch {
                guard isCurrent(epoch) else { return }
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
        let epoch = accountEpoch
        Task {
            guard let api = api, let accountId = activeAccountId else { return }
            do {
                try await api.deleteDocument(id: id)
            } catch {
                // Ohne diese Prüfung verschwand das Dokument auch dann aus der Liste, wenn der
                // Server es gar nicht gelöscht hat (offline, fehlende Rechte) — und tauchte
                // beim nächsten Sync wieder auf.
                if isCurrent(epoch) { lastSyncError = error.localizedDescription }
                return
            }
            // Datei und Indexeintrag gehören zum Konto der Anfrage, nicht zum aktiven.
            PersistenceService.deleteDocFile(docId: id, accountId: accountId)
            Task.detached(priority: .background) {
                await ArchiveIndex.shared.remove(id, account: accountId)
            }
            guard isCurrent(epoch) else { return }
            removeDocumentLocally(id: id)
            saveToDisk()
        }
    }

    /// Nimmt ein Dokument aus beiden Listen. `filteredDocs` muss ausdrücklich mit, weil
    /// `updateFilteredDocs()` bei aktiver Suche nichts neu aufbaut.
    func removeDocumentLocally(id: Int) {
        removeDocumentsLocally(ids: [id])
    }

    /// Wie `removeDocumentLocally(id:)`, aber für viele in einem Durchgang — ein Filterlauf
    /// statt einem pro Dokument.
    func removeDocumentsLocally(ids: Set<Int>) {
        documents.removeAll { ids.contains($0.id) }
        filteredDocs.removeAll { ids.contains($0.id) }
        let before = inboxDocuments.count
        inboxDocuments.removeAll { ids.contains($0.id) }
        if let total = inboxTotal { inboxTotal = max(0, total - (before - inboxDocuments.count)) }
        updateFilteredDocs()
    }

    /// Löscht mehrere Dokumente in einem Serveraufruf (`bulk_edit` mit `delete`).
    ///
    /// Vorher startete das Sammellöschen je Dokument einen eigenen DELETE-Task, jeder mit
    /// eigenem Filterlauf und eigenem Schreibvorgang auf die Platte.
    func deleteDocuments(ids: Set<Int>) {
        guard ids.count > 1 else {
            if let only = ids.first { deleteDocument(id: only) }
            return
        }
        guard let api = api, let accountId = activeAccountId else { return }
        let epoch = accountEpoch
        Task {
            isBulkEditing = true
            do {
                try await api.bulkDelete(ids: Array(ids))
            } catch {
                guard isCurrent(epoch) else { return }
                isBulkEditing = false
                reportBulkResult(error.localizedDescription, failed: true)
                return
            }
            for id in ids { PersistenceService.deleteDocFile(docId: id, accountId: accountId) }
            Task.detached(priority: .background) {
                for id in ids { await ArchiveIndex.shared.remove(id, account: accountId) }
            }
            guard isCurrent(epoch) else { return }
            removeDocumentsLocally(ids: ids)
            saveToDisk()
            isBulkEditing = false
            reportBulkResult("\(ids.count) Dokument(e) gelöscht", failed: false)
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
        deleteMetadata { try await $0.deleteTag(id: id) }
    }

    func deleteCorrespondent(id: Int) {
        deleteMetadata { try await $0.deleteCorrespondent(id: id) }
    }

    func deleteDocumentType(id: Int) {
        deleteMetadata { try await $0.deleteDocumentType(id: id) }
    }

    /// Löscht einen Tag, Sender oder Typ und lädt die Stammdaten neu. Vorher verschluckte `try?`
    /// jeden Fehler — ohne Rechte oder ohne Netz blieb der Eintrag stehen, ohne dass jemand erfuhr, warum.
    private func deleteMetadata(_ operation: @escaping (PaperlessAPI) async throws -> Void) {
        guard let api = api else { return }
        let epoch = accountEpoch
        Task {
            do {
                try await operation(api)
            } catch {
                if isCurrent(epoch) { reportBulkResult(error.localizedDescription, failed: true) }
                return
            }
            await syncMetadata()
        }
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
        // Ablageort vor dem Warten festhalten: Nach einem Kontowechsel zeigte
        // `localFileURL(for:)` in den Ordner des neuen Kontos, und das PDF von Dokument 42
        // aus Konto A lag danach als Dokument 42 von Konto B im Cache.
        let fileURL = localFileURL(for: docId)
        if fileExists(docId: docId) {
            return await Task.detached(priority: .userInitiated) { try? Data(contentsOf: fileURL) }.value
        }
        guard let api = api else { return nil }
        let epoch = accountEpoch
        if let data = try? await api.downloadDocument(id: docId) {
            try? PersistenceService.writeFile(data, to: fileURL)
            return isCurrent(epoch) ? data : nil
        }
        return nil
    }

    func deleteLocalFile(docId: Int) {
        guard let id = activeAccountId else { return }
        PersistenceService.deleteDocFile(docId: docId, accountId: id)
        calculateStorage()
    }

    func startFullDownload() {
        guard let api = api, let accountId = activeAccountId else { return }
        let epoch = accountEpoch
        isDownloadingAll = true
        downloadProgress = 0.0
        downloadStatusText = "Lade Dokumentliste..."
        downloadTask = Task {
            let allDocs: [Document]
            do {
                allDocs = try await api.fetchAllDocuments()
            } catch {
                guard isCurrent(epoch) else { return }
                isDownloadingAll = false
                downloadStatusText = "Fehler: \(error.localizedDescription)"
                return
            }
            for (index, doc) in allDocs.enumerated() {
                guard isCurrent(epoch), isDownloadingAll, !Task.isCancelled else { break }
                downloadProgress = Double(index) / Double(allDocs.count)
                downloadStatusText = "Lade \(index + 1) von \(allDocs.count)..."
                if !PersistenceService.fileExists(docId: doc.id, accountId: accountId) {
                    if let data = try? await api.downloadDocument(id: doc.id) {
                        try? PersistenceService.writeFile(
                            data, to: PersistenceService.docFileURL(for: doc.id, accountId: accountId)
                        )
                    }
                }
            }
            guard isCurrent(epoch) else { return }
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
                guard self.activeAccountId == id else { return }
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
    /// Verhindert, dass der erste Durchlauf mehrfach angestoßen wird.
    private var spotlightFullRunScheduled = false

    /// Schalter „In Spotlight aufnehmen" (Einstellungen → Datenschutz). Ohne Wert: an.
    nonisolated static func spotlightEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "spotlightEnabled") as? Bool ?? true
    }

    /// Ob der erkannte Text in die Systemsuche geht. Nie bei aktiver App-Sperre: Der Text
    /// stünde sonst ohne Face ID für jeden lesbar, der das Gerät entsperrt hat.
    nonisolated static func spotlightIncludesContent(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: "useFaceID")
            && (defaults.object(forKey: "spotlightFullText") as? Bool ?? true)
    }

    /// Nach einer Änderung an Spotlight-Schalter, Volltext oder App-Sperre: Der vorhandene
    /// Index enthält noch den alten Umfang und wird verworfen bzw. neu aufgebaut.
    func applySpotlightSettings() {
        spotlightTask?.cancel()
        spotlightTask = nil
        fullSpotlightIndexBuilt = false
        lastSpotlightRun = nil
        guard Self.spotlightEnabled() else {
            clearSpotlightIndex()
            return
        }
        let epoch = accountEpoch
        spotlightTask = Task {
            let result = await rebuildSpotlightIndex()
            guard isCurrent(epoch) else { return }
            if result.errorMessage != nil {
                Self.logger.error("Spotlight-Neuaufbau nach Einstellungsänderung unvollständig")
            }
        }
    }

    func indexDocumentsForSpotlightIfDue() {
        guard Self.spotlightEnabled() else { return }
        if !fullSpotlightIndexBuilt {
            // Der erste Lauf blättert durch das ganze Archiv und lädt Vorschaubilder nach.
            // Nicht in dem Moment, in dem der Nutzer auf seine Liste wartet — ein paar
            // Sekunden später bekommt er davon nichts mit.
            guard !spotlightFullRunScheduled else { return }
            spotlightFullRunScheduled = true
            lastSpotlightRun = Date()
            let epoch = accountEpoch
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard isCurrent(epoch) else { return }
                indexDocumentsForSpotlight()
                spotlightFullRunScheduled = false
            }
            return
        }
        if let last = lastSpotlightRun,
           Date().timeIntervalSince(last) < Self.spotlightMinInterval { return }
        lastSpotlightRun = Date()
        indexDocumentsForSpotlight()
    }

    func indexDocumentsForSpotlight() {
        let full = !fullSpotlightIndexBuilt
        let epoch = accountEpoch
        spotlightTask = Task {
            let result = await performSpotlightIndexing(fullArchive: full)
            guard isCurrent(epoch) else { return }
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
        let epoch = accountEpoch
        let result = await performSpotlightIndexing(fullArchive: true)
        guard isCurrent(epoch) else { return SpotlightIndexResult() }
        if result.errorMessage == nil && result.indexed > 0 { fullSpotlightIndexBuilt = true }
        return result
    }

    /// Holt für den Index das ganze Archiv vom Server. Ohne Server (Demo-Modus, offline)
    /// bleibt es bei dem, was geladen ist.
    private func documentsForIndexing(fullArchive: Bool, epoch: Int) async -> [Document] {
        let loaded = Array(documents.prefix(Self.spotlightDocumentLimit))
        guard fullArchive, let api = api else { return loaded }

        var collected: [Document] = []
        var page = 1
        while collected.count < Self.spotlightDocumentLimit {
            guard !Task.isCancelled, isCurrent(epoch),
                  let result = try? await api.fetchDocuments(
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
        guard Self.spotlightEnabled(), let accountId = activeAccountId else { return SpotlightIndexResult() }
        let epoch = accountEpoch
        let api = api
        let domain = Self.spotlightDomain(for: accountId)
        let docs = await documentsForIndexing(fullArchive: fullArchive, epoch: epoch)
        // Nach einem Kontowechsel hat `switchAccount` den Index geleert — nichts vom alten
        // Konto nachschieben.
        guard isCurrent(epoch) else { return SpotlightIndexResult() }
        let tags = allTags
        let corrs = allCorrespondents
        let types = allDocTypes
        let includeContent = Self.spotlightIncludesContent()

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
            guard !Task.isCancelled, isCurrent(epoch) else { break }
            var thumbnails: [Int: Data] = [:]
            var pending: [Int] = []
            // Vorschaubilder von der Platte im Hintergrund lesen — vorher synchron auf dem Main Thread,
            // 100 Dateien je Block.
            let thumbnailURLs = chunk.map { ($0.id, ImageCache.shared.getFilePath(for: $0.id)) }
            let onDisk = await Task.detached(priority: .background) { () -> [Int: Data] in
                var found: [Int: Data] = [:]
                for (id, url) in thumbnailURLs {
                    if let data = try? Data(contentsOf: url) { found[id] = data }
                }
                return found
            }.value
            guard isCurrent(epoch) else { break }
            for doc in chunk {
                if let data = onDisk[doc.id] {
                    thumbnails[doc.id] = data
                } else {
                    pending.append(doc.id)
                }
            }

            if downloadBudget > 0, let api, !pending.isEmpty {
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
                // Der Bildcache folgt dem aktiven Konto: nach einem Wechsel landeten die
                // Vorschauen sonst unter derselben ID im Cache des neuen.
                guard isCurrent(epoch) else { break }

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
                    // Ohne Volltext (Schalter aus oder App-Sperre aktiv) nur Titel und Stichwörter.
                    if includeContent, let content = doc.content { attrs.textContent = String(content.prefix(15000)) }

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
            guard isCurrent(epoch) else { break }

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
        guard let id = activeAccountId, diskStateAccountId == id else { return }
        PersistenceService.saveUploads(pendingUploads, accountId: id)
        PersistenceService.save(pendingEdits,   toURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))
        PersistenceService.save(savedFilters,   toURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json"))
    }

    /// Schreibt Dokumente und Stammdaten, wenn sich etwas geändert hat.
    func saveArchive(force: Bool = false) {
        guard let id = activeAccountId, diskStateAccountId == id else { return }
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
        // Stammdaten mit Inhalt, nicht nur ihre Anzahl: Ein umbenannter Tag oder eine neue Farbe
        // wurde sonst nie auf die Platte geschrieben und fehlte offline.
        hasher.combine(allTags)
        hasher.combine(allCorrespondents)
        hasher.combine(allDocTypes)
        hasher.combine(allCustomFields)
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
        // Was schon vor dem Laden im Speicher lag, stammt aus dieser Sitzung — ein Import aus
        // der Share-Extension, eine Änderung, eine frische Serverantwort. Es ist neuer als der
        // Plattenstand und darf von ihm nicht überschrieben werden.
        let knownUploads = Set(snapshot.pendingUploads.map(\.id))
        let knownEdits = Set(snapshot.pendingEdits.map(\.id))
        let knownFilters = Set(snapshot.savedFilters.map(\.id))
        let newUploads = pendingUploads.filter { !knownUploads.contains($0.id) }
        let newEdits = pendingEdits.filter { !knownEdits.contains($0.id) }
        let newFilters = savedFilters.filter { !knownFilters.contains($0.id) }

        pendingUploads = snapshot.pendingUploads + newUploads
        pendingEdits   = snapshot.pendingEdits + newEdits
        savedFilters   = snapshot.savedFilters + newFilters
        if documents.isEmpty         { documents         = snapshot.documents }
        if allTags.isEmpty           { allTags           = snapshot.tags }
        if allCorrespondents.isEmpty { allCorrespondents = snapshot.correspondents }
        if allDocTypes.isEmpty       { allDocTypes       = snapshot.docTypes }
        if allCustomFields.isEmpty   { allCustomFields   = snapshot.customFields }
        diskStateAccountId = snapshot.accountId

        reApplyPendingEdits()
        updateFilteredDocs()
        if !newUploads.isEmpty || !newEdits.isEmpty || !newFilters.isEmpty { saveQueues() }
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

    /// Alle Tags nach Eltern gruppiert und sortiert — einmal statt einmal je Knoten.
    private func tagChildrenIndex() -> [Int?: [Tag]] {
        Dictionary(grouping: allTags, by: \.parent)
            .mapValues { $0.sorted { $0.safeName.localizedCompare($1.safeName) == .orderedAscending } }
    }

    /// Flache Liste mit Tiefenangabe für eingerückte Darstellung.
    func hierarchicalTags() -> [(tag: Tag, depth: Int)] {
        var result: [(Tag, Int)] = []
        // Vorher lief für jeden Knoten ein Filter- und Sortierlauf über alle Tags (O(T²)), bei
        // jeder Body-Auswertung der Tag-Liste.
        let children = tagChildrenIndex()
        var visited = Set<Int>()
        func walk(parent: Int?, depth: Int) {
            for tag in children[parent] ?? [] {
                // Schutz gegen zyklische Eltern-Verweise vom Server.
                guard visited.insert(tag.id).inserted else { continue }
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
        let epoch = accountEpoch
        if let items = try? await api.fetchTrash(), isCurrent(epoch) { trashedDocs = items }
    }

    func restoreFromTrash(ids: [Int]) {
        let epoch = accountEpoch
        Task {
            guard let api = api else { return }
            do {
                try await api.restoreFromTrash(ids: ids)
            } catch {
                // Vorher `try?`: Die App meldete „Wiederhergestellt", auch wenn nichts passiert war.
                if isCurrent(epoch) { reportBulkResult(error.localizedDescription, failed: true) }
                return
            }
            guard isCurrent(epoch) else { return }
            await loadTrash()
            await reloadVisible()
            showSuccessToast("Wiederhergestellt")
            registerReviewEvent()
        }
    }

    func emptyTrash(ids: [Int]) {
        let epoch = accountEpoch
        Task {
            guard let api = api else { return }
            do {
                try await api.emptyTrash(ids: ids)
            } catch {
                if isCurrent(epoch) { reportBulkResult(error.localizedDescription, failed: true) }
                return
            }
            guard isCurrent(epoch) else { return }
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
        let epoch = accountEpoch
        if let v = try? await api.fetchSavedViews(), isCurrent(epoch) {
            serverViews = v
            migrateLocalFiltersToServer()
        }
    }

    /// Übersetzt eine Server-View in unseren lokalen Filterzustand.
    func parse(_ view: SavedView) -> ParsedView {
        var p = ParsedView()
        for rule in view.filterRules {
            guard let raw = rule.value else { continue }
            switch rule.ruleType {
            case FilterRuleType.correspondent: p.corr = Int(raw)
            case FilterRuleType.documentType:  p.type = Int(raw)
            case FilterRuleType.hasTagAll:     p.tag = Int(raw)
            case FilterRuleType.createdAfter:
                if let d = DateFormatting.parseAPIDate(String(raw.prefix(10))) { p.dateFilter = .custom; p.customStart = d }
            case FilterRuleType.createdBefore:
                if let d = DateFormatting.parseAPIDate(String(raw.prefix(10))) { p.dateFilter = .custom; p.customEnd = d }
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

        // `DateFormatting.apiDate` statt eines eigenen `DateFormatter` ohne feste Locale und
        // Kalender (falsches Jahr bei buddhistischem oder japanischem Kalender).
        let cal = Calendar.current
        switch dateFilter {
        case .all: break
        case .lastMonth:
            if let d = cal.date(byAdding: .month, value: -1, to: Date()) {
                rules.append(["rule_type": FilterRuleType.createdAfter, "value": DateFormatting.apiDate(d)])
            }
        case .thisYear:
            if let d = cal.date(from: cal.dateComponents([.year], from: Date())) {
                rules.append(["rule_type": FilterRuleType.createdAfter, "value": DateFormatting.apiDate(d)])
            }
        case .custom:
            rules.append(["rule_type": FilterRuleType.createdAfter, "value": DateFormatting.apiDate(start)])
            rules.append(["rule_type": FilterRuleType.createdBefore, "value": DateFormatting.apiDate(end)])
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
        let epoch = accountEpoch
        Task {
            if let view = try? await api.createSavedView(name: name, sortField: s.field, sortReverse: s.reverse, rules: rules),
               isCurrent(epoch) {
                serverViews.append(view)
                showSuccessToast("Ansicht gespeichert")
                registerReviewEvent()
            }
        }
    }

    func deleteServerView(id: Int) {
        let epoch = accountEpoch
        Task {
            guard let api = api else { return }
            do {
                try await api.deleteSavedView(id: id)
            } catch {
                // Vorher verschwand die Ansicht auch dann aus der Leiste, wenn der Server sie behielt.
                if isCurrent(epoch) { reportBulkResult(error.localizedDescription, failed: true) }
                return
            }
            guard isCurrent(epoch) else { return }
            serverViews.removeAll { $0.id == id }
        }
    }

    /// Läuft die Übernahme gerade? `syncMetadata` und `loadSavedViews` stoßen sie beide an.
    private var isMigratingFilters = false

    /// Hebt bestehende lokale Filter einmalig auf den Server und nimmt sie danach aus der
    /// lokalen Liste — nur die, die der Server tatsächlich angenommen hat.
    private func migrateLocalFiltersToServer() {
        guard !savedFilters.isEmpty, !isDemoMode, !isMigratingFilters,
              let api = api, let accountId = activeAccountId else { return }
        isMigratingFilters = true
        let toMigrate = savedFilters
        let epoch = accountEpoch
        Task {
            defer { isMigratingFilters = false }
            var migrated: Set<UUID> = []
            for f in toMigrate {
                let rules = buildRules(tag: f.tag, corr: f.correspondent, type: f.type,
                                       dateFilter: f.dateFilter, start: Date(), end: Date())
                if let view = try? await api.createSavedView(name: f.name, sortField: "created", sortReverse: true, rules: rules) {
                    migrated.insert(f.id)
                    if isCurrent(epoch) { serverViews.append(view) }
                }
            }
            guard isCurrent(epoch) else {
                PersistenceService.removeQueued(SavedFilter.self, ids: migrated,
                                                filename: "savedfilters.json", accountId: accountId)
                return
            }
            savedFilters.removeAll { migrated.contains($0.id) }
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

    /// Widerruft einen Freigabe-Link. Liefert `nil` bei Erfolg, sonst den Grund.
    ///
    /// Vorher verschluckte `try?` jeden Fehler, und die Ansicht nahm den Link trotzdem aus der
    /// Liste. Offline oder ohne Berechtigung blieb der öffentliche Link damit gültig, während
    /// der Nutzer ihn für widerrufen hielt.
    func deleteShareLink(id: Int) async -> String? {
        guard let api = api, !isDemoMode else { return "Kein Server verbunden." }
        do {
            try await api.deleteShareLink(id: id)
            return nil
        } catch APIError.serverError(404) {
            // Schon weg — genau das, was der Nutzer wollte.
            return nil
        } catch {
            return error.localizedDescription
        }
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
                if hasRetryableQueueItems { sync(silent: true) }
            }
        }
    }

    // MARK: - Clear

    func clearLocalData() {
        for account in accounts {
            UserDefaults.standard.removeObject(forKey: uploadRulesKey(account.id))
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
            // Proxy-Geheimnisse und privater Schlüssel des Client-Zertifikats gehören beim
            // Abmelden genauso vom Gerät wie der Token.
            ServerCredentials.removeAll(for: PaperlessAPI.normalizedBase(account.serverUrl))
        }
        invalidateTokenCache()
        beginNewAccountEpoch()
        uploadRules = []
        accounts = []
        activeAccountId = nil
        diskStateAccountId = nil
        diskLoadTask = nil
        ImageCache.shared.setAccount(nil)
        AccountService.save([])
        AccountService.setActiveId(nil)
        isDemoMode = false
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []; allCustomFields = []; trashedDocs = []; serverViews = []
        pendingUploads = []; pendingEdits = []; cachedCount = 0; storageSize = "0 MB"; lastSyncError = nil
        PersistenceService.clearAll()
        ImageCache.shared.clearAll()
        // Auch HTTP-Antworten, die `URLSession` zwischengespeichert hat (Vorschaubilder, Listen).
        URLCache.shared.removeAllCachedResponses()
        clearSpotlightIndex()
        WidgetDataService.clearContent()
        WidgetCenter.shared.reloadAllTimelines()
        autoSyncTask?.cancel()
    }

    // MARK: - Import

    /// Übergibt die nächste Datei aus Share-Extension oder Kurzbefehl an das Importformular.
    ///
    /// Immer nur eine: Das Formular zeigt genau eine Datei. Ist gerade eine offen, wartet der
    /// Rest in der App Group und kommt nach dem Schließen dran.
    func importNextSharedFile() {
        guard incomingUploadContainer == nil, let next = SharedImports.takeNext() else { return }
        handleImportData(data: next.data, filename: next.filename)
    }

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
        beginNewAccountEpoch()
        accounts = [demoAccount]
        activeAccountId = demoAccount.id
        // Frisches Konto ohne Plattenstand — es gibt nichts zu laden, was überschrieben würde.
        diskLoadTask = nil
        diskStateAccountId = demoAccount.id
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
        let enabled = UserDefaults(suiteName: "group.com.Thomas.paperless")?.object(forKey: "widget_enabled") as? Bool ?? true
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


    // MARK: - Toast

    func showSuccessToast(_ msg: String) {
        uploadSuccessMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if uploadSuccessMessage == msg { uploadSuccessMessage = nil }
        }
    }
}
