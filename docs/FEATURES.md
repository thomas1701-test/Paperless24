# Paperless 24 — Funktionsübersicht

Stand: 12.09.2026 · App-Version 2.1.4 (iOS)

Quelle: Code-Inventur über `Paperless24/`, `PaperlessShare/`, `PaperlessWidget/`.
Nur Funktionen, die tatsächlich im Code existieren.

---

## 1. Konten & Sicherheit

| Funktion | Details | Code |
|---|---|---|
| Login | Server-URL, Benutzer, Passwort → `/api/token/`, http:// wird ergänzt wenn Schema fehlt | `Views/Auth/LoginView.swift`, `Services/PaperlessAPI.swift` |
| 2FA / TOTP | Erkennt OTP-Pflicht aus der 400/401-Antwort, blendet Code-Feld ein | `PaperlessAPI.fetchToken` |
| Token-Speicher | iOS Keychain, Schlüssel pro Server + Benutzer | `Services/KeychainService.swift` |
| Multi-Account | Mehrere Server/Benutzer, Umschalten, Entfernen, getrennte Datenordner je Konto | `Store/AppStore.swift`, `Services/AccountService.swift`, `Views/Settings/AccountsView.swift` |
| Migration | Einmalige Übernahme alter Einzel-Konto-Installationen (`migrated_to_v2`) | `AppStore.init` |
| Face ID / Touch ID | Optionale Sperre, erneute Abfrage nach 60 s im Hintergrund, Weichzeichner beim Verlassen der App | `App/ContentView.swift` |
| Auto-Relogin | Bei 401 wird der Token verworfen und der Login-Screen gezeigt | `AppStore.loadFirstPage` |
| Demo-Modus | Beispieldaten ohne Serververbindung | `AppStore.setupDemoData` |

## 2. Dokumentenliste

- Raster- und Listenansicht, umschaltbar; Kachelgröße 90–260 pt einstellbar
- Seitenweises Laden (Infinite Scroll), Seitengröße 25 / 50 / 100 / 250 / 500 / 1000 / 2000 / alles
- Sortierung: Datum ⇅, Titel, Sender, Hinzugefügt ⇅ — jeweils mit `id` als eindeutigem Zweitkriterium (nötig seit API 9, `created` ohne Uhrzeit)
- Filter: Tag, Sender, Typ, eigenes Feld (+ Textvergleich), Zeitraum (letzter Monat, dieses Jahr, freier Bereich)
- Gespeicherte Ansichten vom Server: laden, anwenden, anlegen, löschen; alte lokale Filter werden einmalig hochmigriert
- Volltextsuche über `?query=` mit 400 ms Entprellung, eigener Such-Paginierung und den letzten 8 Suchbegriffen als Vorschläge
- Offline: lokale Suche über Titel und OCR-Text der zwischengespeicherten Dokumente
- Auswahlmodus mit Sammelaktionen: Tag zuweisen, Sender zuweisen, teilen, löschen
- Wischgesten: löschen, bearbeiten, Schnell-Tag
- Kontextmenü: bearbeiten, Vorschau (QuickLook-Sheet), löschen
- Zum Aktualisieren ziehen
- Drag & Drop von Dokumenten in andere Apps (iPad)
- Posteingang als eigener Tab mit Badge (Definition: Dokumente mit einem Tag, das auf dem Server `is_inbox_tag` trägt — wie in der Weboberfläche; die Zahl kommt aus `/api/statistics/`)
- Dubletten-Schutz in der Liste (`Array+UniqueByID`) — verhindert doppelte Einträge bei instabiler Server-Sortierung

## 3. Dokumentansicht

Vier Reiter: **Dokument · Text · Info · Notizen**

- PDF-Anzeige über PDFKit, Suchbegriff wird im Dokument hervorgehoben
- OCR-Text mit anklickbaren Telefonnummern, Links und Adressen (`LinkifiedText`)
- Info-Reiter: Metadaten, eigene Felder, KI-Zusammenfassung auf Knopfdruck
- Notizen: anlegen und löschen
- Teilen: PDF über das System-Share-Sheet
- Freigabe-Links: erstellen (mit Ablaufdatum und Dateiversion), auflisten, widerrufen
- Übersetzen: `translationPresentation` (on-device, abschaltbar)
- Bearbeiten: Titel, Datum, Sender, Typ, ASN, Tags, eigene Felder
- Ladefehler wird mit Grund und „Erneut versuchen" angezeigt statt Endlos-Spinner

