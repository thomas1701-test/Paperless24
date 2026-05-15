# Multi-Account Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mehrere Server-Konten (inkl. mehrere Benutzer pro Server) unterstützen — Account-Wechsel über Einstellungen, eigener Offline-Speicher pro Konto.

**Architecture:** Ein neues `Account`-Modell (UUID + serverUrl + username) ersetzt die bisherigen `@AppStorage("serverUrl")`/`@AppStorage("username")` in `AppStore`. `KeychainService` wechselt auf einen Composite-Key `serverUrl|username`. `PersistenceService` speichert PDF-Dateien und JSON-Daten in `accounts/<uuid>/`. Eine neue `AccountsView` in den Einstellungen ermöglicht Wechseln, Hinzufügen und Löschen von Konten. Migration beim ersten Start überführt bestehende Daten automatisch.

**Tech Stack:** SwiftUI, UserDefaults, Keychain (Security framework), FileManager

---

## File Map

| Datei | Status | Verantwortung |
|-------|--------|---------------|
| `Paperless TeDi/Services/AccountService.swift` | Neu | `Account`-Struct, UserDefaults-Persistenz der Account-Liste |
| `Paperless TeDi/Services/KeychainService.swift` | Ändern | Composite-Key `serverUrl\|username`, Legacy-Migration |
| `Paperless TeDi/Services/PersistenceService.swift` | Ändern | Per-Account-Verzeichnisse, account-aware Varianten aller Methoden |
| `Paperless TeDi/Store/AppStore.swift` | Ändern | `accounts`/`activeAccountId` statt `@AppStorage`, alle betroffenen Methoden |
| `Paperless TeDi/Views/Auth/LoginView.swift` | Ändern | `LoginMode` enum, lokale State-Variablen statt `$store.serverUrl` |
| `Paperless TeDi/Views/Settings/AccountsView.swift` | Neu | Account-Liste, Wechseln, Hinzufügen (Sheet), Löschen |
| `Paperless TeDi/Views/Settings/SettingsView.swift` | Ändern | Konten-Section hinzufügen, Logout-Button anpassen |
| `Paperless TeDi/App/ContentView.swift` | Ändern | `checkLogin()` und `onLogout`-Closure anpassen |

---

## Task 1: AccountService — Account-Modell und Persistenz

**Files:**
- Create: `Paperless TeDi/Services/AccountService.swift`

- [ ] **Schritt 1: Datei anlegen**

```swift
import Foundation

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var serverUrl: String
    var username: String
}

enum AccountService {
    private static let accountsKey = "accounts_v2"
    private static let activeIdKey = "activeAccountId"

    static func load() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    static func save(_ accounts: [Account]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: accountsKey)
    }

    static func activeId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setActiveId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }
}
```

- [ ] **Schritt 2: Build prüfen**

Xcode → `⌘B`. Keine Fehler erwartet (neue Datei, keine Abhängigkeiten).

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Services/AccountService.swift"
git commit -m "feat: Account-Modell und AccountService"
```

---

## Task 2: KeychainService — Composite-Key

**Files:**
- Modify: `Paperless TeDi/Services/KeychainService.swift`

Bisherige Signatur `saveToken(_:for:)` / `loadToken(for:)` / `deleteToken(for:)` mit einem `server`-Parameter werden ersetzt. Legacy-Methoden für Migration bleiben.

- [ ] **Schritt 1: KeychainService vollständig ersetzen**

```swift
import Foundation
import Security

enum KeychainService {
    private static func key(for serverUrl: String, username: String) -> String {
        "paperless-token-\(serverUrl)|\(username)"
    }

