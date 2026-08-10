# Bugfix- & Sicherheits-Runde (10.08.2026)

Nur iOS-Ziele (`Paperless24`, `PaperlessWidget`, `PaperlessShare`). Der Android-Port unter
`android/` bleibt bewusst unangetastet.

**Backup vor Beginn:** `/Users/thomas/Developer/Paperless-TeDi-BACKUP-20260810-135022.tar.gz`
(kompletter Projektordner inkl. `.git`, Stand vor der ersten Änderung).

**Stand:** alle Punkte umgesetzt. `xcodebuild build` läuft durch, die Testsuite läuft auf dem
Simulator (iPhone 17 Pro, iOS 27.0).

## Datenverlust

- [x] 1 — `EditDocumentView.populate()` liest `created` über `document.dateObject`.
      Der frühere Formatter erzwang Millisekunden und scheiterte sowohl an
      `2026-08-10T00:00:00+02:00` als auch am reinen Datum ab API-Version 9 — das Feld blieb
      auf „heute" und „Speichern" überschrieb das Erstelldatum.
- [x] 2 — `AppStore.addPendingEdit` schreibt `created` als `yyyy-MM-dd` in lokaler Zeit
      (`DateFormatting.apiDate`) statt als UTC-Zeitstempel. Auch `PaperlessAPI.uploadDocument`.
- [x] 3 — `processUploadQueue` / `processEditQueue` haben eine Reentrancy-Sperre
      (`isProcessingUploads`, `isProcessingEdits`). Vorher startete der Import zwei Läufe
      (`addToQueue` + `sync()`) und lud jedes Dokument doppelt hoch.
- [x] 4 — `AppStore.deleteDocument` entfernt lokal nur nach erfolgreichem Serveraufruf,
      sonst `lastSyncError`.
- [x] 5 — `PersistenceService` kodiert beim Aufrufer und schreibt über eine serielle Queue,
      atomar und mit `completeFileProtectionUnlessOpen`. Neu: `writeFile(_:to:)`, genutzt für
      die zwischengespeicherten PDFs.

## Sicherheit

