# Phase 3 — Intelligenz-Features

**Datum:** 2026-06-02  **Branch:** `feature/ngx-parity`
Baut auf Phase 2 (AIService/FoundationModels, iOS 26). Neue Dateien → autom. im Target.

## 1+4. Fristen-Radar (inkl. Kündigungs-Assistent)
- **Modell** `Deadline` (`Models/Deadline.swift`): id, docId, docTitle, type (`DeadlineType`: payment/cancellation/warranty/withdrawal/general), date, description. Persistenz `deadlines.json`; `scannedDeadlineDocIds` → `deadlinescanned.json`.
- **AIService**: `extractDeadlines(text, today) -> [ExtractedDeadline]` (JSON-Liste). `draftCancellation(text, sender) -> String`.
- **Store**: `@Published deadlines`; nach `loadFirstPage` automatisch neue, ungescannte Dokumente mit Inhalt prüfen (gedeckelt ~10/Lauf, nur wenn `fristenRadarEnabled` && KI verfügbar); manueller Komplett-Scan mit Fortschritt.
- **EventKit** (`EventKitService`): pro Frist Button „zu Erinnerungen hinzufügen" (Full-Access-Request). Info.plist: `NSRemindersFullAccessUsageDescription`, `NSCalendarsFullAccessUsageDescription`.
- **UI** `FristenView`: gruppiert (überfällig/Woche/Monat/später), Zeile→Dokument, Buttons Erinnerung + (bei cancellation) „Kündigung entwerfen" → KI-Brief in Sheet (teilen/hochladen). Absenderprofil (Name/Adresse) in Einstellungen (`senderName`/`senderAddress`).
- **Schalter**: `fristenRadarEnabled` (Default true).

## 5. Dubletten-Erkennung
`DuplicatesView` (Einstellungen → on-demand). Gruppiert ähnliche Dokumente (normalisierter Titel + Wort-Jaccard auf Inhalt, gebucketet nach Korrespondent/Länge). Öffnen/Löschen je Eintrag.

## 6. Stapel-Scan mit Auto-Trennung
`PageScannerView` (neu, liefert `[UIImage]`). `BatchScanView`: Seiten OCR'n (`OCRService`), `AIService.groupPages([String]) -> [Int]` (Gruppen-Index je Seite, Fallback: alles eine Gruppe), Review-Screen zum Anpassen, dann je Gruppe PDF → bestehender Upload-Flow. Eigener Menüpunkt „Stapel scannen"; Schalter `batchScanEnabled`.

## 7. Natürlichsprachliche Suche (KI-Filter)
Sternchen-Button an der Suchleiste → Eingabe-Sheet → `AIService.parseQuery(q, tags, corr, types) -> ParsedQuery` (JSON {tag,correspondent,type,dateFrom,dateTo,text}) → mappt auf Filterzustand + wendet an. Nur sichtbar wenn KI verfügbar.

## 9. Übersetzung
Button in `DocumentDetailView` → `.translationPresentation(isPresented:text:)` (Apple-System-UI, Zielsprache = System, on-device). Schalter `translationEnabled`.

## 12. „Habe ich das schon?"-Kamera
Menüpunkt beim Hinzufügen → `PageScannerView` (1 Seite) → `OCRService` → Textähnlichkeit gegen `store.documents` (Titel+Inhalt) → `DuplicateCheckResultView` zeigt Top-Treffer mit Score oder „nicht gefunden".

## Querschnitt
- `OCRService` (Vision) — wiederverwendbar (#6, #12, ersetzt Inline-OCR wo sinnvoll).
- Neue Settings-Schalter + Absenderprofil in `SettingsView`.
- Version → 1.7.0, Changelog.

## Verifikation
`xcodebuild build` (alle Targets). KI/EventKit/Translation/Scanner nur build-verifizierbar — Runtime-Test durch User auf echtem Gerät.

## Risiken
On-device-LLM-Latenz (Fristen-Scan gedeckelt), EventKit-Berechtigung, Translation/FoundationModels geräteabhängig.
