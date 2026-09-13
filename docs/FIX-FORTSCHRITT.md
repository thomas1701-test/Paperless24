# Fix-Fortschritt zur Codeprüfung 12.09.2026

Arbeitsliste zu `docs/AUDIT-2026-09-12.md`. Wird nach **jedem** Fix aktualisiert, damit ein abgebrochener
Lauf nahtlos weitergeht. Nichts davon ist committet. Branch `release/2.2.0` (früher `feature/android-port`), Basis `fd10e25`.

**Wiederaufnahme:** `git status` / `git diff` zeigen den Stand. Tests:
`xcodebuild test -project "Paperless 24.xcodeproj" -scheme Paperless24 -destination 'platform=iOS Simulator,id=D86B4B7C-0B7E-4032-B6A7-9140ABBB8222' -only-testing:Paperless24Tests -derivedDataPath .claude/audit/build/dd`
(Der Simulatorstart hängt gelegentlich nach dem Build. Dann den Prozess beenden und neu starten.)

## Erledigt

| # | Befund | Stand | Tests |
|---|---|---|---|
| 1 | B1 Warteschlange geht beim Start verloren | fertig | `QueuePersistenceTests` (Gegenprobe: ohne Fix rot) |
| 2 | B3 abgelehnte Anfrage blockiert Warteschlange | fertig | `WriteResponseClassificationTests`, `RejectedQueueItemTests` |
| 3 | S1 Rechte-Dialog entfernt Besitzer | fertig | – (API nicht einspeisbar) |
| 4 | S3 Freigabe-Link „widerrufen" scheitert still | fertig | – |
| 5 | B2/S2 Kontowechsel bei laufender Arbeit | fertig (128 Tests grün, `full-r2`) | `AccountSwitchTests` (lokale HTTP-Server) |
| 6 | B6 Serverzugang vor dem Login | fertig (128 Tests grün, `full-r2`) | – (UI) |
| 7 | B7 Vorschaubilder ohne Kopfzeilen/Zertifikat | fertig (128 Tests grün, `full-r2`) | `ServerCredentialsTests.vorschauNutzt…` |
| 8 | S4 Kopfzeilen im Klartext, bleiben nach Abmelden | fertig (128 Tests grün, `full-r2`) | `ServerCredentialsTests` |
| 9 | B4 Bearbeiten löscht leere eigene Felder | fertig (137 Tests, `full-r3`) | `EditPatchTests` |
| 10 | B5 PATCH überschreibt Server-Änderungen | fertig (137 Tests, `full-r3`) | `EditPatchTests` |
| 11 | B8 Löschen ohne Rückfrage (Tags/Sender/Typen, Sammellöschen) + Sammellöschen per bulk_edit | fertig (`full-r3`) | – (UI) |
| 12 | neu: Rückmeldung von Sammelaktionen wurde nie angezeigt (`bulkResultMessage`) | fertig (`full-r3`) | – |
| 13 | B10 Face-ID-Abbruch beim Kaltstart hängt | fertig (`full-r3`) | – (UI) |
| 14 | B11 ASN-Barcode, Vermietoo-Auswahl aus `filteredDocs`, Datumsformatierer ohne POSIX | fertig (`full-r3`) | `ASNBarcodeTests` |
| 15 | S5 Kurzbefehle liefern Daten bei gesperrtem Gerät | fertig (`full-r3`) | – |
| 16 | S6 Picker-Rückruf per Browser-Schema umgehbar | fertig (`full-r3`) | `PickerCallbackTests.rejectsBrowserSchemes` |
| 17 | neu: Betragsfelder „12,50 €" → `12.50` (sonst 400) | fertig (`full-r3`) | `EditPatchTests.betraegeInServerform` |
| 18 | P1 Upload-Bytes in pending.json | fertig (139 Tests, `full-r4`) | `UploadStorageTests` |
| 19 | P4 LinkifiedText / SeriesView / Fristen-Vorschläge auf dem Main Thread | fertig (`full-r4`) | – |
| 20 | B9 Hintergrund-Benachrichtigungen ohne Store; Badge nie zurückgesetzt; Vergleichswert blieb auf Höchststand | fertig (139 Tests, `full-r5`) | – |
| 21 | P3 Archivindex als 50-MB-JSON, nach jeder Seite neu geschrieben | fertig (142 Tests, `full-r6`) | `ArchiveIndexTests` |
| 22 | P2 Scans in voller Kameraauflösung als Bitmap | fertig (144 Tests, `full-r7`) | `ScanPDFTests` |
| 23 | S7 (Teil) VoiceOver hinter App-Sperre; Widget-Daten nach Abmelden/Kontowechsel | fertig (`full-r7`) | – |
| 24 | P5 Pager-Fenster, P6 decodePage / fetchAllDocuments / ein Toast je Durchlauf | fertig (147 Tests, `full-r8`) | `DecodePageTests` |
| 25 | B11-Rest: verschluckte Fehler (Papierkorb, Stammdaten löschen, Ansicht löschen), archiveSignature | fertig (`full-r8`) | – |
| 26 | Share-Extension: nur erster Anhang, gemeinsame Datei überschrieben, ganze Datei im Speicher | fertig (148 Tests, `full-r9`) | `SharedImportsTests` |
| 27 | P4-Rest (PDF/Vorschau lesen im Hintergrund), Multipart-Dateiname, kein stilles „heute", Kurzbefehl-IDs, Fristen > 250 | fertig (150 Tests, `full-r10`) | `MiscFixTests` |
| 28 | Kleinkram: `activeQuery` je Filterlauf, Tag-Hierarchie O(T) + Zyklusschutz, OfflineDocsView, Dublettenprüfung und Spotlight-Vorschauen im Hintergrund, Spotlight ohne Volltext bei App-Sperre, URLCache beim Abmelden | fertig (151 Tests, `full-r11`) | `TagHierarchyTests` |
| 29 | Übersetzungen für neue Texte (en/es/fr/it) | fertig (151 Tests, `full-r12`) | – |
| 30 | Warnungen: veraltetes `onChange`, überflüssige `??`; dabei gefunden: „Nächste freie ASN" lieferte in Archiven ohne ASN nichts statt 1 | fertig (`full-r13`) | – |
| 31 | B2-Randfall: hin- und zurückwechseln während Upload → doppelter Upload, Eintrag blieb | fertig (`b2-back`, Gegenprobe rot) | `AccountSwitchTests.hinUndZurueckWaehrendUpload` |
| 32 | B2-Randfall ganze Suite | fertig (152 Tests, `full-r14`) | – |
| 33 | Widget: `paperless24://inbox` unbehandelt; `widget_enabled` ohne Wert = aus | fertig (154 Tests, `full-r15`) | – |
| 34 | Import-Regeln je Konto | fertig (`full-r15`) | – |
| 35 | Erinnerungs-Alarm in der Vergangenheit | fertig (`full-r15`) | `ReminderAlarmTests` |

