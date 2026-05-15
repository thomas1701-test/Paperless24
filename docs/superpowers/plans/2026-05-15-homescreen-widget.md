# Homescreen Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein WidgetKit-Homescreen-Widget hinzufügen, das die letzten Dokumente oder eine Statistik-Übersicht aus dem App-Group-Cache anzeigt.

**Architecture:** Die Hauptapp schreibt beim Sync Dokumente und Statistiken in `App Group UserDefaults` (`group.com.Thomas.paperless`). Ein neues `PaperlessWidget`-Target liest diese Daten via `TimelineProvider` und rendert drei Widget-Größen in zwei Modi. Deep Links (`paperlesstedi://document?id=123`) verbinden Widget-Taps mit der App.

**Tech Stack:** SwiftUI, WidgetKit, App Group UserDefaults, `WidgetCenter`

---

## File Map

| Datei | Status | Verantwortung |
|-------|--------|---------------|
| `Paperless TeDi/Services/WidgetDataService.swift` | Neu | Daten in App Group schreiben/lesen |
| `Paperless TeDi/Store/AppStore.swift` | Ändern | Sync ruft WidgetDataService + WidgetCenter auf |
| `Paperless TeDi/Views/Settings/SettingsView.swift` | Ändern | Widget-Einstellungs-Abschnitt |
| `Paperless TeDi/App/Paperless_TeDiApp.swift` | Ändern | Deep-Link `document?id=` handler |
| `PaperlessWidget/PaperlessWidgetBundle.swift` | Neu | Widget Entry Point (`@main`) |
| `PaperlessWidget/PaperlessWidget.swift` | Neu | TimelineProvider + Widget-Konfiguration |
| `PaperlessWidget/WidgetViews.swift` | Neu | SwiftUI Views für 3 Größen × 2 Modi |

---

## Task 1: WidgetDataService

**Files:**
- Create: `Paperless TeDi/Services/WidgetDataService.swift`

- [ ] **Schritt 1: Datei erstellen**

```swift
import Foundation
import WidgetKit

struct WidgetDocument: Codable {
    let id: Int
    let title: String
    let created: String
    let correspondent: String?
}

enum WidgetDataService {
    private static let suiteName = "group.com.Thomas.paperless"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func write(
        docs: [WidgetDocument],
        inboxCount: Int,
        totalCount: Int,
        lastSync: Date,
        enabled: Bool
    ) {
        guard let d = defaults else { return }
        d.set(enabled, forKey: "widget_enabled")
        d.set(inboxCount, forKey: "widget_inbox_count")
        d.set(totalCount, forKey: "widget_total_count")
        d.set(lastSync.timeIntervalSince1970, forKey: "widget_last_sync")
        d.set(try? JSONEncoder().encode(docs), forKey: "widget_documents")
    }

    static func readDocuments() -> [WidgetDocument] {
        guard let d = defaults,
              let data = d.data(forKey: "widget_documents") else { return [] }
        return (try? JSONDecoder().decode([WidgetDocument].self, from: data)) ?? []
    }

    static func readStats() -> (inbox: Int, total: Int, lastSync: Date?) {
        guard let d = defaults else { return (0, 0, nil) }
        let inbox = d.integer(forKey: "widget_inbox_count")
        let total = d.integer(forKey: "widget_total_count")
        let ts = d.double(forKey: "widget_last_sync")
        let lastSync = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return (inbox, total, lastSync)
    }

    static func isEnabled() -> Bool {
        defaults?.bool(forKey: "widget_enabled") ?? true
    }

    static func readMode() -> String {
        defaults?.string(forKey: "widget_mode") ?? "documents"
    }
}
```

- [ ] **Schritt 2: Build prüfen**

In Xcode: `⌘B` — keine Fehler erwartet.

- [ ] **Schritt 3: Commit**

```bash
git add "Paperless TeDi/Services/WidgetDataService.swift"
git commit -m "feat: WidgetDataService für App Group Datenaustausch"
```

---

## Task 2: AppStore — Sync mit Widget verknüpfen

**Files:**
- Modify: `Paperless TeDi/Store/AppStore.swift`

- [ ] **Schritt 1: Import WidgetKit oben hinzufügen**

In `AppStore.swift` oben (nach den bestehenden imports):
```swift
import WidgetKit
```