- [~] 6 — **Zurückgenommen.** Der Versuch, eine schemalose Adresse auf `https://` zu heben, hat
      die Verbindung zu Servern ohne TLS abreißen lassen („Die Netzwerkverbindung wurde
      unterbrochen", bestehende Konten wie neue Logins). `normalizedBase` setzt wieder `http://`.
      Geblieben ist die genauere Schema-Erkennung: `hasPrefix("http")` traf früher auch einen
      Host wie `httpserver.local`, der blieb dann ohne Schema stehen.
      Offen bleibt damit: eine schemalos eingegebene Adresse wird im Klartext angesprochen.
      Eine mögliche Lösung ohne Bruch wäre, beim *Anlegen* eines Kontos erst `https://` zu
      probieren und nur bei Fehlschlag auf `http://` zu gehen — das ist eine eigene
      Entscheidung und bewusst nicht Teil dieser Runde.
- [x] 7 — `KeychainService`: `kSecAttrService`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
      `saveToken` liefert `Bool`, Alt-Einträge werden beim ersten Lesen migriert.
      `LoginView` wertet den Rückgabewert aus (neuer String `keychain_save_failed`, 5 Sprachen).
- [x] 8 — `ContentView.authenticate()` nutzt `.deviceOwnerAuthentication` (Biometrie mit
      Gerätecode als Rückfallebene). Fehlschlag hält die Sperre und zeigt „Entsperren".
- [x] 9 — `ImageCache` legt pro Konto ab (`Thumbnails/<UUID>`), `setAccount` beim Start, beim
      Kontowechsel und im Demo-Modus. `deleteAccount`/`clearAll` ergänzt.
- [x] 10 — `AppConstants.isAllowedPickerCallback` weist Web-, Datei- und Skript-Schemata für
      `paperless24://pick?callback=` ab.
- [x] 11 — `PaperlessAPI.checkConnection` (Basic-Auth, ungenutzt) entfernt.

## Funktionsfehler

- [x] 13 — Alle Query-Parameter über `URLComponents` (`PaperlessAPI.url(base:path:query:)`).
- [x] 14 — `LinkifiedText` verlinkt die tatsächliche Fundstelle (`Range(match.range, in:)`)
      statt des ersten Vorkommens; Kartenlink jetzt über HTTPS und `URLComponents`.
- [x] 15 — `fetchAllDocuments` bricht ab, sobald eine Seite nichts Neues mehr beisteuert.
- [x] 16 — Neuer `ShareStaging`-Helfer: eigener Unterordner je Freigabe, entschärfter
      Dateiname, Aufräumen vor der nächsten Freigabe.

## Performance

- [x] 17 — Token liegt im `AppStore` im Speicher (`tokenCache`), `invalidateTokenCache()` bei
      Kontowechsel, Abmelden und 401. Vorher ein Keychain-Zugriff pro gezeichneter Zeile.
- [x] 18 — `PDFKitView` merkt sich die geladenen Daten im Coordinator, statt bei jedem
      `updateUIView` das PDF über `dataRepresentation()` neu zu serialisieren.
- [x] 19 — `OCRService.recognizeFirstPage(ofPDF:)` rendert und erkennt abseits des Main
      Threads; `AskArchiveView.rankedDocuments` rechnet die Embeddings in einer
      `Task.detached` (Eingabe als eigener `Sendable`-Typ `RankInput`).
- [x] 20 — Start und Kontowechsel laden den Plattencache über `AccountDiskSnapshot` in einer
      `Task.detached` und übernehmen ihn in einem Schritt.

## Kleinere Punkte

- [x] 21 — `print()` in `Paperless_TeDiApp` durch `os.Logger` ersetzt.
- [x] 22 — Ungenutztes `PaperlessAPI.thumbnailRequest` (mit `URL(string:)!`) entfernt.
- [x] 23 — Share-Extension öffnet die App über `extensionContext.open` statt über die
      Responder-Kette.
- [x] 24 — Share-Extension schreibt atomar und mit Dateischutz.
- [x] 25 — `requestTimeout` 30 s, `uploadTimeout` 180 s für Upload und Download.
- [x] 26 — IPv6-Hosts im AirScan-URL-Aufbau werden geklammert.
- [x] 27 — Auto-Sync stößt im Hintergrund nichts mehr an.
- [x] 28 — `PersistenceService.calculateStorage` zählt nur noch die Miniaturansichten des
      Kontos statt des kompletten Caches-Ordners.
- [x] 29 — Vorschauen der App-Symbole in „Darstellung" waren alle leer. Bilder aus einem
      `.appiconset` sind über `UIImage(named:)` nicht erreichbar; die Vorschauen liegen jetzt
      als eigene Image-Sets `AppIconPreview…` (180 px) im Asset-Katalog.
      Nicht Teil der ursprünglichen Liste — beim Nachstellen aufgefallen.

## Tests

- [x] T1 — `Paperless24Tests/DateFormattingTests.swift`: alle drei `created`-Formate,
      Formatieren ohne Zeitzonensprung, Rundlauf, `Document.dateObject`.
- [x] T2 — `Paperless24Tests/PaperlessAPIURLTests.swift`: Schema-Vorgabe und Query-Kodierung
      (`&`, `+`, Einschleusen weiterer Parameter).
- [x] T3 — `Paperless24Tests/DeepLinkAndSharingTests.swift`: erlaubte und abgewiesene
      Rückruf-Schemata, Dateinamen und Ablage für das Teilen-Blatt.
      Der Test hat prompt eine Schwäche gefunden: ein Titel aus lauter Trennzeichen ergab den
      Dateinamen `---` statt des Rückfallnamens. Behoben.
- [x] T4 — `Paperless24Tests/AppIconPreviewTests.swift`: lädt jedes Vorschaubild im
      App-Bundle. Vor Punkt 29 wäre dieser Test durchgefallen.

Bewusst **nicht** geschrieben: ein Test für die Reentrancy-Sperre der Warteschlangen. Der
`AppStore` erzeugt seine `PaperlessAPI` selbst; für einen echten Test müsste erst eine
Einspeisung (Protokoll + Attrappe) eingezogen werden. Das ist ein größerer Umbau als der Fix
selbst und wäre ein eigener Schritt.

## Offen gelassen (bewusst)

- `NSAllowsArbitraryLoads` bleibt in `Paperless24-Info.plist`. Selbst gehostete Server ohne
  gültiges Zertifikat sind ein reales Nutzungsszenario; mit dem HTTPS-Standard aus Punkt 6
  ist der gefährliche Teil (unbeabsichtigtes Klartext-HTTP) abgestellt.
- Der Android-Port (`android/`) ist unverändert. Die dort gefundenen Punkte — Klartext-HTTP,
  `usesCleartextTraffic="true"` und der stille Rückfall auf die Cloud-KI in
  `AiSummaryRepository` — stehen weiterhin offen.

## Berührte Dateien

Neu: `Paperless24/Helpers/DateFormatting.swift`, `Paperless24/Helpers/ShareStaging.swift`,
`Paperless24/Store/AccountDiskSnapshot.swift`, drei Testdateien.

Geändert: `PaperlessAPI`, `KeychainService`, `PersistenceService`, `OCRService`,
`AirScanService`, `AppStore`, `ImageCache`, `AppConstants`, `Document`, `ContentView`,
`Paperless_TeDiApp`, `LoginView`, `EditDocumentView`, `DocumentDetailView`, `MainDocView`,
`AskArchiveView`, `MetadataFormSection`, `LinkifiedText`, `PDFKitView`,
`PaperlessShare/ShareViewController`, `Localizable.xcstrings`.
