# Homescreen Widget — Design Spec
**Datum:** 2026-05-15  
**Status:** Genehmigt

---

## Übersicht

Ein WidgetKit-Widget für den iOS-Homescreen, das die letzten Dokumente oder eine Statistik-Übersicht aus der Paperless TeDi App anzeigt. Drei Größen werden unterstützt. Der Nutzer kann in den App-Einstellungen den Widget-Modus und den Aktiv-Status konfigurieren.

---

## Architektur

### Neues Xcode-Target: `PaperlessWidget`
- WidgetKit Extension
- Teilt App Group `group.com.Thomas.paperless` mit Hauptapp und Share Extension
- Kein direkter API-Zugriff — liest ausschließlich aus dem App-Group-Container

### Datenfluss

```
AppStore.sync()
    └─► WidgetDataService.write(docs, stats)
            └─► App Group UserDefaults / JSON-Datei
                    └─► Widget TimelineProvider liest
                            └─► Widget rendert
```

### Refresh-Strategie
- Widget fordert alle 30 Minuten ein Timeline-Update an (`TimelineReloadPolicy.after(...)`)
- Hauptapp ruft `WidgetCenter.shared.reloadAllTimelines()` nach jedem Sync auf

---

## Datenmodell (App Group)

Gespeichert in `App Group UserDefaults` (`group.com.Thomas.paperless`):

```swift
// Schlüssel
"widget_enabled"        // Bool
"widget_mode"           // String: "documents" | "overview"
"widget_documents"      // Data (JSON: [WidgetDocument])
"widget_inbox_count"    // Int
"widget_total_count"    // Int
"widget_last_sync"      // Date (TimeInterval)
```

```swift
struct WidgetDocument: Codable {
    let id: Int
    let title: String
    let created: String  // "2026-01-15"
    let correspondent: String?  // aufgelöster Name
}
```

---

## Widget-Modi und Größen

| Größe | Modus "Letzte Dokumente" | Modus "Übersicht" |
|-------|--------------------------|-------------------|
| Small (2×2) | 1 Dokument (Titel + Datum) | Posteingang-Zähler groß |
| Medium (4×2) | 2 Dokumente | Posteingang + Gesamt + Sync-Zeit |
| Large (4×4) | 5 Dokumente | Alle Stats + letzte 2 Dokumente |

---

## Deep Links

Tap auf ein Dokument im Widget öffnet die App via URL-Scheme:

```
paperlesstedi://document?id=123
```

Tap auf den Hintergrund / Stats-Widget öffnet die App auf der Hauptansicht:

```
paperlesstedi://open
```

**Änderung in `Paperless_TeDiApp.swift`:** `.onOpenURL` wird um den neuen `document?id=` Case erweitert, der `AppStore.openDocumentById(_:)` aufruft.

---

## App-Einstellungen (SettingsView)

Neuer Abschnitt **„Widget"** in `SettingsView.swift`:

```
Section("Widget") {
    Toggle("Widget aktiv", isOn: $widgetEnabled)
    if widgetEnabled {
        Picker("Anzeige", selection: $widgetMode) {
            Text("Letzte Dokumente").tag("documents")
            Text("Übersicht").tag("overview")
        }
    }
}
```

Beide Werte werden in `App Group UserDefaults` geschrieben (nicht `@AppStorage`), damit das Widget sie ohne laufende App lesen kann.

---

## Neue Dateien

| Datei | Zweck |
|-------|-------|
| `PaperlessWidget/PaperlessWidgetBundle.swift` | Widget Entry Point |
| `PaperlessWidget/PaperlessWidget.swift` | `Widget`-Struct mit TimelineProvider |
| `PaperlessWidget/WidgetViews.swift` | SwiftUI Views für alle 3 Größen × 2 Modi |
| `Paperless TeDi/Services/WidgetDataService.swift` | Schreibt Daten in App Group |

---

## Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `AppStore.swift` | `sync()` ruft `WidgetDataService.write()` und `WidgetCenter.shared.reloadAllTimelines()` auf |
| `SettingsView.swift` | Neuer Widget-Abschnitt |
| `Paperless_TeDiApp.swift` | Deep-Link-Handler für `document?id=` |

---

## Einstellungs-Toggle Verhalten

- **Widget deaktiviert:** `WidgetDataService` schreibt leere/nil Daten; Widget zeigt „Widget deaktiviert" mit App-Icon
- **Widget aktiviert:** Daten werden bei jedem Sync aktualisiert

---

## Nicht im Scope

- Interaktive Widgets (iOS 17 Button-Tap direkt im Widget)
- Lock Screen Widget
- macOS Widget