- [ ] **Schritt 2: `syncMetadata()` erweitern — Statistics holen und schreiben**

Die Methode `syncMetadata()` (aktuell ab Zeile ~116) erhält nach dem Speichern der Metadaten einen Widget-Schreibaufruf. Ersetze die gesamte `syncMetadata()`-Methode:

```swift
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
```

- [ ] **Schritt 3: `updateWidget()` Hilfsmethode hinzufügen**

Am Ende von `AppStore.swift`, vor der letzten schließenden `}`:

```swift
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
```

- [ ] **Schritt 4: Build prüfen**

`⌘B` — keine Fehler.

- [ ] **Schritt 5: Commit**

```bash
git add "Paperless TeDi/Store/AppStore.swift"
git commit -m "feat: AppStore schreibt Widget-Daten nach Sync"
```

---

## Task 3: Settings — Widget-Abschnitt

**Files:**
- Modify: `Paperless TeDi/Views/Settings/SettingsView.swift`

- [ ] **Schritt 1: State-Variablen ergänzen**

In `SettingsView`, direkt nach `@AppStorage("pageSize") private var pageSize = 25`:

```swift
@State private var widgetEnabled: Bool = UserDefaults(suiteName: "group.com.Thomas.paperless")?.bool(forKey: "widget_enabled") ?? true
@State private var widgetMode: String = UserDefaults(suiteName: "group.com.Thomas.paperless")?.string(forKey: "widget_mode") ?? "documents"
```

- [ ] **Schritt 2: Widget-Sektion hinzufügen**

In `SettingsView.body` direkt vor dem letzten `Section` (dem mit Changelog + Design + Abmelden):

```swift
Section("Widget") {
    Toggle("Widget aktiv", isOn: $widgetEnabled)
        .onChange(of: widgetEnabled) { val in
            UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(val, forKey: "widget_enabled")
            store.updateWidget()
            WidgetCenter.shared.reloadAllTimelines()
        }
    if widgetEnabled {
        Picker("Anzeige", selection: $widgetMode) {
            Text("Letzte Dokumente").tag("documents")
            Text("Übersicht").tag("overview")
        }
        .onChange(of: widgetMode) { val in
            UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(val, forKey: "widget_mode")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
```

- [ ] **Schritt 3: WidgetKit import ergänzen**

Oben in `SettingsView.swift`:
```swift
import WidgetKit
```

- [ ] **Schritt 4: Build prüfen**

`⌘B` — keine Fehler.

- [ ] **Schritt 5: Commit**

```bash
git add "Paperless TeDi/Views/Settings/SettingsView.swift"
git commit -m "feat: Widget-Einstellungen in SettingsView"
```

---

## Task 4: Deep Link für Dokument-Öffnen

**Files:**
- Modify: `Paperless TeDi/App/Paperless_TeDiApp.swift`
- Modify: `Paperless TeDi/Store/AppStore.swift`

- [ ] **Schritt 1: `openDocumentById` in AppStore ergänzen**

In `AppStore.swift` unter dem `// MARK: - Widget` Block:

```swift
@Published var widgetOpenDocId: Int? = nil
```

Und weiter unten, am Ende des Widget-Blocks:

```swift
func triggerOpenDocument(id: Int) {
    widgetOpenDocId = id
}
```

- [ ] **Schritt 2: Deep Link in `Paperless_TeDiApp.swift` erweitern**

Den bestehenden `.onOpenURL`-Block erweitern. Den Block `if url.scheme == AppConstants.urlScheme` anpassen:

```swift
.onOpenURL { url in
    if url.scheme == AppConstants.urlScheme {
        if url.host == "check_shared" {
            checkForSharedFile()
        } else if url.host == "document" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let idStr = components?.queryItems?.first(where: { $0.name == "id" })?.value,
               let id = Int(idStr) {
                store.triggerOpenDocument(id: id)
            }
        } else if url.host == "exchange" || url.host == "import" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let filename = components?.queryItems?.first(where: { $0.name == "name" })?.value ?? "Import.pdf"
            if let pasteboard = UIPasteboard(name: UIPasteboard.Name("PaperlessExchange"), create: false),
               let data = pasteboard.data(forPasteboardType: "com.paperlesstedi.data") {
                store.handleImportData(data: data, filename: filename)
                pasteboard.items = []
            } else if let data = UIPasteboard.general.data(forPasteboardType: "com.paperlesstedi.shared") {
                store.handleImportData(data: data, filename: filename)
                UIPasteboard.general.items = []
            }
        }
    } else if url.isFileURL {
        store.handleIncomingFile(url: url)
    }
}
```

