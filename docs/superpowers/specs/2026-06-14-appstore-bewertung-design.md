# App-Store-Bewertungs-Erinnerung

**Datum:** 2026-06-14
**Branch:** feature/ngx-parity
**Version:** 1.8.0 → 1.8.1

## Problem

Die App fragt Nutzer nie nach einer App-Store-Bewertung. Es gibt keinerlei
StoreKit-/`requestReview`-Logik im Code. Gewünscht: zum richtigen Moment freundlich
nach einer Bewertung fragen — ohne zu nerven und ohne Apples Limit (max. 3 Dialoge
pro Jahr) zu verbrennen.

## Umfang

- Neuer `ReviewRequestService` (`Services/`) mit der gesamten Entscheidungslogik.
- Drei Auslöser-Stellen rufen je eine Zeile auf (`registerPositiveEvent()`).
- Session-Zähler beim App-Start.
- Manueller „App bewerten"-Eintrag in den Einstellungen.
- App-Store-ID als Konstante in `AppConstants`.

**Keine** Änderungen an Datenmodell, API oder Netzwerk. State liegt rein lokal in
`UserDefaults` (Bewertungs-Status ist geräte-spezifisch — kein iCloud-Sync).

## Design

### Ansatz: „Wann fragen" und „ob fragen" trennen

Das *Wann* (positive Momente) sind dünne Aufrufe verstreut im UI. Das *Ob* lebt
zentral und isoliert in `ReviewRequestService` — eine reine Entscheidungsfunktion
über (Sessions, letztes Aufforderungsdatum, zuletzt gefragte Version), die ohne
StoreKit unit-testbar ist.

### Komponente 1 — `ReviewRequestService`

Datei: `Services/ReviewRequestService.swift` (neu)

Singleton `ReviewRequestService.shared`. Persistierte Werte in `UserDefaults`
(Standard-Suite reicht):

| Key | Typ | Bedeutung |
|-----|-----|-----------|
| `review.launchDays` | `[String]` | Distinct Tage (yyyy-MM-dd), an denen die App lief |
| `review.lastPromptDate` | `Date?` | Wann zuletzt der Dialog ausgelöst wurde |
| `review.lastPromptVersion` | `String?` | App-Version, für die zuletzt gefragt wurde |

Laufzeit-Flag (nicht persistiert): `didAttemptThisSession: Bool`.

Konstanten (leicht justierbar, am Kopf der Datei):
- `minLaunchDays = 3`
- `minDaysBetweenPrompts = 120`

API:

```
func registerLaunch()
    // beim App-Start: heutigen Tag (yyyy-MM-dd) in launchDays aufnehmen (dedupe)

func registerPositiveEvent(_ request: RequestReviewAction)
    // von Auslöser-Stellen aufgerufen; prüft shouldRequest() und ruft ggf. request() auf

func shouldRequest() -> Bool          // reine, testbare Gating-Funktion
func appStoreWriteReviewURL() -> URL  // für den manuellen Button
```

### Gating-Regeln (`shouldRequest`)

Alle müssen `true` sein, sonst passiert nichts:

1. `didAttemptThisSession == false` (max. 1 Versuch pro Session)
2. `launchDays.count >= minLaunchDays` (keine Neu-Nutzer)
3. `lastPromptDate == nil` **oder** ≥ `minDaysBetweenPrompts` Tage her
4. `lastPromptVersion != AppConstants.appVersion` (pro Version nur einmal)

Sind 1–4 erfüllt: `didAttemptThisSession = true` setzen, `lastPromptDate = now`,
`lastPromptVersion = appVersion` speichern, dann den iOS-26-
`RequestReviewAction` aufrufen. Das System zeigt den Dialog *evtl.* — die finale
Entscheidung liegt bewusst bei Apple.

### Komponente 2 — Auslöser-Stellen (je 1 Zeile)

Die View liest die Aufforderung aus der Umgebung:
`@Environment(\.requestReview) private var requestReview` und reicht sie an
`registerPositiveEvent(requestReview)` durch (der Service hält selbst keinen
`RequestReviewAction`).