## 4. Erfassen & Importieren

| Weg | Details |
|---|---|
| Kamera-Scan | VisionKit-Dokumentenscanner, mehrseitig |
| Foto | Auswahl aus der Fotobibliothek, Umwandlung in PDF |
| Datei | PDF-Import über den Dateiauswahldialog |
| Netzwerkscanner | AirScan/eSCL über Bonjour (`_uscan._tcp`), 300 dpi, PDF oder Bild→PDF (`Services/AirScanService.swift`) |
| Stapel-Scan | Mehrere Seiten am Stück, KI gruppiert sie zu einzelnen Dokumenten, manuelle Korrektur per Stepper (`Views/Shared/BatchScanView.swift`) |
| Share Extension | Import aus jeder App über die App Group (`PaperlessShare/`) |
| URL-Schema | `paperless24://check_shared`, `document?id=`, `exchange`/`import`, `pick?callback=` (Dokumentauswahl für Vermietoo, auch mehrfach) |

**Upload-Formular:** Titel, Datum, Sender, Typ, Tags — jeweils mit durchsuchbarem Picker und Direktanlage neuer Einträge.

**Auto-Tagging (Zauberstab):** Vision-OCR der ersten Seite → Apple Intelligence extrahiert Titel, Sender, Typ, Tags, Datum; fehlende Sender/Typen/Tags werden automatisch angelegt. Fallback ohne Apple Intelligence: Stichwortabgleich + `NSDataDetector` fürs Datum.

**Warteschlangen:** Uploads und Änderungen werden lokal gepuffert, bei Verbindung automatisch abgearbeitet, alle 30 s erneut versucht; eigene Verwaltungsansicht (`PendingQueueView`).

## 5. Intelligenz (on-device)

| Funktion | Technik | Ort |
|---|---|---|
| Zusammenfassung | Apple Intelligence (`FoundationModels`), max. 3 Sätze | Info-Reiter |
| Auto-Metadaten | Apple Intelligence, JSON-Ausgabe | Import & Bearbeiten |
| Stapel-Trennung | Apple Intelligence gruppiert Seiten nach Briefkopf | Stapel-Scan |
| Archiv fragen | `NLEmbedding`-Satzähnlichkeit rankt Top-5-Dokumente, danach LLM-Antwort mit Quellenliste | `AskArchiveView` |
| Übersetzen | Apple `Translation`-Framework | Dokumentansicht |
| Texterkennung | Vision (`OCRService`), auch ohne Apple Intelligence nutzbar | Scan-Wege |

Verständliche Fehlermeldungen, wenn das Modell fehlt, der Text zu lang ist, der Sicherheitsfilter greift oder die Sprache nicht unterstützt wird. Alles über einen Schalter in den Einstellungen deaktivierbar.

## 6. Plattform-Integration

- **Widget** (`PaperlessWidget/`): zwei Modi — letzte Dokumente oder Übersicht (Posteingang, Gesamtzahl, letzte Synchronisation); an-/abschaltbar; Tippen öffnet das Dokument per URL-Schema
- **Siri & Kurzbefehle** (`Intents/AppShortcuts.swift`): Dokument scannen, Posteingang öffnen, Dokumente suchen, Archiv fragen
- **Spotlight**: bis zu 10.000 Dokumente inkl. 15.000 Zeichen OCR-Text, Sender als Autor, Tags/Typ als Schlagworte, Vorschaubild (bis zu 400 werden je vollem Lauf nachgeladen); der erste Lauf je Konto blättert durch das ganze Archiv, eigener Indexbereich je Konto; Treffer öffnet das Dokument in der App
- **Benachrichtigungen**: `BGAppRefreshTask` prüft stündlich die Posteingangszahl und meldet Zuwachs lokal
- **iCloud-Einstellungssync**: `NSUbiquitousKeyValueStore` für Darstellung, Sprache, Seitengröße, KI-Schalter usw.
- **iPad/Mac**: Dreispalten-Layout (Filter-Seitenleiste · Liste · Detail), nur auf echten Tablets/Macs aktiv
- **Haptik**, **Sprachen**: DE, EN, FR, ES, IT mit eigener Auswahl in den Einstellungen

### Darstellung (Einstellungen › Farbthema & Darstellung)