- [ ] **Schritt 3: Build prüfen**

`⌘B` — keine Fehler.

- [ ] **Schritt 4: Commit**

```bash
git add "Paperless TeDi/App/Paperless_TeDiApp.swift" "Paperless TeDi/Store/AppStore.swift"
git commit -m "feat: Deep Link paperlesstedi://document?id= für Widget-Tap"
```

---

## Task 5: Xcode Widget Target anlegen (MANUELL)

Dieser Schritt kann **nicht** per Code automatisiert werden — er erfordert Xcode-UI-Interaktion.

- [ ] **Schritt 1: Neues Target hinzufügen**

In Xcode:
1. `File → New → Target`
2. `Widget Extension` wählen
3. Name: `PaperlessWidget`
4. Product Name: `PaperlessWidget`
5. Include Configuration Intent: **Nein**
6. `Finish`

- [ ] **Schritt 2: App Group Capability hinzufügen**

Im neuen `PaperlessWidget`-Target:
1. `Signing & Capabilities` Tab
2. `+ Capability` → `App Groups`
3. `group.com.Thomas.paperless` aktivieren (dieselbe Gruppe wie Hauptapp und PaperlessShare)

- [ ] **Schritt 3: Swift-Version und Deployment Target prüfen**

Im `PaperlessWidget`-Target unter `Build Settings`:
- `iOS Deployment Target`: auf denselben Wert wie die Hauptapp setzen (z.B. iOS 16.0)
- `Swift Language Version`: `Swift 5`

- [ ] **Schritt 4: Von Xcode erstellte Dummy-Dateien löschen**

Xcode erstellt automatisch `PaperlessWidget.swift` und ggf. `PaperlessWidgetBundle.swift` mit Placeholder-Code. Diese Dateien **komplett überschreiben** (nicht löschen, sondern Inhalt ersetzen) in Task 6 + 7.

---

## Task 6: Widget Views

**Files:**
- Create/Overwrite: `PaperlessWidget/WidgetViews.swift`

- [ ] **Schritt 1: Datei anlegen/überschreiben**

```swift
import SwiftUI
import WidgetKit

// MARK: - Hilfs-View: eine Dokumentenzeile

struct DocRow: View {
    let doc: WidgetDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(doc.title)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            Text(formattedDate(doc.created))
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func formattedDate(_ s: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(s.prefix(10))) else { return s }
        let out = DateFormatter()
        out.dateStyle = .short
        out.timeStyle = .none
        return out.string(from: d)
    }
}

// MARK: - Deaktiviert-View (gemeinsam für alle Größen)

struct WidgetDisabledView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28)).foregroundColor(.accentColor)
            Text("Paperless TeDi")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small

struct SmallDocumentsView: View {
    let doc: WidgetDocument?

    var body: some View {
        if let doc = doc {
            Link(destination: URL(string: "paperlesstedi://document?id=\(doc.id)")!) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text(doc.title)
                        .font(.caption).fontWeight(.semibold).lineLimit(2)
                    if let corr = doc.correspondent {
                        Text(corr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetDisabledView()
        }
    }
}

struct SmallOverviewView: View {
    let inbox: Int
    var body: some View {
        VStack(spacing: 4) {
            Text("\(inbox)")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.accentColor)
            Text("Posteingang")
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "paperlesstedi://open"))
    }
}

// MARK: - Medium

struct MediumDocumentsView: View {
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.accentColor).font(.caption)
                Text("Zuletzt hinzugefügt").font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

            ForEach(docs.prefix(2)) { doc in
                Link(destination: URL(string: "paperlesstedi://document?id=\(doc.id)")!) {
                    DocRow(doc: doc)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
                if doc.id != docs.prefix(2).last?.id {
                    Divider().padding(.horizontal, 12)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumOverviewView: View {
    let inbox: Int
    let total: Int
    let lastSync: Date?

    var body: some View {
        HStack(spacing: 0) {
            statItem(value: "\(inbox)", label: "Posteingang", icon: "tray.fill", color: .pink)
            Divider().padding(.vertical, 12)
            statItem(value: "\(total)", label: "Dokumente", icon: "doc.text.fill", color: .blue)
            Divider().padding(.vertical, 12)
            statItem(value: syncText, label: "Sync", icon: "arrow.clockwise", color: .green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "paperlesstedi://open"))
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 18))
            Text(value).font(.headline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var syncText: String {
        guard let d = lastSync else { return "–" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Large

struct LargeDocumentsView: View {
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.accentColor).font(.caption)
                Text("Zuletzt hinzugefügt").font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            ForEach(docs.prefix(5)) { doc in
                Link(destination: URL(string: "paperlesstedi://document?id=\(doc.id)")!) {
                    DocRow(doc: doc).padding(.horizontal, 14).padding(.vertical, 5)
                }
                Divider().padding(.horizontal, 14)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeOverviewView: View {
    let inbox: Int
    let total: Int
    let lastSync: Date?
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                overviewStat(value: "\(inbox)", label: "Posteingang", icon: "tray.fill", color: .pink)
                overviewStat(value: "\(total)", label: "Dokumente", icon: "doc.text.fill", color: .blue)
                overviewStat(value: syncText, label: "Sync", icon: "arrow.clockwise", color: .green)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider().padding(.horizontal, 14)

            Text("Zuletzt hinzugefügt")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)

            ForEach(docs.prefix(2)) { doc in
                Link(destination: URL(string: "paperlesstedi://document?id=\(doc.id)")!) {
                    DocRow(doc: doc).padding(.horizontal, 14).padding(.vertical, 4)
                }
                Divider().padding(.horizontal, 14)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "paperlesstedi://open"))
    }

    private func overviewStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 14))
            Text(value).font(.subheadline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var syncText: String {
        guard let d = lastSync else { return "–" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
```