| Moment | Ort | Auslöser |
|--------|-----|----------|
| Dokument erfolgreich archiviert | Pending-Queue-Verarbeitung in `Store/AppStore.swift` (nach Server-Bestätigung des Uploads) | nach erfolgreichem Upload |
| Treffer in „Frag das Archiv" | `Views/Shared/AskArchiveView.swift` | wenn ein Treffer-Dokument geöffnet wird |
| KI-Aktion fertig | `Views/Documents/DocumentDetailView.swift` (Zusammenfassung) bzw. Übersetzungs-Abschluss | nach erfolgreich abgeschlossener Zusammenfassung/Übersetzung |

Da der Service in einer reinen Logik-Schicht sitzt, AppStore aber kein
SwiftUI-Environment hat: AppStore postet ein leichtes Signal (z. B. Methodenaufruf
mit übergebenem `RequestReviewAction` aus der aufrufenden View, oder ein
`@Published`-Flag, das die Root-View beobachtet und dann `requestReview()` ruft).
**Implementierungsdetail:** bevorzugt den `RequestReviewAction` von der nächsten
View durchreichen; nur falls das umständlich wird, ein `@Published var
shouldShowReviewPrompt` in AppStore, das `RootTabView` per `.onChange` in
`requestReview()` übersetzt.

### Komponente 3 — App-Start-Hook

In `App/Paperless_TeDiApp.swift` (oder `RootTabView.onAppear`):
`ReviewRequestService.shared.registerLaunch()` einmal pro Kaltstart.

### Komponente 4 — Manueller Button „App bewerten"

Datei: `Views/Settings/SettingsView.swift`

Neue Zeile (passend zur bestehenden Sektion, z. B. nahe „Über"/Changelog):
„App bewerten" → öffnet `appStoreWriteReviewURL()` via `openURL`.

```
https://apps.apple.com/app/id6770317210?action=write-review
```

Funktioniert immer — auch wenn der automatische Dialog gedrosselt ist.

### Komponente 5 — Konstante

`Helpers/AppConstants.swift`:

```swift
static let appStoreId = "6770317210"
```

## Fehlerfälle

- StoreKit nicht verfügbar / Dialog wird vom System unterdrückt: kein Fehler,
  `requestReview()` ist „best effort". Wir markieren den Versuch trotzdem als
  erfolgt (sonst würden wir bei jedem Event erneut anlaufen).
- Manueller URL lässt sich nicht öffnen (z. B. kein App Store): `openURL`-
  Completion ignorieren bzw. still scheitern lassen — kein Blockieren.
- `UserDefaults`-Werte fehlen beim ersten Start: Defaults (`[]`, `nil`) greifen,
  Gating ist dann sauber `false` bis Schwellen erreicht sind.

## Versionierung & Changelog

- `AppConstants.appVersion`: `1.8.0` → `1.8.1`.
- Neuer `ChangelogEntry(version: "1.8.1", date: "14.06.2026", …)` am Anfang von
  `appChangelog`, z. B.:
  - „Du kannst die App jetzt direkt aus den Einstellungen heraus bewerten."
- `MARKETING_VERSION` in `Paperless 24.xcodeproj/project.pbxproj` für alle drei
  Targets `1.8.0` → `1.8.1`.

## Verifikation

- Unit-Test der reinen Gating-Logik `shouldRequest()` über gesetzte
  `UserDefaults`-Werte (Sessions, Datum, Version) — deckt alle vier Regeln ab.
- Build via `xcodebuild` (alle 3 Targets).
- Manueller Gegentest im Simulator: Auslöser triggern; StoreKit-Dialog erscheint
  im Simulator unbeschränkt. Manueller „App bewerten"-Button öffnet die korrekte
  App-Store-URL.

## Bewusst nicht enthalten (YAGNI)

- Kein eigenes In-App-Feedback-Sheet vor der Bewertung („Gefällt dir die App?"
  → ja/nein-Weiche). Apple rät davon ab und es ist für v1 unnötig.
- Kein Server-/iCloud-Sync des Bewertungs-Status — bewusst pro Gerät.
- Keine Tracking-/Analytics-Anbindung.