- Sechs Farbthemen: Indigo (Standard), Ozean, Wald, Sonnenuntergang, Graphit, Kontrast — jeweils mit eigener Akzentfarbe für hell und dunkel plus passendem Hintergrundverlauf
- Freie Akzentfarbe über den Farbwähler (`custom`), als Hex gespeichert und über iCloud synchronisiert
- Erscheinungsbild Auto / Hell / Dunkel bleibt unverändert erhalten
- Schwarzer Hintergrund (OLED): ersetzt im Dunkelmodus das Systemgrau durch echtes Schwarz
- PDF im Dunkelmodus abdunkeln (Invertierung + Farbtondrehung, ohne private API)
- Lesemodus für den OCR-Text: warmer Papierton, Serifenschrift, einstellbare Schriftgröße 14–26 pt
- Fünf alternative App-Symbole passend zu den Themen
- Live-Vorschau der Auswahl mit Chips und Beispielkarte
- Das Widget übernimmt die Akzentfarbe (die App legt sie fertig aufgelöst in der App Group ab)
- Tag-Farben vom Server bleiben unangetastet
- Technik: `Helpers/Theme.swift` (`AppTheme`, `ThemeSettings`, `ThemePalette`, `@Environment(\.palette)`), Tests in `Paperless24Tests/ThemeTests.swift`

## 7. Offline

- Dokument-Cache pro Konto im Dateisystem
- „Alle Dokumente herunterladen" mit Fortschritt und Abbruch
- Speicherverbrauch und Anzahl zwischengespeicherter Dateien in den Einstellungen, Einzelverwaltung in `OfflineDocsView`
- Offline-Banner, letzte Daten bleiben nutzbar, Änderungen laufen in die Warteschlange
- Metadaten (Tags, Sender, Typen, eigene Felder, Filter) werden als JSON je Konto gespeichert

## 8. Verwaltung

- Tags: Liste mit Suche, Anlegen, Löschen, hierarchische Darstellung verschachtelter Tags
- Sender und Typen: Liste mit Suche, Anlegen, Löschen
- Papierkorb: Ansicht, Wiederherstellen, endgültig löschen
- Eigene Felder: alle Typen anzeigen und bearbeiten (Text, Zahl, Datum, Auswahl, Ja/Nein, Dokumentverknüpfung, Währung u. a.), Filter danach
- Statistik-Kacheln: Posteingang, Dokumente gesamt, Zeichenzahl, höchste ASN
- Spotlight-Index neu aufbauen
- Changelog, Unterstützungsseite (PayPal-Trinkgeld), App-Bewertung mit Gating-Logik (`ReviewRequestService`)

## 9. Server-Kompatibilität

- API-Versionsaushandlung pro Server: bevorzugt `version=9`, wertet `X-Api-Version` aus, fällt bei 406 dauerhaft auf den Server-Standard zurück (`APIVersionNegotiator`)
- Unterstützt paperless-ngx 2.x bis 3.0.x
- Genutzte Endpunkte: `token`, `documents` (Liste, Detail, Suche, Download, Upload, PATCH, DELETE), `tags`, `correspondents`, `document_types`, `custom_fields`, `saved_views`, `share_links`, `trash`, `notes`, `statistics`, `thumb`

## Was die App bewusst *nicht* kann (Stand heute)

- Keine Berechtigungen/Besitzer (owner, view/edit permissions)
- Keine Speicherpfade (storage paths), Workflows, E-Mail-Regeln, Benutzer/Gruppen
- Kein Sammel-Endpunkt `bulk_edit` — Sammelaktionen laufen als Einzel-PATCH
- Keine Seitenbearbeitung (drehen, löschen, teilen, zusammenführen) am Server
- Kein Verarbeitungsstatus nach dem Upload (`/api/tasks/`)
- Keine ngx-eigenen Vorschläge (`/api/documents/{id}/suggestions/`)
- Kein mTLS, keine eigenen HTTP-Header (Cloudflare Access, Authelia, Basic-Auth-Proxy)
- Kein echtes Server-Push (nur stündliches Polling im Hintergrund)
- Kein ASN-Barcode-Scanner, keine Dublettenprüfung beim Scannen
- Kein Zugriff auf ngx-3.0-Neuerungen: Dateiversionen, Sharelink-Bundles, Server-KI/Chat, ähnliche Dokumente