- [ ] **Schritt 2: Build prüfen (Widget-Target)**

Sicherstellen dass das `PaperlessWidget`-Target ausgewählt ist, dann `⌘B`.

- [ ] **Schritt 3: Commit**

```bash
git add PaperlessWidget/WidgetViews.swift
git commit -m "feat: Widget Views für alle Größen und Modi"
```

---

## Task 7: TimelineProvider und Widget-Konfiguration

**Files:**
- Create/Overwrite: `PaperlessWidget/PaperlessWidget.swift`
- Create/Overwrite: `PaperlessWidget/PaperlessWidgetBundle.swift`

- [ ] **Schritt 1: `PaperlessWidget.swift` erstellen/überschreiben**

```swift
import WidgetKit
import SwiftUI

struct PaperlessEntry: TimelineEntry {
    let date: Date
    let docs: [WidgetDocument]
    let inboxCount: Int
    let totalCount: Int
    let lastSync: Date?
    let mode: String
    let enabled: Bool
}

struct PaperlessTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaperlessEntry {
        PaperlessEntry(
            date: Date(),
            docs: [
                WidgetDocument(id: 1, title: "Rechnung Amazon", created: "2026-05-01", correspondent: "Amazon"),
                WidgetDocument(id: 2, title: "Kontoauszug Mai", created: "2026-05-10", correspondent: "Bank")
            ],
            inboxCount: 3,
            totalCount: 142,
            lastSync: Date(),
            mode: "documents",
            enabled: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PaperlessEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaperlessEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> PaperlessEntry {
        let stats = WidgetDataService.readStats()
        return PaperlessEntry(
            date: Date(),
            docs: WidgetDataService.readDocuments(),
            inboxCount: stats.inbox,
            totalCount: stats.total,
            lastSync: stats.lastSync,
            mode: WidgetDataService.readMode(),
            enabled: WidgetDataService.isEnabled()
        )
    }
}

struct PaperlessWidgetEntryView: View {
    let entry: PaperlessEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.enabled {
            WidgetDisabledView()
        } else if entry.mode == "overview" {
            overviewView
        } else {
            documentsView
        }
    }

    @ViewBuilder
    private var documentsView: some View {
        switch family {
        case .systemSmall:
            SmallDocumentsView(doc: entry.docs.first)
        case .systemMedium:
            MediumDocumentsView(docs: entry.docs)
        case .systemLarge:
            LargeDocumentsView(docs: entry.docs)
        default:
            SmallDocumentsView(doc: entry.docs.first)
        }
    }

    @ViewBuilder
    private var overviewView: some View {
        switch family {
        case .systemSmall:
            SmallOverviewView(inbox: entry.inboxCount)
        case .systemMedium:
            MediumOverviewView(inbox: entry.inboxCount, total: entry.totalCount, lastSync: entry.lastSync)
        case .systemLarge:
            LargeOverviewView(inbox: entry.inboxCount, total: entry.totalCount, lastSync: entry.lastSync, docs: entry.docs)
        default:
            SmallOverviewView(inbox: entry.inboxCount)
        }
    }
}

struct PaperlessWidget: Widget {
    let kind = "PaperlessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaperlessTimelineProvider()) { entry in
            PaperlessWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Paperless TeDi")
        .description("Zeigt deine zuletzt hinzugefügten Dokumente oder eine Übersicht.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

- [ ] **Schritt 2: `PaperlessWidgetBundle.swift` erstellen/überschreiben**

```swift
import WidgetKit
import SwiftUI

