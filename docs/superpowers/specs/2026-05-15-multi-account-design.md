# Multi-Account Support — Design Spec
**Datum:** 2026-05-15  
**Status:** Genehmigt

---

## Übersicht

Mehrere Server-Konten (auch mehrere Benutzer pro Server) in einer App-Installation. Konten werden in den Einstellungen verwaltet — hinzufügen, wechseln, löschen. Jedes Konto hat eigenen Token (Keychain) und eigenen Offline-Speicher. Der bestehende API-Code bleibt unverändert.

---

## Architektur

Vier geänderte Dateien, eine neue View:

| Datei | Änderung |
|-------|----------|
| `Paperless TeDi/Store/AppStore.swift` | `accounts: [Account]`, `activeAccountId`, computed `serverUrl`/`username` |
| `Paperless TeDi/Services/KeychainService.swift` | Key-Schema auf `serverUrl\|username` umstellen + Migration |
| `Paperless TeDi/Services/PersistenceService.swift` | Per-Account-Subdirectory + Migration |
| `Paperless TeDi/Views/Auth/LoginView.swift` | `LoginMode` enum (`.initial` / `.addAccount`) |
| `Paperless TeDi/Views/Settings/AccountsView.swift` | NEU — Liste, Wechseln, Hinzufügen, Löschen |

---

## Account-Modell

```swift
struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var serverUrl: String
    var username: String
}
```

Kein `displayName` — `username @ serverUrl` reicht als Anzeige.

---

## AppStore

### Neue Properties

```swift
@Published var accounts: [Account] = []          // persisted via UserDefaults JSON
@Published var activeAccountId: UUID? = nil       // persisted via UserDefaults
```

### Computed Properties (bestehende API-Aufrufe bleiben unverändert)

```swift
var activeAccount: Account? {
    accounts.first { $0.id == activeAccountId }
}

var serverUrl: String { activeAccount?.serverUrl ?? "" }
var username: String { activeAccount?.username ?? "" }
```

### Methoden

```swift
func addAccount(_ account: Account)
// Fügt Account hinzu, setzt als aktiv, leert Dokumente/Tags/Korrespondenten

func switchAccount(to id: UUID)
// Setzt activeAccountId, leert documents/tags/correspondents, lädt neu

func removeAccount(id: UUID)
// Löscht Account, zugehörigen Keychain-Token und Offline-Dateien (async)
// Wenn aktiv: wechselt zu erstem verbleibendem Account oder setzt auf nil
```

### Migration beim App-Start

Wenn `accounts` leer UND altes `UserDefaults["serverUrl"]` vorhanden:
```swift
let legacy = Account(id: UUID(), serverUrl: oldServerUrl, username: oldUsername)
accounts = [legacy]
activeAccountId = legacy.id
// alte @AppStorage-Werte löschen
```

---

## KeychainService

### Key-Schema

- Alt: `"paperless-token-\(serverUrl)"`
- Neu: `"paperless-token-\(serverUrl)|\(username)"`

### API

```swift
static func saveToken(_ token: String, for serverUrl: String, username: String)
static func loadToken(for serverUrl: String, username: String) -> String?
static func deleteToken(for serverUrl: String, username: String)
```

Bestehende Signaturen (`saveToken(_:for:)` mit nur `serverUrl`) werden durch neue ersetzt. `AppStore` ruft immer mit `activeAccount?.serverUrl` und `activeAccount?.username` auf.

### Migration

Beim ersten Start nach dem Update:
```swift
// In AppStore.migrate() oder KeychainService.migrateIfNeeded()
if let oldToken = loadToken(for: serverUrl),  // alter Key (nur serverUrl)
   !username.isEmpty {
    saveToken(oldToken, for: serverUrl, username: username)  // neuer Key
    deleteToken(for: serverUrl)  // alter Key löschen
}
```

---

## PersistenceService

### Verzeichnisstruktur

- Alt: `<Documents>/doc_\(docId).pdf`
- Neu: `<Documents>/accounts/\(accountId)/doc_\(docId).pdf`

### API-Änderung

`docFileURL(for:)` bekommt zusätzlichen Parameter:
```swift
static func docFileURL(for docId: Int, accountId: UUID) -> URL
```

Alle Aufrufe von `PersistenceService.docFileURL` in `AppStore` werden mit `activeAccount!.id` aufgerufen.

### Migration

Beim ersten Start: Falls `<Documents>/doc_*.pdf`-Dateien existieren, aber kein `accounts/`-Verzeichnis:
```swift
// Vorhandene Dateien in accounts/<migratedAccountId>/ verschieben
// Migration einmalig via UserDefaults-Flag "persistenceMigrated_v2"
```

---

## UI: AccountsView

Erreichbar über Einstellungen-Tab → "Konten".

```
Konten
┌─────────────────────────────────────────┐
│ ✓  thomas @ mein-server.de    [aktiv]   │
│    admin @ server2.local                │
│                                         │
│ + Konto hinzufügen                     │
└─────────────────────────────────────────┘
```

- Tap auf inaktives Konto → `store.switchAccount(to:)` → sofortiger Wechsel, Sheet/View schließt sich
- Swipe-to-delete → `.destructive` Alert: "Konto und gespeicherte Dateien löschen?"
  - Aktives Konto kann nur gelöscht werden wenn ≥ 2 Konten vorhanden
- "Konto hinzufügen" → `LoginView(mode: .addAccount)` als Sheet

---

## LoginView

### LoginMode

```swift
enum LoginMode {
    case initial      // erster Start, kein Konto vorhanden
    case addAccount   // zusätzliches Konto hinzufügen
}
```

### Verhalten je Modus

| | `.initial` | `.addAccount` |
|---|---|---|
| Felder vorausgefüllt | nein | nein |
| Erfolg | `onConnect()` aufrufen | Account zur Liste hinzufügen, Sheet schließen |
| Demo-Button | sichtbar | verborgen |
| FaceID-Toggle | sichtbar | verborgen |

### Signatur

```swift
struct LoginView: View {
    let mode: LoginMode
    let onConnect: () -> Void   // nur für .initial relevant
}
```

---

## Fehlerbehandlung

| Szenario | Verhalten |
|----------|-----------|
| Letztes Konto gelöscht | `activeAccountId = nil` → App zeigt LoginView (`.initial`) |
| Account-Wechsel während Ladevorgang | laufende Tasks werden verworfen, Daten neu geladen |
| Doppelter Account (gleiche serverUrl + username) | Alert: "Dieses Konto ist bereits vorhanden" |
| Migration schlägt fehl | Fehler loggen, App startet trotzdem (leere Account-Liste) |

---

## Nicht im Scope

- FaceID pro Account (ein globaler Toggle bleibt)
- Account umbenennen / Alias vergeben
- Account-Reihenfolge per Drag & Drop ändern
- Automatischer Wechsel basierend auf Netzwerk
- Passwort in der App ändern
