# Durchsuchbare Metadaten-Auswahl (Sender / Typ / Tags)

**Datum:** 2026-06-08
**Branch:** feature/ngx-parity
**Version:** 1.8.0

## Problem

Im Import-Screen (und beim Bearbeiten) wählt man Sender, Typ und Tags über
einfache `Picker`/`Menu`-Steuerelemente ohne Suche. Bei vielen Einträgen ist
das mühsames Scrollen. Gewünscht: je ein Suchfeld pro Auswahl.

## Umfang

Greift überall, wo die geteilte Komponente `MetadataFormSection` verwendet wird:

- Import: `Views/Upload/UploadDocumentView.swift`
- Bearbeiten: `Views/Edit/EditDocumentView.swift`

Reine View-Schicht. **Keine** Änderungen an Datenmodell, API oder Store.

## Design

### Ansatz

Statt Dropdown/Menu direkt im Formular werden Sender, Typ und Tags zu
**tippbaren Zeilen**, die ein **durchsuchbares Sheet** (`.searchable`) öffnen.
Das entspricht dem bereits vorhandenen Filter-Pattern (`FilterPickerSheet`).

### Komponente 1 — `FilterPickerSheet` erweitern

Datei: `Views/Shared/FilterPickerSheet.swift`

- Neuer optionaler Parameter `noneLabel: String = "Alle"`.
- Die „Alle"-Zeile (Auswahl = `nil`) zeigt stattdessen `noneLabel` an.
- Bestehender Aufruf in `MainDocView` bleibt unverändert (Default „Alle").
- Im Metadaten-Kontext: `noneLabel: "Kein Sender"` bzw. `"Kein Typ"`.

Damit wird die fertige, durchsuchbare Einfachauswahl für **Sender** und **Typ**
wiederverwendet — kein Duplikat.

### Komponente 2 — Neues `MultiSelectPickerSheet`

Datei: `Views/Shared/MultiSelectPickerSheet.swift` (neu)

Durchsuchbare **Mehrfachauswahl** für **Tags**.

- Eingaben:
  - `title: String`
  - `items: [FilterPickerItem]` (id + name; bestehender Typ aus FilterPickerSheet)
  - `colors: [Int: String]` optional (Tag-Farbe als Hex; für Farbpunkt)
  - `@Binding var selected: Set<Int>`
- Verhalten:
  - `List` mit Häkchen-Zeilen; Tippen toggelt die Auswahl.
  - `.searchable(text:)` filtert per `localizedCaseInsensitiveContains`.
  - Sheet bleibt offen; „Fertig"-Button in der Toolbar schließt es.
  - Optionaler Farbpunkt links (wie in `QuickTagSheet`), wenn `colors` einen
    Eintrag liefert.

### Komponente 3 — `MetadataFormSection` umbauen

Datei: `Views/Shared/MetadataFormSection.swift`

Die drei Steuerelemente werden zu tippbaren Zeilen + bestehendem „+"-Button:

| Zeile  | Anzeige                          | Tippen öffnet                              |
|--------|----------------------------------|--------------------------------------------|
| Sender | aktueller Name oder „Kein Sender"| `FilterPickerSheet` (noneLabel „Kein Sender") |
| Typ    | aktueller Name oder „Kein Typ"   | `FilterPickerSheet` (noneLabel „Kein Typ") |
| Tags   | „N gewählt" / „Keine"            | `MultiSelectPickerSheet`                    |

- Mapping `store.allCorrespondents` / `store.allDocTypes` / `store.allTags` auf
  `[FilterPickerItem]` (id, `safeName`).
- Tag-Farben aus `store.allTags` (`safeColor`) in `colors` reichen.
- Die grünen **„+"-Buttons** (Neu-Anlegen via `SimpleInputSheet`) bleiben
  unverändert daneben erhalten.
- Der **KI-Zauberstab** (`runAnalysis` / `applySuggestion`) bleibt unverändert.
- Sheet-Präsentation über drei `Bool`-States bzw. einen `enum`-State plus
  Item-/Binding-Übergabe.

## Fehlerfälle

- Leere Listen (keine Tags/Sender/Typen): Sheet öffnet mit leerer Liste; Suche
  liefert nichts. „+"-Button bleibt der Weg zum Anlegen — unverändert.
- Auswahl zeigt auf gelöschten Eintrag: Name nicht gefunden → Fallback auf
  `noneLabel` in der Zeilenanzeige (bestehendes Verhalten beibehalten).

## Versionierung & Changelog

- `AppConstants.appVersion`: `1.7.0` → `1.8.0`.
- Neuer `ChangelogEntry(version: "1.8.0", date: "08.06.2026", …)` an den Anfang
  des `appChangelog`-Arrays, z. B.:
  - „Sender, Typ und Tags bei Import und Bearbeiten jetzt durchsuchbar."
- `MARKETING_VERSION` in `Paperless 24.xcodeproj/project.pbxproj` für alle
  Targets `1.7.0` → `1.8.0`.

## Verifikation

- Build via `xcodebuild` (Compile-Check der Views).
- Manueller Gegentest im Simulator/Gerät durch den Nutzer (Import-Flow:
  Sender/Typ/Tags suchen und auswählen; Bearbeiten-Flow ebenso).

## Bewusst nicht enthalten (YAGNI)

- Kein Inline-Anlegen aus dem Suchergebnis heraus („als neu anlegen, wenn keine
  Treffer") — die bestehenden „+"-Buttons decken das ab.
- Keine Änderung am KI-Zauberstab oder an Custom Fields.