@main
struct PaperlessWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaperlessWidget()
    }
}
```

- [ ] **Schritt 3: `WidgetDocument` aus `WidgetDataService.swift` dem Widget-Target zugänglich machen**

In Xcode: `WidgetDataService.swift` in den **Target Memberships** auch für `PaperlessWidget` aktivieren.
(Datei im Navigator anklicken → rechts unter „Target Membership" auch `PaperlessWidget` anhaken)

- [ ] **Schritt 4: Build prüfen (beide Targets)**

Beide Targets (`Paperless TeDi` und `PaperlessWidget`) nacheinander mit `⌘B` bauen.

- [ ] **Schritt 5: Commit**

```bash
git add PaperlessWidget/PaperlessWidget.swift PaperlessWidget/PaperlessWidgetBundle.swift
git commit -m "feat: Widget TimelineProvider und Konfiguration"
```

---

## Task 8: Im Simulator testen

- [ ] **Schritt 1: App auf Simulator starten, einmal syncen**

App starten → sie synct automatisch → im Hintergrund werden Daten in App Group geschrieben.

- [ ] **Schritt 2: Widget zum Homescreen hinzufügen**

Im Simulator: Homescreen lang drücken → `+` → „Paperless TeDi" suchen → alle 3 Größen testen.

- [ ] **Schritt 3: Beide Modi testen**

In der App → Einstellungen → Widget → Anzeige auf „Übersicht" wechseln → zurück zum Homescreen → Widget sollte Stats zeigen.

- [ ] **Schritt 4: Deep Link testen**

Im Widget ein Dokument antippen → App sollte sich öffnen. (Vollständige Deep-Link-Navigation in Tab 4 ggf. noch implementieren, wenn `widgetOpenDocId` nicht vom RootTabView beobachtet wird — dann `onChange(of: store.widgetOpenDocId)` in `RootTabView` oder `MainDocView` ergänzen.)

- [ ] **Schritt 5: Toggle testen**

Einstellungen → Widget deaktivieren → Widget zeigt „Widget deaktiviert"-View.

- [ ] **Schritt 6: Finaler Commit**

```bash
git add -A
git commit -m "feat: Homescreen Widget vollständig implementiert"
```

---

## Self-Review Checkliste

- [x] `WidgetDataService` schreibt und liest alle 6 Schlüssel aus der Spec
- [x] `AppStore.syncMetadata()` holt Statistics und ruft `updateWidget()` auf
- [x] `WidgetCenter.shared.reloadAllTimelines()` wird nach Sync und nach Settings-Änderungen aufgerufen
- [x] Alle 3 Größen × 2 Modi implementiert (6 View-Kombinationen)
- [x] Placeholder-View für Xcode Widget Gallery vorhanden
- [x] Deep Link `paperlesstedi://document?id=` in `Paperless_TeDiApp.swift` verankert
- [x] `paperlesstedi://open` als Fallback für Stats-Widget
- [x] Widget-Toggle deaktiviert Datenschreiben und zeigt Disabled-View
- [x] `WidgetDocument` ist für beide Targets verfügbar (Target Membership in Task 7)
- [x] Manueller Xcode-Schritt (Task 5) klar dokumentiert
