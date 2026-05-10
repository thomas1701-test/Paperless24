# Paperless TeDi — Komplettes Refactoring Design

**Datum:** 2026-05-10  
**Status:** Approved

## Ziele

1. Credentials sicher im iOS Keychain statt UserDefaults
2. API Token statt dauerhafter Basic Auth
3. Code aufteilen (1900-Zeilen-Datei → strukturierte Unterordner)
4. Bugs beheben (dead code, String Identifiable Antipattern)
5. Code-Duplikation eliminieren (MetadataFormSection)
6. Performance (filteredDocs gecacht, Infinite Scroll Pagination)
7. appGroupId als gemeinsame Konstante
8. Typ-Sicherheit (Enums für SortOrder, LayoutStyle, DateFilter)
9. PaperlessDocument nur Codable (kein manuelles JSON parsing)
10. Vollständig async/await Networking

## Architektur

### Schichten

```
Views → AppStore → PaperlessAPI → Paperless NGX Server
                 → PersistenceService → Disk
                 → KeychainService → iOS Keychain
```

### Dateistruktur

```
Paperless TeDi/
├── App/
│   ├── Paperless_TeDiApp.swift
│   └── ContentView.swift           (~30 Zeilen, nur Entry Point)
├── Models/
│   ├── Document.swift              (Codable only, CodingKeys)
│   ├── Tag.swift
│   ├── Correspondent.swift
│   ├── DocumentType.swift
│   ├── Note.swift
│   ├── PendingUpload.swift
│   ├── PendingEdit.swift
│   └── Enums.swift                 (SortOrder, LayoutStyle, DateFilter, AppState)
├── Services/
│   ├── PaperlessAPI.swift          (async/await, Token Auth, Pagination)
│   ├── KeychainService.swift       (native SecItem API)
│   └── PersistenceService.swift    (Disk I/O)
├── Store/
│   └── AppStore.swift              (@MainActor ObservableObject)
├── Helpers/
│   ├── AppConstants.swift          (appGroupId, appVersion — Shared Target)
│   ├── ImageCache.swift
│   └── Color+Hex.swift
└── Views/
    ├── Auth/
    │   ├── WelcomeView.swift
    │   └── LoginView.swift
    ├── Documents/
    │   ├── MainDocView.swift
    │   ├── DocumentDetailView.swift
    │   ├── DocumentCard.swift
    │   └── DocumentRow.swift
    ├── Upload/
    │   └── UploadDocumentView.swift
    ├── Edit/
    │   └── EditDocumentView.swift
    ├── Settings/
    │   ├── SettingsView.swift
    │   ├── TagListView.swift
    │   ├── CorrespondentListView.swift
    │   ├── DocTypeListView.swift
    │   ├── PendingQueueView.swift
    │   ├── OfflineDocsView.swift
    │   └── ChangelogView.swift
    └── Shared/
        ├── MetadataFormSection.swift
        ├── AuthImage.swift
        ├── PDFKitView.swift
        ├── ScannerView.swift
        ├── PhotoPicker.swift
        ├── ShareSheet.swift
        ├── DashboardItem.swift
        └── SimpleInputSheet.swift
```

## Authentifizierung

### Token-Flow (Option C)

1. Erster Login: Basic Auth → POST /api/token/ → Token erhalten
2. Token im Keychain speichern (server-spezifisch)
3. Alle folgenden Requests: `Authorization: Token <token>`
4. 401-Response → Keychain leeren → Login-Screen

### KeychainService

Native `SecItem` API, kein externes Framework.  
Speichert Token unter dem Key `paperless-token-<serverUrl>`.

### Was wo gespeichert wird

- **@AppStorage:** serverUrl, username, appearanceMode, useFaceID, layoutStyle, sortOrder
- **Keychain:** API Token
- **Nie persistiert:** Passwort (nur im Speicher während Login)

## Pagination

- page_size=25 pro Request
- Infinite Scroll: letztes Element lädt nächste Seite
- Suche: setzt auf Seite 1 zurück
- Offline-Suche: clientseitig auf gecachten Dokumenten

## AppStore

`@MainActor ObservableObject`. Koordiniert API + Persistence.

Wichtige Properties:
- `@Published var documents: [Document]` — alle geladenen Dokumente
- `@Published var filteredDocs: [Document]` — gecachter Filter/Sort-Output
- `@Published var hasNextPage: Bool`
- `@Published var isLoadingMore: Bool`

Pagination-Methoden:
- `func loadFirstPage() async`
- `func loadNextPage() async`

## Enums

```swift
enum SortOrder: Int, CaseIterable {
    case dateDesc, dateAsc, addedDesc, addedAsc, titleAZ, senderAZ
}
enum LayoutStyle: String { case grid, list }
enum DateFilter: String, CaseIterable { case all, lastMonth, thisYear, custom }
enum AppState { case loading, welcome, login, main }
```

## Bug Fixes

| Bug | Fix |
|-----|-----|
| `if self.lastSyncError == nil { self.lastSyncError = nil }` | Gelöscht |
| `extension String: Identifiable` | Gelöscht, `\.self` in ForEach |
| `appGroupId` doppelt hart-kodiert | `AppConstants.swift` mit Shared Target |
| `var body = [...]` nie neu assigned | `let body = [...]` |
| `PaperlessDocument` doppeltes JSON Parsing | Nur Codable + CodingKeys |

## Code-Qualität

- `MetadataFormSection`: Gemeinsamer View für Correspondent/Typ/Tag-Picker in Upload und Edit
- AI-Analyse-Logik: Gemeinsame Funktion, von beiden Views genutzt
- Keine DispatchQueue.main.async mehr (durch @MainActor ersetzt)
- Alle URLSession-Calls durch async/await ersetzt

## Share Extension

`AppConstants.swift` bekommt Shared Target Membership für `PaperlessShare`.  
`ShareViewController.swift` importiert aus AppConstants statt eigener Konstante.
