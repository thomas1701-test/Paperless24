# App-Store-Eintrag

Texte und Bild-Pipeline für App Store Connect. Stand: 10.08.2026, App-Version 2.1.3.

## Texte

Je Sprache ein Ordner, ein Feld pro Datei — dieselbe Struktur wie `fastlane deliver`.

| Datei | Feld in App Store Connect | Grenze |
|---|---|---|
| `name.txt` | App-Name | 30 |
| `subtitle.txt` | Untertitel | 30 |
| `keywords.txt` | Keywords (kommagetrennt, keine Leerzeichen) | 100 |
| `promotional_text.txt` | Werbetext (ohne neue Version änderbar) | 170 |
| `description.txt` | Beschreibung | 4000 |
| `release_notes.txt` | Neue Funktionen | 4000 |

Längen prüfen:

```bash
for f in docs/appstore/*/*.txt; do printf '%-38s %5d\n' "$f" "$(wc -m < "$f")"; done
```

Weitere Felder, die nicht in Dateien liegen:

- Support-URL: `https://thomas1701-test.github.io/Paperless24/support.html`
- Marketing-URL: `https://thomas1701-test.github.io/Paperless24/`
- Datenschutz-URL: `https://thomas1701-test.github.io/Paperless24/privacy.html`
- Impressum (kein eigenes Feld in App Store Connect, aber aus Marketing-, Support- und
  Datenschutz-Seite verlinkt): `https://thomas1701-test.github.io/Paperless24/impressum.html`

  (Die Seiten liegen in `docs/` und werden über GitHub Pages ausgeliefert — vor der
  Einreichung prüfen, ob Pages für das Repository aktiv ist und die URLs wirklich laden.)
- Kategorie: Produktivität (primär), Dienstprogramme (sekundär)
- Datenschutz-Angaben: keine Datenerfassung — die App spricht nur mit dem Server des Nutzers

## Screenshots

Die Bilder entstehen im **Demo-Modus** aus `Paperless24/Services/DemoDataService.swift`. Alle
Absender, Beträge und Adressen darin sind erfunden; es werden keine echten Daten abgelichtet.

### 1. Rohe Aufnahmen erzeugen

`Paperless24UITests/StoreScreenshotTests.swift` fährt die App durch und hängt die Bilder ans
Testergebnis. Je Gerät und Sprache ein Lauf:

```bash
xcodebuild test -project "Paperless 24.xcodeproj" -scheme Paperless24 -only-testing:Paperless24UITests/StoreScreenshotTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -parallel-testing-enabled NO -resultBundlePath out.xcresult
```

Vorher am Simulator die Statusleiste festnageln und die App neu installieren:

```bash
xcrun simctl status_bar <UDID> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
```

Sprache: Simulator auf `en-US` stellen (`defaults write -g AppleLanguages -array en-US`,
danach neu starten) — der Test erkennt die Sprache selbst und tippt die passenden
Beschriftungen an. `DemoDataService` liefert dann auch englische Beispieldokumente.

Bilder aus dem Ergebnis holen:

```bash
xcrun xcresulttool export attachments --path out.xcresult --output-path bilder
```

Die Dateinamen stehen in `bilder/manifest.json` unter `suggestedHumanReadableName`.

### 2. Rahmen und Schlagzeilen

`frame_shots.py` legt den Farbverlauf, die Schlagzeile und den Schatten dazu. Die Texte je
Bild stehen oben in der Datei in `SLIDES`.

```bash
python3 docs/appstore/frame_shots.py
```

Erwartet die rohen Aufnahmen in `shots_de/`, `shots_iphone_en/`, `shots_ipad_de/`,
`shots_ipad_en/` neben dem Skript und schreibt nach `store/<locale>/<gerät>/`.

### Größen

| Gerät | Simulator | Auflösung |
|---|---|---|
| iPhone 6.9" | iPhone 17 Pro Max | 1320 × 2868 |
| iPad 13" | iPad Pro 13-inch (M5) | 2064 × 2752 |

Apple skaliert die 6.9"-Bilder für kleinere iPhones herunter; eine zweite iPhone-Größe ist
nicht nötig. Die iPad-Bilder braucht der iPad-Store separat.
