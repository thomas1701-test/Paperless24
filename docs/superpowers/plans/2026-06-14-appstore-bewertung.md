# App-Store-Bewertungs-Erinnerung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nutzer nach positiven Momenten (Upload, Archiv-Treffer, KI-Aktion) freundlich um eine App-Store-Bewertung bitten, ohne zu nerven und ohne Apples 3×/Jahr-Limit zu verbrennen.

**Architecture:** Eine isolierte `ReviewRequestService`-Klasse kapselt die reine Gating-Logik (testbar ohne StoreKit) und persistiert ihren Zustand in `UserDefaults`. Auslöser-Stellen rufen `AppStore.registerReviewEvent()`. AppStore setzt ein `@Published`-Flag, das `RootTabView` per `.onChange` in den SwiftUI-`requestReview`-Environment-Aufruf übersetzt — exakt das Flag-Pattern, das die App bereits für `requestScan`, `requestInbox` usw. nutzt. Ein manueller „App bewerten"-Button in den Einstellungen öffnet die Schreib-Bewertungs-URL direkt.

**Tech Stack:** SwiftUI, StoreKit `@Environment(\.requestReview)` (iOS 26 Deployment), Swift Testing (`import Testing`), `UserDefaults`. Projekt nutzt synchronisierte Xcode-Ordner — neue Dateien werden automatisch ins Target aufgenommen.

**Spec:** `docs/superpowers/specs/2026-06-14-appstore-bewertung-design.md`

---

### Task 1: App-Store-ID-Konstante

**Files:**
- Modify: `Paperless24/Helpers/AppConstants.swift:5`

- [ ] **Step 1: Konstante hinzufügen**

In `AppConstants` direkt nach `urlScheme` einfügen:

```swift
    static let urlScheme = "paperless24"
    static let appStoreId = "6770317210"
```

- [ ] **Step 2: Commit**

```bash
git add "Paperless24/Helpers/AppConstants.swift"
git commit -m "feat: App-Store-ID als Konstante"
```

---

### Task 2: ReviewRequestService (Gating-Logik, TDD)

**Files:**
- Create: `Paperless24/Services/ReviewRequestService.swift`
- Test: `Paperless24Tests/ReviewRequestServiceTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Erstelle `Paperless24Tests/ReviewRequestServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import Paperless24

struct ReviewRequestServiceTests {

    /// Frische UserDefaults-Suite je Test, damit nichts überspringt.
    private func makeService() -> (ReviewRequestService, UserDefaults) {
        let suite = "review.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ReviewRequestService(defaults: defaults), defaults)
    }

    @Test func neuerNutzerWirdNichtGefragt() {
        let (svc, _) = makeService()
        svc.registerLaunch(today: Date())
        #expect(svc.shouldRequestReview(now: Date(), version: "1.8.1") == false)
    }