Gegenprobe B2 (`b2-neg2`): ohne Epochen-Prüfung in `loadFirstPage` rot (A-Dokument in Liste und Plattencache von B). Der Upload-Teil wurde in der Probe nur halb zurückgebaut und dort nicht separat belegt.

## In Arbeit / Nächste Schritte

### Runde 3 (13.09.2026) – Nutzerentscheidungen + neue Meldungen
**Simulator:** `F37ED3E3…` (iPhone 17 Pro 26.5, gebootet) benutzt der Nutzer selbst (Konto „thomas" auf seinem Server).
Tests ab jetzt NUR auf `0B2A7927-ECC0-4481-BA6D-AA1F468A7AE3` (iPhone 17, 26.5): `SIM=0B2A7927-ECC0-4481-BA6D-AA1F468A7AE3 .claude/audit/runtests.sh …`
- [x] N1 Suchfeld verschwindet: nachgestellt per `SearchFieldUITests` (Demo-Modus) — rot bei *Detail offen → Tabwechsel → zurück* und *Scan-Tab → Scanner schließen*; Fix `.searchable(placement: .navigationBarDrawer(displayMode: .always))` in MainDocView → grün
- [x] N2 Einstellungen gegliedert: Startseite = Dashboard, Warteschlange (nur wenn etwas wartet), Konto (Konten, Serverzugang), Kategorien Archiv verwalten / Offline & Laden / KI & Automatik / Darstellung (AppearanceView + Angaben in der Liste + Sprache) / Mitteilungen & Widget / Datenschutz & Spotlight / Hilfe & Info. Neue Datei `Views/Settings/SettingsCategoryViews.swift`. Abmelden jetzt mit Rückfrage. `SettingsCategoriesUITests`, AppearanceUITests/StoreScreenshotTests angepasst
- [x] N3 Sortieren: Ursache in `AppStore` — ohne Filter übernahm der Schnellpfad in `updateFilteredDocs` die Liste unverändert („schon vom Server sortiert"), es wurde nie neu geladen → Tipp ohne Wirkung; mit Filter galt ein Sortierwechsel als gleiche Anfrage. Fix: `listSortOrder`/`lastAppliedQueryOrder`, `reloadIfSortOrderChanged()` (sofort lokal umsortieren, dann erste Seite in neuer Sortierung vom Server), veraltete Antworten verworfen, Nachladen erst nach passender erster Seite. Tests `sortierwechselLaedtVomServer`, `sortierwechselBeiAktivemFilter` (vorher rot) + `SortMenuUITests`
- [x] E1 Login/Konto hinzufügen: https Standard, Schalter „Unverschlüsselt verbinden (http)"; eingefügtes `http://` schaltet ihn NICHT ein (Hinweis), `https://` setzt ihn zurück; Bestandsadresse ohne Schema → Schalter an + gespeicherte Schreibweise wird wiederverwendet (kein Doppelkonto). `Helpers/ServerAddress.swift`, `ServerAddressTests`, `LoginSchemeUITests`
- [x] E2 KI-Vorschläge: vorhandene Einträge direkt, fehlende → Sheet „Neu anlegen?" mit Schalter je Eintrag (`MetadataFormSection.proposalSheet`, `Helpers/SuggestionResolver.swift`); Fehler beim Anlegen werden gemeldet. `SuggestionResolverTests`. UI nicht getestet (braucht KI + Server)
- [x] E3 Datenschutz & Spotlight: „In Spotlight aufnehmen", „Volltext durchsuchbar" (aus bei App-Sperre), App-Sperre umschaltbar (verlangt Face ID/Code); Änderung baut Index neu (`AppStore.applySpotlightSettings`). `SpotlightSettingsTests`
- [x] N4 Unterstützungsseite: „kostenlos" + PayPal-Trinkgeld raus (Kauf-App, Richtlinie 3.1.1; Nutzer wählte „ohne PayPal"), jetzt Dank für den Kauf + „App bewerten" + „App weiterempfehlen" (ShareLink auf Store-Seite). Übersetzt, alte Katalogeinträge entfernt, `docs/FEATURES.md` angepasst. 166 Tests grün (`full-r20`), UI-Test prüft Seite (`ui10`)
- [x] Übersetzungen en/es/fr/it für 45 neue Texte; mit `+` zusammengesetzte Fußzeilen zu einem Text zusammengefasst (vorher gar nicht übersetzbar)

- **Stand 13.09.: alles getestet — 166 Unit-Tests grün (`full-r19`, Test-Simulator), UI-Tests grün (`ui8`/`ui9`). Nichts committet.**
- Entscheidungen 1–3 umgesetzt (E1–E3). Offen: Commit/Branch (`feature/android-port` ist ein irreführender Name).
- Mit echtem Server/Gerät noch nicht geprüft: S1 Rechte, B6 Login hinter Proxy, B7 Vorschaubilder hinter Proxy, B8
  Dialoge, B9 Hintergrundlauf, B10 Face ID, Share-Extension mit mehreren Dateien, Widget-Tipp, P2 Scanqualität, E2-Dialog mit echter KI, N3 Sortierung gegen echten Server, App-Sperre-Schalter mit Face ID.
- Tests: `.claude/audit/runtests.sh <log> ['Suite/test()']` (Testnamen mit Klammern in Anführungszeichen!).

## Protokoll

- **B1/B3/S1/S3** – Details im Abschnitt „Umsetzung" des Berichts.
- **B2/S2** – `AppStore.accountEpoch` + `isCurrent(_:)`; `beginNewAccountEpoch()` in `switchAccount`,
  `removeAccount`, `clearLocalData`, `setupDemoData` (bricht Suche/Download/Spotlight/Auto-Sync ab und leert
  den flüchtigen Zustand: Posteingang, Suchverlauf, Upload-Status, Benutzer/Gruppen, Speicherpfade, Fehler,
  Offline). Epochen-Prüfung nach jedem `await` in Sync, erste Seite, Nachladen, Suche, Posteingang,
  Stammdaten, Sammelaktionen, eigene Felder, Speicherpfade/Server-Metadaten, Papierkorb, gespeicherte
  Ansichten, Filter-Migration, Löschen, Archivindex, Spotlight, Komplett-Download, Speicherberechnung,
  Fristen (`confirmDeadline`). Die Warteschlangen binden `api` einmal. Was nach einem Wechsel noch übertragen
  wurde, wird per `PersistenceService.removeQueued` aus der Datei des alten Kontos genommen. Der Sync wird
  nicht abgebrochen (ein gekappter Upload könnte schon angekommen sein und später doppelt hinausgehen). Das
  401 löscht den Token des Kontos der Anfrage. `ArchiveIndex`-Methoden nehmen das Konto als Parameter (kein
  separates `use(account:)` mehr). PDF-Ablageort wird vor dem Download festgehalten (`loadPDFData`,
  `DocumentDetailView`). `AccountDiskSnapshot` wartet auf ausstehende Schreibvorgänge.
  Nebenbei: Filter-Migration entfernt nur erfolgreich übernommene Filter und läuft nicht doppelt;
  gelöschte Dokumente fliegen aus dem Archivindex.
- **B6/B7/S4** – `ServerAccessView(server:dismissAfterSave:)` statt `store.makeServerBase()`; Login-Bildschirm
  hat Knopf „Serverzugang (Proxy, Zertifikat)" (Sheet, Adresse = eingegebene Serveradresse normalisiert).
  `ServerCredentials`: Kopfzeilen im Schlüsselbund (`de.tedi.paperless.headers`, `…ThisDeviceOnly`), In-Memory-Cache,
  Umzug aus `customHeaders.<server>` in den UserDefaults beim ersten Lesen, `removeAll(for:)` (Kopfzeilen, Zertifikat,
  Session). `clearLocalData` räumt für alle Konten, `removeAccount` nur wenn kein anderes Konto denselben Server nutzt.
  `ClientCertSessionProvider` merkt sich, ob ein Zertifikat existiert (vorher Schlüsselbund-Abfrage je Anfrage).
  `AuthImage` lädt über `ClientCertSessionProvider`-Session mit eigenen Kopfzeilen, prüft HTTP 200 und legt nur ab,
  wenn das Konto noch dasselbe ist (`ImageCache.saveImage(_:for:ifAccount:)`).
- **B4/B5** – `PendingEdit.changedFields` (API-Feldnamen) und `existingFieldIDs`, berechnet in `addPendingEdit` gegen den
  angezeigten Stand (`anyLoadedDocument`); unverändert → keine Warteschlange. `PaperlessAPI.patchDocument(_ edit:)` +
  `patchBody(for:)`: nur geänderte Felder; `custom_fields` enthält vorhandene Felder auch leer (`null`), neue leere nicht.
  `PendingEdit.applied(to:)` wendet nur geänderte Felder an (auch `reApplyPendingEdits`). Einträge alter Versionen
  (`changedFields == nil`) schreiben wie früher alles. Betragsfelder: `AppStore.normalizedForServer`.
- **B8/Sammelaktionen** – `confirmMetadataDeletion` (TagListView.swift) für Tags/Sender/Typen; Bestätigungsdialoge für
  Sammellöschen in `MainDocView` und `InboxView`; `AppStore.deleteDocuments(ids:)` (ein `bulk_edit`,
  `removeDocumentsLocally`); `reportBulkResult(_:failed:)` ersetzt das nie angezeigte `bulkResultMessage`.
- **B10** – `ContentView`: Nach Fehlschlag `isBlurry = true`; bei `.active` bleibt die Sperrfläche, solange `authFailed`.
- **B11** – `ASNScannerSheet.asn(from:)` (letzte ASCII-Ziffernfolge, max. 9 Stellen); Vermietoo-Mehrfachauswahl und
  Sammel-Teilen lesen `filteredDocs`; `CustomFieldsSection.dateBinding` und gespeicherte Ansichten nutzen `DateFormatting`.
- **S5** – `authenticationPolicy = .requiresAuthentication` für `FindDocumentsIntent`, `InboxCountIntent`.
- **S6** – `AppConstants.allowedCallbackSchemes = ["vermietoo"]`.
- **P1** – `PendingUpload.encode(to:)` lässt `data` weg, `init(from:)` liest alte Einträge mit Base64 weiter;
  `PersistenceService.saveUploads` (Dateien → JSON → Aufräumen in der seriellen Queue), `loadUploads` (fehlende Datei →
  `failureReason`). `AccountDiskSnapshot` und `saveQueues` nutzen sie.
- **P4** – `LinkifiedText.linkify` detached per `.task(id: text)`; `SeriesView` rechnet per `.task(id: inputKey)`;
  `AppStore.deadlineSuggestions()` async + `nonisolated static deadlineSuggestions(in:fieldId:limit:)`.
- **B9** – `BackgroundData` (NotificationService.swift), `NotificationService.checkDeadlines(api:)`,
  `AppStore.deadlineEntries(from:fieldId:)`, `clearBadge()` bei `.active`, `syncMetadata` zieht `lastNotifiedInbox` nach;
  `AppStore.checkInboxForNotification` entfernt.
- **P3** – `ArchiveIndex`: `[Int: [Float]]`, Binärformat (`encode`/`decode`), Umzug aus JSON beim Laden,
  `index(…, persist:)` + `flush(account:)`; `buildFullArchiveIndex` schreibt einmal am Ende (auch nach Abbruch).
- **P2** – `Helpers/ScanPDF.swift`; genutzt von ScannerView, PhotoPicker, `OCRService.pdf(from:)`, AirScanService.
- **S7 (Teil)** – `ContentView` `.accessibilityHidden(isBlurry)`; `WidgetDataService.clearContent()` in `switchAccount` und `clearLocalData`.
- **Zweite Prüfrunde** – `Paperless_TeDiApp` wertet `paperless24://inbox` aus; `widget_enabled` über
  `object(forKey:) as? Bool ?? true` (AppStore, SettingsView, beide WidgetDataService); Import-Regeln unter
  `uploadRules.<accountId>` mit Umzug; `RemindersService.alarmDate(dueDate:leadDays:now:calendar:)`;
  „Nächste freie ASN" unterscheidet Fehler von „keine ASN"; Warnungen bereinigt.
- **B2-Randfall** – `queueItemsInFlight` in beiden Warteschlangen; nach Epochenwechsel bei gleichem Konto Einträge im
  Speicher austragen statt nur in der Datei.

### 13.09.2026
- Nutzerentscheidungen E1 (http nur per Schalter), E2 (Rückfrage vor Anlegen durch KI), E3 (Spotlight-Schalter) umgesetzt.
- Meldungen N1 (Suchfeld weg nach Tabwechsel), N2 (Einstellungen unübersichtlich), N3 (Sortieren wirkungslos) behoben.
- Achtung: Die ersten Testläufe liefen auf dem Simulator, den der Nutzer parallel mit seinem echten Konto benutzte. UI-Tests
  sind dort nur durch Einstellungen/Konto-hinzufügen/Sortier-Menü gelaufen, nichts Zerstörendes (Abmelden-Test bricht ab, Login
  wird nicht abgeschickt). Ab `full-r19` auf eigenem Test-Simulator.

### TestFlight (13.09.2026, auf Wunsch des Nutzers)
- Build-Nummer 4 → 5 (alle Targets), Version bleibt 2.2.0. Nicht committet.
- Archiv `.claude/audit/release/Paperless24-2.2.0-5.xcarchive` (Log `archive.log`), Upload per `xcodebuild -exportArchive` mit `.claude/audit/release/ExportOptions.plist` (Log `export.log`).
- Upload per Kommandozeile gescheitert: „Failed to find an account with App Store Connect access for team RVXL7PUD42" (xcodebuild sieht die Xcode-Anmeldung nicht). Archiv nach `~/Library/Developer/Xcode/Archives/2026-09-12/Paperless24 2.2.0 (5) 13.09.26.xcarchive` kopiert und im Organizer geöffnet; Upload macht der Nutzer über „Distribute App".
- Nutzer hat über den Organizer hochgeladen; der Organizer hat die Build-Nummer selbst auf 7 gesetzt (Upload per API-Schlüssel danach abgelehnt: „must be higher than 7"). Projekt auf `CURRENT_PROJECT_VERSION = 7` gezogen. Nächster Upload: 8. Upload per App-Store-Connect-API-Schlüssel funktioniert (Zugangsdaten nur lokal, nicht im Repo).

### Git-Aufräumen (13.09.2026)
- Commits `f20302f` (alle Fixes), `75fde5a` (geteilte Schemes), Merge `a04fb5c` (xcode/main eingeführt, docs/index.html in 2.2.0-Fassung). Branch `feature/android-port` → `release/2.2.0`, gepusht, PR https://github.com/thomas1701-test/Paperless24/pull/2 — erst nach App-Store-Freigabe mergen (docs/ = GitHub Pages).
- Worktrees entfernt; nicht committete Stände vorher als wip-Commits gesichert: `archiv/wip-customfield-formatter`, `archiv/wip-ui-texte-2026-07`, `archiv/wip-sharestaging-test`. Unmerged behalten und umbenannt: `archiv/korrespondenten-punkt`, `archiv/macos-design-spec`. Gelöscht (vollständig in release enthalten): 7 claude/*-Branches, `feature/ngx-parity`, `feature/unterstuetzung-paypal`. Remote-Branches von anderen Sitzungen (claude/paperless-ngx-app-icon-…, claude/remove-email-github-page-…) nicht angefasst.

### N5 „Zeitüberschreitung" + „Offline" bleiben stehen (13.09.2026, Screenshot vom iPhone)
- Ursache: Anfrage läuft beim Wechsel in eine andere App (Mail) weiter, iOS friert sie ein → Timeout → nach 2 Versuchen `isOffline = true` + `lastSyncError`. Kein Sync beim Zurückkehren in den Vordergrund, kein automatischer Neuversuch → Banner bleiben, bis man zieht oder den Tab wechselt. Zusätzlich: beide Banner doppelt, rotes Banner färbt Kopfzeile/Statusleiste (Hintergrund ignoriert Safe Area).
- Umgesetzt: `backgroundTransitions` + `appDidEnterBackground()`/`appDidBecomeActive()` in AppStore, Aufruf aus `Paperless_TeDiApp` (scenePhase). Fehlschlag über einen Hintergrundwechsel zählt nicht als Fehlversuch; Rückkehr in den Vordergrund lädt neu (offline sofort, sonst `syncIfStale`); Auto-Sync-Schleife synct alle 30 s, solange `isOffline`; `URLError` setzt nur noch `isOffline`, andere Fehler nur `lastSyncError`; Offline-Banner mit Neuladen-Knopf; rote/orange/lila Banner mit `ignoresSafeAreaEdges: []`.
- Tests: `nichtErreichbarZeigtNurOffline`, `vordergrundHoltAusOfflineZurueck` (beide ohne Fix rot, `offline-neg`). 168 Tests grün (`full-r21`).
- Nicht abgedeckt: der Hintergrund-Pfad selbst (URLSession wiederholt abgerissene GETs von sich aus, ein Testserver erzeugt den Fehler nicht) und die Banner-Darstellung (nur Code, kein Screenshot — im Simulator ohne erreichbaren Server nicht herstellbar).