    static func saveToken(_ token: String, for serverUrl: String, username: String) {
        let data = Data(token.utf8)
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken(for serverUrl: String, username: String) -> String? {
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken(for serverUrl: String, username: String) {
        let k = key(for: serverUrl, username: username)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Migration: liest alten Single-User-Token (Key = nur serverUrl)
    static func loadLegacyToken(for serverUrl: String) -> String? {
        let k = "paperless-token-\(serverUrl)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteLegacyToken(for serverUrl: String) {
        let k = "paperless-token-\(serverUrl)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: k
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Schritt 2: Build prüfen**

`⌘B` — erwartet Compilerfehler an allen Stellen, die die alten Signaturen aufrufen (AppStore, ContentView, LoginView, SettingsView). Das ist erwartet und wird in Task 4–7 behoben.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Services/KeychainService.swift"
git commit -m "feat: KeychainService Composite-Key serverUrl|username"
```

---

## Task 3: PersistenceService — Per-Account-Speicher

**Files:**
- Modify: `Paperless TeDi/Services/PersistenceService.swift`

Alte account-lose Methoden (`docFileURL(for:)`, `fileExists(docId:)`, `deleteDocFile(docId:)`) werden entfernt und durch account-aware Varianten ersetzt. `clearAll()` bleibt unverändert. Neue Methoden für JSON-Datenpfade und Migration werden hinzugefügt.

- [ ] **Schritt 1: PersistenceService vollständig ersetzen**

```swift
import Foundation

enum PersistenceService {
    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // MARK: - JSON Data (account-agnostic, für globale Einstellungen — nicht mehr verwendet)

    static func save<T: Encodable>(_ value: T, to filename: String) {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(value).write(to: url(filename))
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        guard let data = try? Data(contentsOf: url(filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Per-Account JSON Data

    static func accountDataURL(for accountId: UUID, filename: String) -> URL {
        let dir = url("accounts/\(accountId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func save<T: Encodable>(_ value: T, toURL fileURL: URL) {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(value).write(to: fileURL)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, fromURL fileURL: URL) -> T? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Per-Account PDF Files

    static func docFileURL(for docId: Int, accountId: UUID) -> URL {
        let dir = url("accounts/\(accountId.uuidString)/docs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("doc_\(docId).pdf")
    }

    static func fileExists(docId: Int, accountId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: docFileURL(for: docId, accountId: accountId).path)
    }

    static func deleteDocFile(docId: Int, accountId: UUID) {
        try? FileManager.default.removeItem(at: docFileURL(for: docId, accountId: accountId))
    }

    static func deleteAccountFiles(accountId: UUID) {
        try? FileManager.default.removeItem(at: url("accounts/\(accountId.uuidString)"))
    }

    static func calculateStorage(accountId: UUID) -> (sizeString: String, cachedCount: Int) {
        var totalBytes: Int64 = 0
        var count = 0
        let docsDir = url("accounts/\(accountId.uuidString)/docs")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += Int64(size)
                }
                if file.lastPathComponent.hasPrefix("doc_") { count += 1 }
            }
        }
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let subs = try? FileManager.default.subpathsOfDirectory(atPath: cacheDir.path) {
            for path in subs {
                if let attrs = try? FileManager.default.attributesOfItem(
                    atPath: cacheDir.appendingPathComponent(path).path
                ), let size = attrs[.size] as? Int64 {
                    totalBytes += size
                }
            }
        }
        return (String(format: "%.2f MB", Double(totalBytes) / 1_048_576), count)
    }

    // MARK: - Migration

    static func legacyDataURL(_ filename: String) -> URL {
        url(filename)
    }

    static func migrateLegacyDocFiles(to accountId: UUID) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil
              ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("doc_") && file.pathExtension == "pdf" {
            let stem = file.deletingPathExtension().lastPathComponent.dropFirst(4) // "doc_123" → "123"
            if let id = Int(stem) {
                let dest = docFileURL(for: id, accountId: accountId)
                try? FileManager.default.moveItem(at: file, to: dest)
            }
        }
    }

    // MARK: - Global

    static func clearAll() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
```

- [ ] **Schritt 2: Build prüfen**

`⌘B` — erwartet Compilerfehler in AppStore.swift an den Stellen, die alte PersistenceService-Signaturen verwenden. Wird in Task 4 behoben.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Services/PersistenceService.swift"
git commit -m "feat: PersistenceService per-Account-Verzeichnisse und Migration"
```

---

## Task 4: AppStore — Account-Modell, Migration, alle Methoden

**Files:**
- Modify: `Paperless TeDi/Store/AppStore.swift`

Wichtige Kontexte aus der bestehenden Datei (vor dem Ändern lesen):
- Zeilen 46–48: `@AppStorage("serverUrl")` und `@AppStorage("username")` — werden entfernt
- Zeilen 63–66: `private var api` — wird auf Composite-Key-Lookup umgestellt
- Zeilen 75–87: `init()` — bekommt Account-Lade- + Migrationslogik
- Zeilen 91–101: `makeServerBase()`, `thumbnailURL()`, `authToken()` — kleinere Anpassungen
- Zeile 159: `KeychainService.deleteToken(for: serverUrl)` — auf neue Signatur
- Zeile 425: `PersistenceService.deleteDocFile(docId: id)` — auf neue Signatur
- Zeilen 490–491: `fileExists(docId:)` und `localFileURL(for:)` — auf neue Signatur
- Zeilen 494–500: `loadPDFData(for:)` — verwendet `localFileURL`, passt sich automatisch an
- Zeilen 503–506: `deleteLocalFile(docId:)` — auf neue Signatur
- Zeilen 544–551: `calculateStorage()` — auf neue Signatur
- Zeilen 603–622: `saveToDisk()` / `loadFromDisk()` — auf URL-Variante umstellen
- Zeilen 653–660: `clearLocalData()` — Accounts leeren
- Zeilen 686–696: `setupDemoData()` — Demo-Account anlegen

- [ ] **Schritt 1: Settings-Block ersetzen**

Ersetze in `AppStore.swift` den bestehenden Settings-Block (enthält `@AppStorage("serverUrl")` und `@AppStorage("username")`):

```swift
    // MARK: - Settings

    @AppStorage("serverUrl") var serverUrl = ""
    @AppStorage("username") var username = ""
    @AppStorage("isDemoMode") var isDemoMode = false
```

durch:

```swift
    // MARK: - Settings

    @AppStorage("isDemoMode") var isDemoMode = false

    @Published var accounts: [Account] = []
    @Published var activeAccountId: UUID? = nil

    var activeAccount: Account? {
        accounts.first { $0.id == activeAccountId }
    }

    var serverUrl: String { activeAccount?.serverUrl ?? "" }
    var username: String { activeAccount?.username ?? "" }
```

Dann ersetze den bestehenden `private var api`-Block:

```swift
    private var api: PaperlessAPI? {
        guard let token = KeychainService.loadToken(for: serverUrl), !serverUrl.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: serverUrl, token: token)
    }
```

durch:

```swift
    private var api: PaperlessAPI? {
        guard let account = activeAccount,
              let token = KeychainService.loadToken(for: account.serverUrl, username: account.username),
              !account.serverUrl.isEmpty else { return nil }
        return PaperlessAPI(serverUrl: account.serverUrl, token: token)
    }
```

- [ ] **Schritt 2: init() ersetzen**

Ersetze die gesamte `init()`-Methode (Zeilen 75–87):

```swift
    init() {
        var loadedAccounts = AccountService.load()
        var loadedActiveId = AccountService.activeId()

        // Migration: Single-Account → Multi-Account
        if loadedAccounts.isEmpty {
            let legacyUrl = UserDefaults.standard.string(forKey: "serverUrl") ?? ""
            let legacyUser = UserDefaults.standard.string(forKey: "username") ?? ""
            if !legacyUrl.isEmpty, !legacyUser.isEmpty {
                let account = Account(id: UUID(), serverUrl: legacyUrl, username: legacyUser)
                if let token = KeychainService.loadLegacyToken(for: legacyUrl) {
                    KeychainService.saveToken(token, for: legacyUrl, username: legacyUser)
                    KeychainService.deleteLegacyToken(for: legacyUrl)
                }
                PersistenceService.migrateLegacyDocFiles(to: account.id)
                for filename in ["documents.json", "tags.json", "corrs.json", "types.json",
                                 "pending.json", "edits.json", "savedfilters.json"] {
                    let oldURL = PersistenceService.legacyDataURL(filename)
                    let newURL = PersistenceService.accountDataURL(for: account.id, filename: filename)
                    try? FileManager.default.moveItem(at: oldURL, to: newURL)
                }
                loadedAccounts = [account]
                loadedActiveId = account.id
                AccountService.save(loadedAccounts)
                AccountService.setActiveId(loadedActiveId)
                UserDefaults.standard.removeObject(forKey: "serverUrl")
                UserDefaults.standard.removeObject(forKey: "username")
            }
        }

        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
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
```

- [ ] **Schritt 3: API-Zugriff-Methoden aktualisieren**

Ersetze `authToken()` (aktuell Zeile ~100):

```swift
    func authToken() -> String {
        guard let account = activeAccount else { return "" }
        return KeychainService.loadToken(for: account.serverUrl, username: account.username) ?? ""
    }

    func hasValidToken() -> Bool {
        guard let account = activeAccount else { return false }
        return KeychainService.loadToken(for: account.serverUrl, username: account.username) != nil
    }
```

- [ ] **Schritt 4: Account-Management-Methoden hinzufügen**

Füge nach `hasValidToken()` hinzu:

```swift
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
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []
        pendingUploads = []; pendingEdits = []; savedFilters = []
        autoSyncTask?.cancel()
        if KeychainService.loadToken(for: serverUrl, username: username) != nil {
            loadFromDisk(for: id)
            calculateStorage()
            startAutoSync()
        }
    }

    func removeAccount(id: UUID) {
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
                documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []
                pendingUploads = []; pendingEdits = []; savedFilters = []
                autoSyncTask?.cancel()
            }
        }
    }
```

- [ ] **Schritt 5: `loadFirstPage()` Keychain-Delete aktualisieren**

Suche in `loadFirstPage()` nach `KeychainService.deleteToken(for: serverUrl)` und ersetze durch:

```swift
            } catch APIError.unauthorized {
                if let account = activeAccount {
                    KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                }
                lastSyncError = "Sitzung abgelaufen, bitte neu einloggen"
                needsReLogin = true
                isSyncing = false
                return
```

- [ ] **Schritt 6: Offline-/Download-Methoden aktualisieren**

Ersetze `fileExists(docId:)` und `localFileURL(for:)`:

```swift
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
```

- [ ] **Schritt 7: `deleteLocalFile(docId:)` aktualisieren**

```swift
    func deleteLocalFile(docId: Int) {
        guard let id = activeAccountId else { return }
        PersistenceService.deleteDocFile(docId: docId, accountId: id)
        calculateStorage()
    }
```

- [ ] **Schritt 8: `deleteDocument(id:)` aktualisieren**

Suche `PersistenceService.deleteDocFile(docId: id)` in `deleteDocument` und ersetze die gesamte Methode:

```swift
    func deleteDocument(id: Int) {
        Task {
            guard let api = api, let accountId = activeAccountId else { return }
            try? await api.deleteDocument(id: id)
            documents.removeAll { $0.id == id }
            updateFilteredDocs()
            PersistenceService.deleteDocFile(docId: id, accountId: accountId)
        }
    }
```

- [ ] **Schritt 9: `calculateStorage()` aktualisieren**

```swift
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
```

- [ ] **Schritt 10: `saveToDisk()` und `loadFromDisk()` aktualisieren**

Ersetze `saveToDisk()`:

```swift
    func saveToDisk() {
        guard let id = activeAccountId else { return }
        PersistenceService.save(documents,        toURL: PersistenceService.accountDataURL(for: id, filename: "documents.json"))
        PersistenceService.save(allTags,          toURL: PersistenceService.accountDataURL(for: id, filename: "tags.json"))
        PersistenceService.save(allCorrespondents,toURL: PersistenceService.accountDataURL(for: id, filename: "corrs.json"))
        PersistenceService.save(allDocTypes,      toURL: PersistenceService.accountDataURL(for: id, filename: "types.json"))
        PersistenceService.save(pendingUploads,   toURL: PersistenceService.accountDataURL(for: id, filename: "pending.json"))
        PersistenceService.save(pendingEdits,     toURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))
        PersistenceService.save(savedFilters,     toURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json"))
    }
```

Ersetze `loadFromDisk()` durch eine Variante mit `id`-Parameter (bisherige Aufrufe in `init()` und `switchAccount()` schon angepasst):

```swift
    func loadFromDisk(for id: UUID) {
        documents       = PersistenceService.load([Document].self,     fromURL: PersistenceService.accountDataURL(for: id, filename: "documents.json"))    ?? []
        allTags         = PersistenceService.load([Tag].self,           fromURL: PersistenceService.accountDataURL(for: id, filename: "tags.json"))         ?? []
        allCorrespondents = PersistenceService.load([Correspondent].self, fromURL: PersistenceService.accountDataURL(for: id, filename: "corrs.json"))      ?? []
        allDocTypes     = PersistenceService.load([DocumentType].self,  fromURL: PersistenceService.accountDataURL(for: id, filename: "types.json"))        ?? []
        pendingUploads  = PersistenceService.load([PendingUpload].self, fromURL: PersistenceService.accountDataURL(for: id, filename: "pending.json"))      ?? []
        pendingEdits    = PersistenceService.load([PendingEdit].self,   fromURL: PersistenceService.accountDataURL(for: id, filename: "edits.json"))        ?? []
        savedFilters    = PersistenceService.load([SavedFilter].self,   fromURL: PersistenceService.accountDataURL(for: id, filename: "savedfilters.json")) ?? []
        updateFilteredDocs()
    }
```

- [ ] **Schritt 11: `clearLocalData()` aktualisieren**

```swift
    func clearLocalData() {
        for account in accounts {
            KeychainService.deleteToken(for: account.serverUrl, username: account.username)
        }
        accounts = []
        activeAccountId = nil
        AccountService.save([])
        AccountService.setActiveId(nil)
        isDemoMode = false
        documents = []; filteredDocs = []; allTags = []; allCorrespondents = []; allDocTypes = []
        pendingUploads = []; pendingEdits = []; cachedCount = 0; storageSize = "0 MB"; lastSyncError = nil
        PersistenceService.clearAll()
        ImageCache.shared.clearCache()
        clearSpotlightIndex()
        autoSyncTask?.cancel()
    }
```

- [ ] **Schritt 12: `setupDemoData()` aktualisieren**

```swift
    func setupDemoData() {
        isDemoMode = true
        let demoAccount = Account(id: UUID(), serverUrl: "demo.local", username: "demo")
        accounts = [demoAccount]
        activeAccountId = demoAccount.id
        AccountService.save(accounts)
        AccountService.setActiveId(demoAccount.id)
        allTags = [Tag(id: 1, name: "Rechnung", color: "#ff0000")]
        allCorrespondents = [Correspondent(id: 1, name: "Amazon")]
        allDocTypes = [DocumentType(id: 1, name: "Rechnung")]
        documents = [Document(id: 1, title: "Demo", content: "Text", created: "2026-01-26",
                              added: nil, correspondent: 1, documentType: 1,
                              archiveSerialNumber: 100, tags: [1])]
        updateFilteredDocs()
        saveToDisk()
    }
```

- [ ] **Schritt 13: Build prüfen**

`⌘B` — Fehler nur noch in `ContentView.swift`, `LoginView.swift`, `SettingsView.swift` erwartet (alte Keychain-Signaturen). Wird in Task 5–7 behoben.

- [ ] **Schritt 14: Commit**

```bash
git add "Paperless TeDi/Store/AppStore.swift"
git commit -m "feat: AppStore auf Multi-Account umgestellt"
```

---

## Task 5: LoginView — LoginMode und lokale State-Variablen

**Files:**
- Modify: `Paperless TeDi/Views/Auth/LoginView.swift`

`serverUrl` und `username` wechseln von `$store.serverUrl`/`$store.username` (gebundene Writes in den Store) zu lokalen `@State`-Variablen. Neuer `mode: LoginMode`-Parameter. Im `.addAccount`-Modus wird nach Erfolg `dismiss()` aufgerufen statt `onConnect()`.

- [ ] **Schritt 1: Gesamte LoginView ersetzen**

```swift
import SwiftUI

enum LoginMode {
    case initial
    case addAccount
}

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @Binding var useFaceID: Bool
    var mode: LoginMode = .initial
    let onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var serverUrl = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var otpRequired = false
    @State private var otpCode = ""
    @State private var showDemoConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Login").font(.largeTitle).bold()
            TextField("Server", text: $serverUrl)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: serverUrl) { _, _ in resetOtp() }
            TextField("Benutzer", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: username) { _, _ in resetOtp() }
            SecureField("Passwort", text: $password)
                .textFieldStyle(.roundedBorder)
                .onChange(of: password) { _, _ in resetOtp() }
            if otpRequired {
                VStack(spacing: 4) {
                    Text("Gib deinen Authentifikator-Code ein")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("6-stelliger Code", text: $otpCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                }
            }
            if mode == .initial {
                Toggle("FaceID", isOn: $useFaceID)
            }
            if isChecking {
                ProgressView()
            } else {
                Button(otpRequired ? "Code bestätigen" : "Login") { login() }
                    .buttonStyle(.borderedProminent)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).font(.caption)
            }
            if mode == .initial {
                Button("Demo") { showDemoConfirm = true }
                    .foregroundColor(.orange)
                    .alert("Demo-Modus", isPresented: $showDemoConfirm) {
                        Button("Abbrechen", role: .cancel) {}
                        Button("Starten") { store.setupDemoData(); onConnect() }
                    } message: {
                        Text("Zeigt Beispieldaten. Es wird keine Verbindung zum Server hergestellt.")
                    }
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func resetOtp() {
        otpRequired = false
        otpCode = ""
    }

    private func login() {
        isChecking = true
        errorMessage = ""
        Task { @MainActor in
            do {
                if !otpRequired {
                    try await PaperlessAPI.checkConnection(
                        serverUrl: serverUrl,
                        username: username,
                        password: password
                    )
                }
                let token = try await PaperlessAPI.fetchToken(
                    serverUrl: serverUrl,
                    username: username,
                    password: password,
                    otp: otpRequired && !otpCode.isEmpty ? otpCode : nil
                )
                let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                KeychainService.saveToken(cleanToken, for: serverUrl, username: username)
                store.isDemoMode = false

                if mode == .addAccount {
                    if store.accounts.contains(where: {
                        $0.serverUrl == serverUrl && $0.username == username
                    }) {
                        errorMessage = "Dieses Konto ist bereits vorhanden"
                        isChecking = false
                        return
                    }
                    let account = Account(id: UUID(), serverUrl: serverUrl, username: username)
                    store.addAccount(account)
                    dismiss()
                } else {
                    let account = Account(id: UUID(), serverUrl: serverUrl, username: username)
                    store.addAccount(account)
                    onConnect()
                }
            } catch APIError.otpRequired {
                otpRequired = true
                errorMessage = ""
            } catch APIError.unauthorized {
                errorMessage = otpRequired ? "Falscher Code" : "Login fehlgeschlagen"
            } catch {
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }
}
```

- [ ] **Schritt 2: Build prüfen**

`⌘B` — Fehler nur noch in `ContentView.swift` und `SettingsView.swift` erwartet.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Views/Auth/LoginView.swift"
git commit -m "feat: LoginView mit LoginMode und lokalen State-Variablen"
```

---

## Task 6: AccountsView — neuer Account-Manager

**Files:**
- Create: `Paperless TeDi/Views/Settings/AccountsView.swift`

- [ ] **Schritt 1: Datei anlegen**

```swift
import SwiftUI

struct AccountsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAddAccount = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            ForEach(store.accounts) { account in
                Button {
                    if account.id != store.activeAccountId {
                        store.switchAccount(to: account.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username).font(.headline)
                            Text(account.serverUrl).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if account.id == store.activeAccountId {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .onDelete { offsets in
                guard let first = offsets.first else { return }
                let account = store.accounts[first]
                guard store.accounts.count > 1 else { return }
                accountToDelete = account
                showDeleteConfirm = true
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
            }
        }
        .navigationTitle("Konten")
        .sheet(isPresented: $showAddAccount) {
            LoginView(useFaceID: .constant(false), mode: .addAccount, onConnect: {})
                .environmentObject(store)
        }
        .alert("Konto löschen", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) { accountToDelete = nil }
            Button("Löschen", role: .destructive) {
                if let account = accountToDelete {
                    store.removeAccount(id: account.id)
                }
                accountToDelete = nil
            }
        } message: {
            if let account = accountToDelete {
                Text("\(account.username) @ \(account.serverUrl) und alle gespeicherten Dateien löschen?")
            }
        }
    }
}
```

- [ ] **Schritt 2: Build prüfen**

`⌘B` — keine Fehler in dieser Datei erwartet.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Views/Settings/AccountsView.swift"
git commit -m "feat: AccountsView"
```

---

## Task 7: SettingsView + ContentView verdrahten

**Files:**
- Modify: `Paperless TeDi/Views/Settings/SettingsView.swift`
- Modify: `Paperless TeDi/App/ContentView.swift`

- [ ] **Schritt 1: SettingsView — Konten-Section hinzufügen**

In `SettingsView.swift`, direkt vor `Section("Verwaltung")` einfügen:

```swift
                Section("Konten") {
                    NavigationLink(destination: AccountsView()) {
                        Label("Konten verwalten", systemImage: "person.2")
                    }
                }
```

- [ ] **Schritt 2: SettingsView — Logout-Button anpassen**

Den bestehenden Block:
```swift
                    Button("Abmelden", role: .destructive) {
                        store.clearLocalData()
                        KeychainService.deleteToken(for: store.serverUrl)
                        onLogout()
                    }
```
ersetzen durch:
```swift
                    Button("Abmelden", role: .destructive) {
                        store.clearLocalData()
                        onLogout()
                    }
```

(`clearLocalData()` löscht jetzt intern alle Tokens aller Konten.)

- [ ] **Schritt 3: ContentView — `checkLogin()` aktualisieren**

Die bestehende `checkLogin()`-Methode:
```swift
    private func checkLogin() {
        guard !store.serverUrl.isEmpty else { appState = .login; return }
        guard KeychainService.loadToken(for: store.serverUrl) != nil else { appState = .login; return }
        if useFaceID { authenticate() } else { appState = .main }
    }
```
ersetzen durch:
```swift
    private func checkLogin() {
        guard !store.serverUrl.isEmpty else { appState = .login; return }
        guard store.hasValidToken() else { appState = .login; return }
        if useFaceID { authenticate() } else { appState = .main }
    }
```

- [ ] **Schritt 4: ContentView — `onLogout`-Closure aktualisieren**

Den bestehenden Aufruf:
```swift
                case .main:     RootTabView(onLogout: { store.serverUrl = ""; appState = .login })
```
ersetzen durch:
```swift
                case .main:     RootTabView(onLogout: { appState = .login })
```

(`store.serverUrl` ist jetzt read-only computed — Zuweisung wäre ein Compilerfehler.)

- [ ] **Schritt 5: ContentView — LoginView-Aufruf pre-fill hinzufügen**

Den bestehenden Aufruf:
```swift
                case .login:    LoginView(useFaceID: $useFaceID, onConnect: { appState = .main })
```
ersetzen durch:
```swift
                case .login:
                    LoginView(
                        useFaceID: $useFaceID,
                        onConnect: { appState = .main },
                        prefillServerUrl: store.serverUrl,
                        prefillUsername: store.username
                    )
```

Damit LoginView die Felder für Re-Login vorausfüllt. Dazu muss `LoginView` einen benutzerdefinierten `init` bekommen.

- [ ] **Schritt 6: LoginView — prefill-Init hinzufügen**

In `Paperless TeDi/Views/Auth/LoginView.swift` die `@State private var serverUrl = ""` und `@State private var username = ""` behalten, aber einen custom `init` ergänzen:

```swift
    init(
        useFaceID: Binding<Bool>,
        mode: LoginMode = .initial,
        onConnect: @escaping () -> Void,
        prefillServerUrl: String = "",
        prefillUsername: String = ""
    ) {
        self._useFaceID = useFaceID
        self.mode = mode
        self.onConnect = onConnect
        self._serverUrl = State(initialValue: prefillServerUrl)
        self._username = State(initialValue: prefillUsername)
    }
```

Und die bestehenden `@State private var serverUrl = ""` und `@State private var username = ""` bleiben als Backing-Storage (werden durch den Init gesetzt).

- [ ] **Schritt 7: Build prüfen**

`⌘B` — keine Fehler erwartet. Alle alten Keychain-Signaturen und `store.serverUrl`-Zuweisungen sind jetzt behoben.

- [ ] **Schritt 8: Commit**

```bash
git add "Paperless TeDi/Views/Settings/SettingsView.swift" \
        "Paperless TeDi/App/ContentView.swift" \
        "Paperless TeDi/Views/Auth/LoginView.swift"
git commit -m "feat: AccountsView in Settings verdrahtet, ContentView und Logout angepasst"
```

---

## Task 8: Manuell testen

- [ ] **Schritt 1: Migrations-Test (bestehende Installation)**

App mit bestehendem Login starten (nicht erst deinstallieren):
- Erwartung: App öffnet sich normal, Dokumente sind sichtbar
- Einstellungen → Konten: ein Konto mit bisherigen Server/Username-Daten ist vorhanden
- Kein erneuter Login erforderlich

- [ ] **Schritt 2: Zweites Konto hinzufügen**

Einstellungen → Konten → „Konto hinzufügen" → gültige Zugangsdaten eines zweiten Servers eingeben → Login
- Erwartung: Sheet schließt sich, in der Konto-Liste erscheinen zwei Konten, das neue ist aktiv (Checkmark)

- [ ] **Schritt 3: Account-Wechsel**

In Konten-Liste auf das erste Konto tippen:
- Erwartung: Checkmark wechselt, Dokumente in der Haupt-Ansicht werden durch die des ersten Kontos ersetzt

- [ ] **Schritt 4: Konto löschen**

Auf einem inaktiven Konto in der Liste nach links wischen → Löschen bestätigen:
- Erwartung: Konto verschwindet aus der Liste; beim aktiven Konto ist Swipe-Delete nicht möglich solange es das einzige Konto ist

- [ ] **Schritt 5: Abmelden (letztes Konto)**

Einstellungen → Abmelden:
- Erwartung: App zeigt Willkommens-/Login-Bildschirm; alle Daten gelöscht

- [ ] **Schritt 6: Frische Installation**

App deinstallieren, neu installieren:
- Erwartung: Willkommens-Bildschirm erscheint; nach Login ein Konto in der Liste

- [ ] **Schritt 7: Finaler Commit**

```bash
git add -A
git commit -m "feat: Multi-Account Support vollständig implementiert"
```