    @Test func dreiStarttageNeueVersionLoest() {
        let (svc, _) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == true)
    }

    @Test func gleicherTagZaehltNurEinmal() {
        let (svc, _) = makeService()
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: base)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func cooldownBlockiert() {
        let (svc, defaults) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        // Direkt seeden (nicht via recordPrompt, das das Session-Flag setzen würde):
        // vor 10 Tagen gefragt, andere Version -> Cooldown greift isoliert.
        defaults.set(cal.date(byAdding: .day, value: -10, to: base)!,
                     forKey: ReviewRequestService.Key.lastPromptDate)
        defaults.set("1.0.0", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func gleicheVersionNurEinmal() {
        let (svc, defaults) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        // Cooldown lange her (200 Tage), aber gleiche Version -> Versions-Sperre greift isoliert.
        defaults.set(cal.date(byAdding: .day, value: -200, to: base)!,
                     forKey: ReviewRequestService.Key.lastPromptDate)
        defaults.set("1.8.1", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func keinErneutesFragenNachPrompt() {
        let (svc, _) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == true)
        // Nach dem Prompt: nicht mehr (Session-Flag + Versions-Sperre).
        svc.recordPrompt(now: base, version: "1.8.1")
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func schreibBewertungsURLKorrekt() {
        let (svc, _) = makeService()
        #expect(svc.appStoreWriteReviewURL().absoluteString
            == "https://apps.apple.com/app/id6770317210?action=write-review")
    }
}
```

- [ ] **Step 2: Tests laufen lassen — müssen fehlschlagen (Typ existiert nicht)**

Run: `xcodebuild test -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: FAIL — Compile-Fehler „cannot find 'ReviewRequestService' in scope".
(Falls „iPhone 16" nicht existiert: `xcrun simctl list devices available` und einen vorhandenen Namen einsetzen.)

- [ ] **Step 3: ReviewRequestService implementieren**

Erstelle `Paperless24/Services/ReviewRequestService.swift`:

```swift
import Foundation

/// Entscheidet, OB nach einer App-Store-Bewertung gefragt wird.
/// Reine, ohne StoreKit testbare Gating-Logik; State liegt lokal in UserDefaults.
/// Der eigentliche `requestReview`-Aufruf passiert in der View-Schicht (RootTabView).
final class ReviewRequestService {
    static let shared = ReviewRequestService()

    // Justierbare Schwellen
    private let minLaunchDays = 3
    private let minDaysBetweenPrompts = 120

    private let defaults: UserDefaults
    private var didAttemptThisSession = false

    // Intern (nicht private), damit Tests den persistierten Zustand direkt seeden können.
    enum Key {
        static let launchDays = "review.launchDays"
        static let lastPromptDate = "review.lastPromptDate"
        static let lastPromptVersion = "review.lastPromptVersion"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Beim App-Start aufrufen: hält den heutigen Tag (yyyy-MM-dd) fest (dedupe).
    func registerLaunch(today: Date = Date()) {
        let key = Self.dayString(today)
        var days = defaults.stringArray(forKey: Key.launchDays) ?? []
        guard !days.contains(key) else { return }
        days.append(key)
        defaults.set(days, forKey: Key.launchDays)
    }

    /// Reine Gating-Funktion — alle Regeln müssen erfüllt sein.
    func shouldRequestReview(now: Date = Date(),
                             version: String = AppConstants.appVersion) -> Bool {
        if didAttemptThisSession { return false }

        let days = defaults.stringArray(forKey: Key.launchDays) ?? []
        if days.count < minLaunchDays { return false }

        if let last = defaults.object(forKey: Key.lastPromptDate) as? Date {
            let elapsedDays = now.timeIntervalSince(last) / 86_400
            if elapsedDays < Double(minDaysBetweenPrompts) { return false }
        }

        if defaults.string(forKey: Key.lastPromptVersion) == version { return false }

        return true
    }

    /// Nach einem ausgelösten Dialog aufrufen: markiert Versuch (Session + persistiert).
    func recordPrompt(now: Date = Date(),
                      version: String = AppConstants.appVersion) {
        didAttemptThisSession = true
        defaults.set(now, forKey: Key.lastPromptDate)
        defaults.set(version, forKey: Key.lastPromptVersion)
    }

    func appStoreWriteReviewURL() -> URL {
        URL(string: "https://apps.apple.com/app/id\(AppConstants.appStoreId)?action=write-review")!
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: Tests laufen lassen — müssen bestehen**

Run: `xcodebuild test -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: PASS — alle 7 Tests grün („Test Suite … passed").

- [ ] **Step 5: Commit**

```bash
git add "Paperless24/Services/ReviewRequestService.swift" "Paperless24Tests/ReviewRequestServiceTests.swift"
git commit -m "feat: ReviewRequestService mit Gating-Logik (+Tests)"
```

---

### Task 3: AppStore-Brücke + Upload-Auslöser

**Files:**
- Modify: `Paperless24/Store/AppStore.swift` (Published-Flag bei den anderen `request*`-Flags ~Z. 51-54; neue Methode; Aufruf in `processUploadQueue` ~Z. 553)

- [ ] **Step 1: Published-Flag ergänzen**

Bei den bestehenden Request-Flags (nach `@Published var requestAskArchive = false`, Z. 54) einfügen:

```swift
    @Published var requestAskArchive = false
    @Published var shouldRequestReview = false
```

- [ ] **Step 2: registerReviewEvent() hinzufügen**

Direkt nach `func removePendingUpload(at:)` (Z. 561) einfügen:

```swift
    /// Von positiven Momenten aufgerufen. Prüft die Gating-Regeln und setzt bei
    /// Eignung das Flag, das RootTabView in den requestReview-Aufruf übersetzt.
    func registerReviewEvent() {
        guard ReviewRequestService.shared.shouldRequestReview() else { return }
        ReviewRequestService.shared.recordPrompt()
        shouldRequestReview = true
    }
```

- [ ] **Step 3: Upload-Erfolg als Auslöser verdrahten**

In `processUploadQueue` (Z. 553) nach dem erfolgreichen Upload ergänzen:

```swift
                try await api.uploadDocument(item)
                processed.append(item.id)
                showSuccessToast("Fertig: \(item.title)")
                registerReviewEvent()
```

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "Paperless24/Store/AppStore.swift"
git commit -m "feat: AppStore-Bewertungs-Flag + Upload-Auslöser"
```

---

### Task 4: App-Start-Hook

**Files:**
- Modify: `Paperless24/App/ContentView.swift:42` (`.onAppear`)

- [ ] **Step 1: registerLaunch im onAppear**

Den bestehenden `.onAppear`-Block (Z. 42) um die erste Zeile ergänzen:

```swift
        .onAppear {
            ReviewRequestService.shared.registerLaunch()
            if store.serverUrl.isEmpty {
                appState = .welcome
            } else {
                checkLogin()
            }
        }
```

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Paperless24/App/ContentView.swift"
git commit -m "feat: Start-Tage für Bewertungs-Gating zählen"
```

---

### Task 5: RootTabView-Brücke zum requestReview-Aufruf

**Files:**
- Modify: `Paperless24/Views/App/RootTabView.swift` (Environment-Eigenschaft ~Z. 5; neues `.onChange` bei den anderen ~Z. 50)

- [ ] **Step 1: requestReview-Environment einbinden**

Nach `@EnvironmentObject var store: AppStore` (Z. 4) ergänzen:

```swift
    @EnvironmentObject var store: AppStore
    @Environment(\.requestReview) private var requestReview
    let onLogout: () -> Void
```

- [ ] **Step 2: onChange-Brücke ergänzen**

Direkt nach dem `.onChange(of: store.requestAskArchive)`-Block (Z. 50-52) einfügen:

```swift
        .onChange(of: store.shouldRequestReview) { req in
            if req {
                store.shouldRequestReview = false
                requestReview()
            }
        }
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "Paperless24/Views/App/RootTabView.swift"
git commit -m "feat: RootTabView löst requestReview-Dialog aus"
```

---

### Task 6: Weitere Auslöser-Stellen (Archiv-Treffer, KI-Aktionen)

**Files:**
- Modify: `Paperless24/Views/Shared/AskArchiveView.swift:43` (openDoc-Button)
- Modify: `Paperless24/Views/Documents/DocumentInfoView.swift:22` (Zusammenfassung erfolgreich)
- Modify: `Paperless24/Views/Documents/DocumentDetailView.swift` (Übersetzungs-Sheet geschlossen)

- [ ] **Step 1: Archiv-Treffer geöffnet**

In `AskArchiveView` den Button (Z. 43) ergänzen:

```swift
                                Button {
                                    openDoc = doc
                                    store.registerReviewEvent()
                                } label: {
```

- [ ] **Step 2: Zusammenfassung erfolgreich**

In `DocumentInfoView` im Erfolgszweig (Z. 21-22) ergänzen:

```swift
                                if let result = await AIService.shared.summarize(content) {
                                    summary = result
                                    store.registerReviewEvent()
                                } else {
```

- [ ] **Step 3: Übersetzung abgeschlossen**

In `DocumentDetailView` ein `.onChange` direkt nach dem bestehenden
`.translationPresentation(...)`-Modifier (Z. 101) anhängen:

```swift
        .translationPresentation(isPresented: $showTranslation, text: displayDoc.content ?? "")
        .onChange(of: showTranslation) { wasShown, isShown in
            if wasShown && !isShown { store.registerReviewEvent() }
        }
```

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "Paperless24/Views/Shared/AskArchiveView.swift" "Paperless24/Views/Documents/DocumentInfoView.swift" "Paperless24/Views/Documents/DocumentDetailView.swift"
git commit -m "feat: Archiv-Treffer und KI-Aktionen als Bewertungs-Auslöser"
```

---

### Task 7: Manueller „App bewerten"-Button in Einstellungen

**Files:**
- Modify: `Paperless24/Views/Settings/SettingsView.swift` (Environment `openURL` oben in der View; Button in der Section ~Z. 166-169)

- [ ] **Step 1: openURL-Environment ergänzen**

Falls noch nicht vorhanden, oben in `SettingsView` bei den anderen Eigenschaften ergänzen:

```swift
    @Environment(\.openURL) private var openURL
```

(Prüfen mit `grep -n "openURL" Paperless24/Views/Settings/SettingsView.swift` — nur hinzufügen, wenn nicht vorhanden.)

- [ ] **Step 2: Button in der Section einfügen**

In der letzten `Section` (Z. 166) vor dem Changelog-NavigationLink einfügen:

```swift
                Section {
                    Button {
                        openURL(ReviewRequestService.shared.appStoreWriteReviewURL())
                    } label: {
                        Label("App bewerten", systemImage: "star")
                    }
                    NavigationLink(destination: ChangelogView()) {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
```

- [ ] **Step 3: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add "Paperless24/Views/Settings/SettingsView.swift"
git commit -m "feat: App bewerten-Eintrag in den Einstellungen"
```

---

### Task 8: Versions-Bump auf 1.8.1 + Changelog

**Files:**
- Modify: `Paperless24/Helpers/AppConstants.swift:6` (`appVersion`) und `appChangelog`-Array (Z. 8)
- Modify: `Paperless 24.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, 3 Vorkommen)

- [ ] **Step 1: appVersion erhöhen**

In `AppConstants.swift`:

```swift
    static let appVersion = "1.8.1"
```

- [ ] **Step 2: Changelog-Eintrag voranstellen**

Als erstes Element im `appChangelog`-Array (vor dem 1.8.0-Eintrag):

```swift
    static let appChangelog: [ChangelogEntry] = [
        ChangelogEntry(version: "1.8.1", date: "14.06.2026", changes: [
            "Du kannst die App jetzt direkt aus den Einstellungen heraus bewerten.",
        ]),
        ChangelogEntry(version: "1.8.0", date: "08.06.2026", changes: [
```

- [ ] **Step 3: MARKETING_VERSION für alle Targets bumpen**

Run: `sed -i '' 's/MARKETING_VERSION = 1.8.0;/MARKETING_VERSION = 1.8.1;/g' "Paperless 24.xcodeproj/project.pbxproj"`
Danach prüfen: `grep -c "MARKETING_VERSION = 1.8.1;" "Paperless 24.xcodeproj/project.pbxproj"`
Expected: `3`

- [ ] **Step 4: Build prüfen**

Run: `xcodebuild build -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add "Paperless24/Helpers/AppConstants.swift" "Paperless 24.xcodeproj/project.pbxproj"
git commit -m "chore: Version 1.8.1 + Changelog"
```

---

### Task 9: Gesamt-Verifikation

**Files:** keine

- [ ] **Step 1: Tests laufen lassen**

Run: `xcodebuild test -scheme Paperless24 -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, alle ReviewRequestService-Tests grün.

- [ ] **Step 2: Alle drei Schemes bauen**

Run:
```bash
for s in Paperless24 PaperlessShare PaperlessWidgetExtension; do
  echo "=== $s ==="
  xcodebuild build -scheme "$s" -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
done
```
Expected: jeweils `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manueller Gegentest (durch den Nutzer, am Simulator/Gerät)**

- Einstellungen → „App bewerten" öffnet die korrekte App-Store-Schreib-Bewertung.
- StoreKit-Dialog erscheint im Simulator nach einem ausgelösten positiven Moment
  (im Simulator ohne Drossel; in TestFlight/Release entscheidet Apple).

---

## Hinweise für die Umsetzung

- **`onChange`-Signatur:** `RootTabView` nutzt die alte Ein-Parameter-Form
  (`{ val in }`) — dort konsistent bleiben (Task 5). In `DocumentDetailView`
  (Task 6) wird die alte/neue Wertform (`{ wasShown, isShown in }`) gebraucht.
- **Deutsche Strings:** Niemals ein gerades `"` innerhalb eines Strings — beendet
  ihn. Hier nicht relevant, aber im Changelog beachten.
- **Synchronisierte Ordner:** Neue Dateien (`ReviewRequestService.swift`,
  `ReviewRequestServiceTests.swift`) werden durch die Xcode-Ordner-Sync
  automatisch ins jeweilige Target gezogen — kein pbxproj-Eingriff nötig.
- **Simulator-Name:** Schlägt `name=iPhone 16` fehl, mit
  `xcrun simctl list devices available` einen vorhandenen Namen wählen.
