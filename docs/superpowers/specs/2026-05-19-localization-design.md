# Lokalisierung — Design Spec

**Datum:** 2026-05-19  
**Status:** Approved

## Ziel

Die App Paperless24 (inkl. Widget und Share Extension) wird in 5 Sprachen verfügbar gemacht:
- **Englisch** (Base / Fallback — Development Language)
- Deutsch
- Französisch
- Spanisch
- Italienisch

Die Sprache folgt der iOS-Systemsprache. Nutzer können die App-Sprache über *Einstellungen → Paperless24 → Sprache* überschreiben (iOS 13+ Per-App Language, automatisch verfügbar ohne Extra-Code).

## Ansatz: String Catalogs (.xcstrings)

Xcode 15+ nativer Standard. JSON-basiert, eine Datei pro Target enthält alle Sprachen. Xcode zeigt Übersetzungsstand automatisch an. SwiftUI `Text("literal")`, `TextField("placeholder", …)`, `.navigationTitle("…")`, `Button("…")` etc. werden automatisch erkannt — kein Umbau der SwiftUI-Views nötig.

## Dateien

| Target | Datei |
|--------|-------|
| Paperless24 | `Paperless24/Localizable.xcstrings` |
| PaperlessWidget | `PaperlessWidget/Localizable.xcstrings` |
| PaperlessShare | `PaperlessShare/Localizable.xcstrings` |

## String-Inventar

### Paperless24 (~52 Strings)

**Automatisch erkannte SwiftUI-Strings (kein Code-Umbau):**
- `"Login"`, `"Server"`, `"Benutzer"`, `"Passwort"`, `"FaceID"`, `"Suche..."`, `"Sender"`, `"Tags"`, `"Notizen"`, `"Dokument"`, `"Text"`, `"Übersicht"`, `"Dashboard"`, `"Posteingang"`, `"Uploads"`, `"Bearbeitungen"`
- `"Posteingang leer"`, `"Keine Dokumente gefunden"`, `"Keine Downloads"`, `"Kein OCR-Text vorhanden"`, `"Kein Sender"`, `"Keine"`, `"Leer"`, `"Geschützt"`
- `"Dokumente werden geladen..."`, `"Lade Dokument..."`, `"KI denkt..."`, `"Auto"`, `"Hell"`, `"Dunkel"`
- `"Letzte Dokumente"`, `"Zuletzt hinzugefügt"`, `"Alle"`, `"App Speicher"`
- `"Name für diesen Filter:"`, `"Tags:"`, `"Gib deinen Authentifikator-Code ein"`
- `"Offline – letzte Daten werden angezeigt"`, `"Zeigt Beispieldaten. Es wird keine Verbindung zum Server hergestellt."`
- `"Alle Dokumente haben einen Sender."`, `"Das letzte Konto kann nicht gelöscht werden. Melde dich stattdessen ab."`
- `"Neuer Tag"`, `"Neuer Sender"`, `"Neuer Typ"`, `"Warteschlange"`
- `"Posteingang"`, `"Dokumente"`, `"Zeichen"`, `"Letzte ASN"`
- `"Dokumente beim Start"`, `"Widget aktiv"`, `"Anzeige"`, `"Design"`

**Code-Strings (Umbau auf `String(localized:)`):**
- `"Dieses Konto ist bereits vorhanden"` → `String(localized: "account_already_exists")`
- `"Falscher Code"` → `String(localized: "wrong_otp_code")`
- `"Login fehlgeschlagen"` → `String(localized: "login_failed")`
- BiometricAuth-Reason `"Anmelden"` → `String(localized: "biometric_reason")`

**String-Interpolation mit Pluralform:**
- `"\(count) Dokumente"` — im Katalog als plural-fähiger String
- `"\(count) unbearbeitet"`
- `"\(count) Upload(s)"` (bereits mit Singular/Plural-Logik im Code)
- `"\(count) gewählt"`
- `"Fehler: \(err)"` → als `String(localized: "error_detail \(err)")`

### PaperlessWidget (~5 Strings)

- `"Posteingang"`, `"Dokumente"`, `"Sync"` (Label-Strings in statItem/overviewStat)
- Widget description: `"Zeigt deine zuletzt hinzugefügten Dokumente oder eine Übersicht."`
- Widget display name: `"Paperless24"`

### PaperlessShare (~3 Strings)

- `"Keine Daten gefunden."`
- `"Daten waren leer."`
- `"Fehler: \(err)"`, `"Speicherfehler: \(err)"`

## Xcode-Projekt-Konfiguration

1. *Project → Info → Localizations* → 4 Sprachen hinzufügen: Deutsch (de), Französisch (fr), Spanisch (es), Italienisch (it)
2. Development Language auf Englisch (en) setzen
3. Für jedes Target die `Localizable.xcstrings`-Datei zum jeweiligen Target-Membership hinzufügen

## .xcstrings-Format

```json
{
  "sourceLanguage": "en",
  "strings": {
    "Login": {
      "localizations": {
        "de": { "stringUnit": { "state": "translated", "value": "Login" } },
        "fr": { "stringUnit": { "state": "translated", "value": "Connexion" } },
        "es": { "stringUnit": { "state": "translated", "value": "Iniciar sesión" } },
        "it": { "stringUnit": { "state": "translated", "value": "Accedi" } }
      }
    }
  },
  "version": "1.0"
}
```

## Implementierungsreihenfolge

1. Xcode-Projekt: Development Language auf Englisch setzen, 4 weitere Sprachen hinzufügen
2. `Localizable.xcstrings` für alle 3 Targets anlegen (mit allen Strings + KI-Übersetzungen)
3. Code-Strings auf `String(localized:)` umstellen (LoginView, ContentView)
4. Plural-Strings für count-Interpolationen einrichten
5. Widget-Strings in Widget-Katalog eintragen

## Was sich NICHT ändert

- Alle SwiftUI `Text("…")`, `TextField("…")`, `Button("…")`, `Label("…")`, `.navigationTitle("…")` bleiben unverändert — der String-Literal wird automatisch als Lookup-Key verwendet
- Kein in-App-Sprachpicker — iOS-Standard-Mechanismus wird genutzt
- Keine externen Abhängigkeiten
