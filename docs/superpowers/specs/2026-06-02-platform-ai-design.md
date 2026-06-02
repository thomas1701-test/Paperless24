# Phase 2 — Apple-Plattform-Tiefe + KI

**Datum:** 2026-06-02  **Branch:** `feature/ngx-parity` (Folgearbeit)
Deployment-Target: iOS 26 (FoundationModels verfügbar). Synchronisierte Ordnergruppe → neue Dateien automatisch im Target.

## A. Verstellbare Kachelgröße (Mac/iPad)
`@AppStorage("gridItemSize")` (Default 130). Slider in Einstellungen. `LazyVGrid` in MainDocView/InboxView nutzt `GridItem(.adaptive(minimum: gridItemSize))`.

## B. iCloud-Settings-Sync
`SettingsSyncService` spiegelt ausgewählte UserDefaults-Keys in `NSUbiquitousKeyValueStore` (appearanceMode, layoutStyle, appLanguage, pageSize, gridItemSize, aiEnabled, notificationsEnabled). Bidirektional via Notification-Observer.

## C. Drag & Drop (iPad)
`DocumentCard`/`DocumentRow` erhalten `.onDrag { NSItemProvider(...) }` mit der lokalen PDF-Datei (lädt bei Bedarf in tmp).

## D. App Intents / Shortcuts & Siri
`Intents/AppShortcuts.swift`: `ScanDocumentIntent`, `OpenInboxIntent`, `SearchDocumentsIntent(query)`. Öffnen App via Deep-Link-State im Store (`pendingIntentAction`). `AppShortcutsProvider` mit deutschen Phrasen.

## E. Lokale Benachrichtigungen
`NotificationService`: UNUserNotificationCenter-Auth, BGAppRefreshTask (`com.Thomas.paperless.refresh`). Hintergrund: Statistik laden, wenn Inbox > letzter gemerkter Wert → lokale Notification. Info.plist: `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes=fetch`. Toggle in Einstellungen.

## F. KI (Apple Intelligence, on-device)
`AIService` (FoundationModels): `availability`, `summarize(text)`, `extractMetadata(text, existingTags/Corr/Types)`, `answer(question, context)`. Alles hinter `@AppStorage("aiEnabled")` (Default true). Auf inkompatiblen Geräten/Aus: Funktionen ausgeblendet, Auto-Tagging fällt auf bestehende Vision-Logik zurück.
- **Auto-Tagging+**: MetadataFormSection nutzt AIService für Vorschläge (inkl. neuer Tags).
- **Zusammenfassung**: Button im Detail (Info-Tab), zeigt KI-Summary.
- **Frag dein Archiv (leicht)**: `AskArchiveView` — `NLEmbedding` (sentence) rankt geladene Dokumente (Titel+content) gegen die Frage, Top-N als Kontext an AIService. Eintrag in Einstellungen/Toolbar.

## G. Live-Text-Aktionen (OCR-Tab)
OCR-Text-Tab linkifiziert via `NSDataDetector` (Telefon, Link, Adresse) → `AttributedString` mit tappbaren Aktionen; IBAN-Regex zum Kopieren.

## H. iPad/Mac Split-View (leicht)
MainDocView: bei `horizontalSizeClass == .regular` `NavigationSplitView` (Liste links, Detail rechts), sonst bisheriger `NavigationStack`. Auswahl über `selectedDocId`.

## I. AirScan (eSCL, best-effort)
`AirScanService`: `NWBrowser` für `_uscan._tcp`; eSCL über URLSession (POST `/eSCL/ScanJobs` mit Settings-XML, GET `NextDocument` → JPEG/PDF). `AirScanView` listet gefundene Scanner, startet Scan, übergibt Daten an bestehenden Upload-Flow. Funktioniert nicht mit jedem Gerät (dokumentiert).

## J. Vermietoo erweitern
- **Mehrfachauswahl**: Bulk-Aktion „An Vermietoo" im Auswahl-Modus (mehrere IDs + PDFs via Pasteboard, Callback mit id-Liste).
- **Bidirektional**: URL-Scheme `paperless24://upload` (Vermietoo legt Dokument via Pasteboard-Daten zurück) → bestehender Upload-Flow.

## Verifikation
`xcodebuild build` (alle Targets) muss durchlaufen. FoundationModels/AirScan/BGTask nur build-verifizierbar (kein Gerät/Scanner/Server hier) — Runtime-Test durch den User.

## Risiken / bewusst best-effort
AirScan (kein offizielles iOS-API), FoundationModels-Verfügbarkeit (geräteabhängig), BGTask-Timing (OS-gesteuert).
