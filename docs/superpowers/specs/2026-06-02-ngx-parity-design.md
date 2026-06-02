# Paperless-ngx Feature-Parität — Design

**Datum:** 2026-06-02
**Branch:** `feature/ngx-parity`

Schließt fünf funktionale Lücken gegenüber Paperparrot / Swift Paperless. Jedes Feature
folgt dem bestehenden Muster: `PaperlessAPI` (Netzwerk) → `AppStore` (`@MainActor`,
`@Published`, Persistenz pro Konto) → SwiftUI-Views. Neue Dateien unter `Paperless24/`
werden dank `PBXFileSystemSynchronizedRootGroup` automatisch kompiliert.

## 1. Custom Fields (voll: alle Typen, lesen + bearbeiten)

**Modelle** (`Models/CustomField.swift`)
- `CustomField`: `id`, `name`, `data_type`, `extra_data` (Select-Optionen, Währung).
- `CustomField.SelectOption`: dekodiert sowohl neue Objekt-Form (`{id,label}`) als auch
  alte String-Form.
- `CFValue`: Enum, das den heterogenen Wert flexibel de-/kodiert
  (`text/number/integer/bool/ints/strings/none`); `jsonValue` für PATCH-Body.
- `CustomFieldEdit { field: Int, value: CFValue }`.

**Document**: neues Feld `customFields: [CustomFieldEdit]` (Default `[]`), dekodiert aus
`custom_fields`. Memberwise-Init bleibt nutzbar (Default-Wert).

**API**: `fetchCustomFields()`; `patchDocument(...)` erhält `customFields`-Parameter und
sendet `custom_fields: [{field, value}]` — nur Einträge mit Wert ≠ `none`.

**Store**: `@Published allCustomFields`, Persistenz `customfields.json`, Laden in
`syncMetadata`. `PendingEdit` + `addPendingEdit` + `reApplyPendingEdits` tragen
`customFields`. Bulk-Operationen reichen `doc.customFields` durch (kein Datenverlust).

**UI**: `Shared/CustomFieldsSection.swift` rendert je Typ (TextField / DatePicker /
Toggle / NumberPad / Picker für Select / Dokument-Link-Editor mit Auswahl-Sheet).
Eingebunden in `EditDocumentView`. `DocumentDetailView` erhält einen „Info"-Tab mit
read-only-Anzeige (Metadaten + Custom Fields). Client-seitiger Filter-Chip „Feld" in der
Filter-Bar (konsistent mit bestehenden lokalen Filtern in `updateFilteredDocs`).

## 2. Papierkorb (voll: Liste, Wiederherstellen, endgültig löschen)

**Modell** (`Models/TrashDocument.swift`): `id`, `title`, `created`, `deleted_at`.
**API**: `fetchTrash()`; `restoreFromTrash(ids:)` → `POST /api/trash/ {action:"restore",documents:[…]}`;
`emptyTrash(ids:)` → `{action:"empty",documents:[…]}`.
**Store**: `trashedDocs`, `loadTrash()`, `restoreFromTrash`, `emptyTrash`.
**UI**: `Views/Settings/TrashView.swift`, verlinkt aus `SettingsView` („Papierkorb").
Liste mit Mehrfachauswahl, Wiederherstellen, endgültig löschen (mit Bestätigung).
Löschen eines Dokuments wandert in ngx 2.x ohnehin in den Papierkorb.

## 3. Tag-Hierarchien (Parent Tags, verschachtelt)

**Tag**: Feld `parent: Int?`. Helper `childTags(of:)`, `rootTags`, `tagPath(id:)` im Store.
**UI**: Tag-Filter-Picker und `TagListView` zeigen Einrückung nach Parent. Badges in
Karten/Zeilen bleiben unverändert.

## 4. Share Links (voll: erstellen mit Ablauf, kopieren, widerrufen)

**Modell** (`Models/ShareLink.swift`): `id`, `slug`, `expiration`, `created`,
`document`, `file_version`. Öffentliche URL: `<server>/share/<slug>`.
**API**: `fetchShareLinks(documentId:)`, `createShareLink(documentId:expiration:fileVersion:)`,
`deleteShareLink(id:)`.
**UI**: `Views/Documents/ShareLinkSheet.swift`, geöffnet aus `DocumentDetailView`-Toolbar.
Bestehende Links auflisten, neuen mit optionalem Ablaufdatum erstellen, URL kopieren,
widerrufen.

## 5. Saved Views (Server-Views nutzen, lokale migrieren)

**Modell** (`Models/SavedView.swift`): `id`, `name`, `show_on_dashboard`,
`show_in_sidebar`, `sort_field`, `sort_reverse`, `filter_rules:[{rule_type,value}]`.
**Rule-Type-Mapping**: Titel 0, Korrespondent 3, Typ 4, Has-Tag 6, Created-After 9,
Created-Before 8 (verifiziert gegen ngx-Quellcode `filter-rule-type.ts`).
**API**: `fetchSavedViews()`, `createSavedView(...)`, `deleteSavedView(id:)`.
**Store**: `serverViews`, `loadSavedViews()`. Migration: bestehende lokale `savedFilters`
einmalig (`migrated_saved_views`-Flag) per `createSavedView` zum Server hochladen, danach
lokale Liste leeren. `applyServerView` parst `filter_rules` → setzt
`filterTag/Corr/Type/Date` + `SortOrder`.
**UI**: Filter-Bar zeigt Server-Views als Chips (ersetzt lokale Chips); „Speichern"
erstellt jetzt eine Server-View.

## Test / Verifikation
`xcodebuild build -scheme Paperless24` muss fehlerfrei durchlaufen. Manuelle Smoke-Tests
gegen einen ngx-Server pro Feature.

## Bewusst ausgeklammert (YAGNI)
Storage Paths, Owner-Filter, Workflows, Mail-Rules, Custom-Field-Server-Query
(stattdessen client-seitiger Filter), macOS/Watch (Option 2).
