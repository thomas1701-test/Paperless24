# Umsetzung der Feature-Ideen — Arbeitsprotokoll

Begonnen: 12.09.2026 · Branch: `feature/android-port` · Ausgangsversion 2.1.4
Vorlage: [FEATURE-IDEEN.md](FEATURE-IDEEN.md)

**Diese Datei ist die Übergabe.** Sie wird nach jedem Punkt aktualisiert. Wer hier neu
einsteigt, liest Abschnitt „So geht es weiter" und kann sofort arbeiten.

## Verifikation

```
xcodebuild -project "Paperless 24.xcodeproj" -scheme Paperless24 \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Baseline vor der ersten Änderung: **BUILD SUCCEEDED**, 0 Fehler (12.09.2026).
Zusätzlich zu prüfen: Schemes `PaperlessShare` und `PaperlessWidgetExtension`.

## Statuslegende

✅ fertig · 🔧 in Arbeit · ⏳ offen · ⛔️ nicht baubar (Grund dabei)

## Reihenfolge und Status

| # | Punkt | Status | Notiz |
|---|---|---|---|
| 0.1 | Filter an den Server geben | ✅ | inkl. Mehrfach-/Negativfilter |
| 0.2 | „Erledigt" im Posteingang (Inbox-Tag entfernen) | ✅ | Wisch, Auswahlmodus, Sammelaktion |
| 0.3 | `bulk_edit` statt N Einzel-PATCH | ✅ | mit Warteschlange als Rückfallebene |
| 0.4 | ngx-Vorschläge (`/api/documents/{id}/suggestions/`) | ✅ | genutzt im Triage-Modus |
| 0.5 | Verarbeitungsstatus (`/api/tasks/`) | ✅ | erkennt auch Server-Dubletten |
| A1 | Posteingang-Triage | ✅ | `TriageView`, „Durchwischen" im Posteingang-Menü |
| A2 | Im Detail zum nächsten Dokument wischen | ✅ | `DocumentPagerView` |
| A3 | Textausschnitt im Suchtreffer | ✅ | Server-Highlight, sonst lokal |
| A4 | Anzeigefelder der Liste konfigurierbar | ✅ | 5 Schalter, iCloud-synchron |
| A5 | Diagnose-Ansicht | ✅ | `DiagnosticsView`, Bericht kopierbar |
| B1 | Fristen-Radar, zweiter Versuch | ✅ | 16 Tests grün, opt-in |
| B2 | Embedding-Index über das ganze Archiv | ✅ | `ArchiveIndex`, Aufbau in den Einstellungen |
| B3 | Dublettenprüfung, zweiter Versuch | ✅ | Signatur statt Ähnlichkeit, 9 Tests |
| B4 | Wiederkehrende Dokumente überwachen | ✅ | `SeriesDetector`, 10 Tests |
| B5 | Upload-Regeln | ✅ | `UploadRule` + `UploadRulesView` |
| C1 | Mindest-iOS senken | ✅ | 18.0, alle 3 Targets bauen |
| C2 | App Intents mit Parametern/Rückgabe | ✅ | 3 neue Intents + `DocumentEntity` |
| C3 | Sperrbildschirm-, Control-Center-, interaktives Widget | ✅ | 3 Zubehör-Familien, 2 Controls, Scan-Knopf |
| C4 | mTLS + eigene HTTP-Header | ✅ | `ServerAccessView`, greift schon beim Login |
| C5 | Eigene Felder anlegen/ändern/löschen | ✅ | `CustomFieldListView` |
| C6 | Berechtigungen, Besitzer, Speicherpfade | ✅ | als Sammelaktion |
| C7 | ASN-Barcode | ✅ | Scanner + nächste freie Nummer |
| C8 | Seitenwerkzeuge (PDF) | ✅ | drehen, löschen, sortieren vor dem Upload |
| C9 | Server-KI von ngx 3.0 als Alternative | ⚠️ | „Ähnliche Dokumente" gebaut; Chat-Endpunkt nicht (siehe unten) |
| C10 | File Provider | ⛔️ | braucht ein neues Xcode-Target — von der Kommandozeile nicht verlässlich anzulegen |
| C11 | Server-Push | ⛔️ | braucht eigenen Relay-Server + APNs-Zertifikat; in dieser Umgebung nicht baubar |
| C12 | Statistik-Dashboard | ✅ | `StatisticsView`, sagt was sie auswertet |
| **L1** | **Ladeverhalten glätten** | ✅ | 6 Ursachen behoben, 94 Tests grün |

## Protokoll

### Vorbereitung (12.09.2026)
- Baseline-Build geprüft: erfolgreich.
- Diese Datei angelegt.

### 0.1 Filter an den Server geben ✅
**Neu:** `Paperless24/Models/DocumentQuery.swift` — alle Filter an einem Ort, übersetzt in
Query-Parameter (`tags__id__all`, `tags__id__none`, `correspondent__id__in`,
`document_type__id__in`, `storage_path__id__in`, `created__date__gte/lte`,
`custom_fields__id__all`, `query`). Dazu `DocumentFilterSupport`: merkt sich je Server, ob er
die Parameter versteht.

**Geändert:**
- `PaperlessAPI`: `fetchDocuments(query:page:pageSize:ordering:)`.
- `AppStore`: `activeQuery`, `isServerFiltering`, `isQueryActive`, `listCount`,
  `applyFilters()`, `runQuery()`, `refineQueryResult()`, `refreshList()`;
  `loadNextSearchPage()` blättert jetzt *innerhalb* des Filters. Suche und Filter laufen über
  denselben Pfad.
- `updateFilteredDocs()` bleibt als lokale Rückfallebene (offline, Demo, alter Server) und
  rechnet dieselben Mengen aus wie `activeQuery`, damit offline dasselbe herauskommt.
- `MainDocView`: `applyFilters()` ruft den Store, Pull-to-Refresh nutzt `refreshList()`,
  Kopfzeile zeigt die Server-Trefferzahl, neuer Chip „Mehr" + Sidebar-Zeile.
- **Neu:** `Views/Shared/AdvancedFilterSheet.swift` — Mehrfachauswahl und „keiner dieser Tags".

**Wichtig:** Die Server-Antwort landet in `filteredDocs`, **nicht** in `documents`.
`documents` ist Offline-Cache, Spotlight- und „Archiv fragen"-Quelle und muss die
ungefilterte Liste bleiben.

**Rest:** Textvergleich im eigenen Feld bleibt absichtlich lokal (`custom_field_query` ist je
ngx-Version unterschiedlich). Auf echtem Server gegen ngx 2.x und 3.0 noch nicht getestet.

### 0.3 `bulk_edit` ✅
`PaperlessAPI.bulkEdit(ids:method:parameters:)` plus `bulkModifyTags`, `bulkSetCorrespondent`,
`bulkSetDocumentType`, `bulkSetStoragePath`, `bulkDelete`. `AppStore`: `bulkModifyTags`,
`bulkRemoveTags`, `bulkAssignDocumentType`, Helfer `mutateLoadedDocuments`,
`anyLoadedDocument`, `queueTagChange`. Schlägt der Aufruf fehl, landet die Änderung in der
bisherigen Einzel-PATCH-Warteschlange — offline geht nichts verloren.
Neu in `PendingEdit`: `applied(to:)` (eine Stelle für alle drei Listen).

### 0.2 „Erledigt" im Posteingang ✅
`AppStore.markAsDone(_:)` / `markAsUnread(_:)` entfernen bzw. setzen die Inbox-Tags.
`InboxView` neu geschrieben: Wisch von links „Erledigt", Auswahlmodus mit „Alle auswählen" und
„Als erledigt markieren", Kontextmenü im Raster, Menü mit „Durchwischen".
Ohne Inbox-Tag auf dem Server erscheinen die Aktionen nicht.

### 0.4 ngx-Vorschläge ✅
**Neu:** `Models/DocumentSuggestions.swift` (toleranter Decoder — ältere Server liefern
`storage_paths`/`dates` nicht), `PaperlessAPI.fetchSuggestions(documentId:)`,
`AppStore.fetchSuggestions(for:)` (gibt bei Fehler/404 `nil`).

### A1 Posteingang-Triage ✅
**Neu:** `Views/Documents/TriageView.swift`. Vorschau, Titel, Datum, Sender, Typ, Tags auf
einem Bildschirm; Vorbelegung aus 0.4, die **nur leere Felder** füllt; „Erledigt und weiter"
entfernt den Inbox-Tag und legt das nächste Dokument vor; „Überspringen" lässt es liegen.
Arbeitet auf einer eigenen Kopie der Liste, damit der Stapel beim Bestätigen nicht wegrutscht.

### 0.5 Verarbeitungsstatus ✅
**Neu:** `Models/ConsumptionTask.swift` (`ConsumptionTask` + `UploadTaskStatus`).
`PaperlessAPI.uploadDocument` gibt jetzt die Auftrags-ID zurück, `fetchTask(taskId:)` fragt
`/api/tasks/` ab (verträgt Array *und* paginierte Hülle, `related_document` als Zahl oder
String). `AppStore.followUp(taskId:title:)` pollt 20 × 3 s und meldet das Ergebnis;
`uploadTaskStatuses` wird in `PendingQueueView` angezeigt.

Ein Fehlschlag erscheint als Alarm — vorher hätte der Nutzer geglaubt, das Dokument sei im
Archiv. **Nebeneffekt:** Die Dublettenmeldung des Consumers wird erkannt und benannt; damit
ist ein Teil von B3 ohne eigene Heuristik erledigt.

### A2 Wischen zwischen Dokumenten ✅
**Neu:** `Views/Documents/DocumentPagerView.swift`. Beide Listen (Dokumente, Posteingang)
öffnen jetzt den Pager. Das Fenster um das gewählte Dokument ist auf ±40 Seiten begrenzt und
wächst am Rand nach — ein `TabView` im Seitenstil legt seine Seiten nicht verlässlich erst bei
Bedarf an, und ein Archiv mit Tausenden Dokumenten wäre sonst spürbar langsam.

### A3 Textausschnitt im Suchtreffer ✅
`Document.searchHit` (`__search_hit__`) mit tolerantem Decoder, `searchSnippet(for:)`:
bevorzugt den Ausschnitt des Servers (Auszeichnung wird entfernt, weil Whoosh und Tantivy
unterschiedlich auszeichnen), sonst lokal um den ersten Treffer geschnitten — funktioniert
damit auch offline und auf alten Servern.

### A4 Anzeigefelder der Liste ✅
`DocumentRow` zeigt Sender, Typ, Belegdatum, Hinzugefügt-Datum und ASN nach Wahl
(`rowShow*`-Schalter, neue Sektion in den Einstellungen, in den iCloud-Sync aufgenommen).

### A5 Diagnose-Ansicht ✅
**Neu:** `Views/Settings/DiagnosticsView.swift` + `AppStore.probeConnection()`. Zeigt Server,
verhandelte API-Version, ob der Server-Filter aktiv ist, Verbindungsprüfung mit Laufzeit,
Datenbestand, Warteschlange, Gerät und KI-Verfügbarkeit; „Bericht kopieren" für Supportmails.
Enthält bewusst kein Passwort und keine Dokumentinhalte. Bietet an, einen abgeschalteten
Server-Filter erneut zu versuchen.

### C1 Mindest-iOS gesenkt ✅
`IPHONEOS_DEPLOYMENT_TARGET` in allen acht Konfigurationen von 26.0/26/26.2 auf **18.0**.
Alle drei Schemes bauen fehlerfrei. Das ist der Beweis, dass die 26er-Anforderung unnötig war:
Hätte der Code ein ungeschütztes iOS-26-API benutzt, wäre der Build ein Fehler, keine Warnung.
Die einzigen zwei `#available(iOS 26, *)`-Stellen in `AIService` bleiben unverändert — Apple
Intelligence ist weiterhin nur dort aktiv, wo es das Gerät hergibt.
Sicherung der alten Projektdatei liegt im Scratchpad (`pbxproj.bak`).
**Noch zu prüfen:** Lauf auf einem echten iOS-18-Gerät; der Build allein sagt nichts über
Laufzeitverhalten älterer Systeme.

### C5 Eigene Felder verwalten ✅
`PaperlessAPI.createCustomField/renameCustomField/deleteCustomField`, im Store
`createCustomField`, `renameCustomField`, `deleteCustomField`, `syncCustomFields`,
`customField(named:)`. **Neu:** `Views/Settings/CustomFieldListView.swift` (Suche, Anlegen mit
Typwahl und Select-Optionen, Umbenennen, Löschen mit Warnung).

### B1 Fristen-Radar, zweiter Versuch ✅
**Neu:** `Models/Deadline.swift`, `Services/DeadlineDetector.swift`,
`Services/RemindersService.swift`, `Store/AppStore+Deadlines.swift`,
`Views/Documents/DeadlinesView.swift`, `Paperless24Tests/DeadlineDetectorTests.swift`.

Anders als beim ersten Versuch:
1. **Deterministisch.** Datumsmuster (dd.MM.yyyy, ISO, ausgeschriebener Monat) plus eine Liste
   gewichteter Schlüsselwörter. Ein Datum wird nur zur Frist, wenn ein Schlüsselwort in seiner
   Nähe steht — entscheidend ist die **Nähe**, nicht die Reihenfolge in der Liste (daran ist
   die erste Fassung im Test gescheitert: „Zahlbar bis 30.09. … Kündigungsfrist bis 31.12."
   wurde zu zwei Zahlungsfristen).
2. **Kein stiller Hintergrundlauf.** Vorschlag im Triage-Modus und in der Fristenliste, immer
   mit Belegstelle. Gespeichert wird nur, was bestätigt wird.
3. **Nur eindeutige Treffer schlagen automatisch vor** (`primaryDeadline`, Gewicht ≥ 1.0);
   mehrdeutige („bitte bis") erscheinen nur in der vollständigen Liste.
4. **Opt-in** (`deadlineRadarEnabled`, Standard aus).
5. Ablage in einem Datumsfeld auf dem Server — damit auch in der Weboberfläche sichtbar.
6. Erinnerungen statt Kalendereinträge (eine Frist ist eine Aufgabe), mit Vorlauf je Art:
   Kündigung 42 Tage, Zahlung 3 Tage.
7. Hintergrund-Benachrichtigung nur über **bestätigte** Fristen, höchstens einmal täglich.

**16 Tests**, davon die Hälfte Negativfälle (Rechnungsdatum ohne Schlüsselwort, 31.02.,
Zahlenkolonnen, Schlüsselwort zwei Sätze entfernt). Alle grün.

**Grenze:** Das Datumsfeld hält nur das Datum, nicht die Art der Frist. Die Art wird beim
Vorschlag angezeigt, aber nicht gespeichert — ein zweites Feld dafür wäre mehr Verwaltung als
Nutzen.

### L1 Ladeverhalten ✅ (Nutzerrückmeldung)
Sechs Ursachen, alle im Zusammenspiel verantwortlich für das Ruckeln:

1. **Layoutsprung.** Die Fortschrittsleiste („Suche…", Sync-Balken) war ein Baustein *im*
   Stack. Beim Auftauchen rutschte die ganze Liste um ihre Höhe nach unten und beim
   Verschwinden zurück. Jetzt eine Zeile fester Höhe (`activityStrip`), die immer im Layout
   steht und nur ihren Inhalt wechselt.
2. **JSON auf dem Main Thread.** `PersistenceService.save` kodiert beim Aufrufer — also lief
   `JSONEncoder` über *alle* Dokumente samt erkanntem Text auf dem Main Thread, bei jedem Sync.
   `saveToDisk()` ist jetzt geteilt: Warteschlangen sofort (klein, verlustkritisch), Archiv in
   einem Hintergrund-Task und nur, wenn sich laut Fingerabdruck etwas geändert hat
   (`saveArchive(force:)`, `archiveSignature()`).
3. **Sync bei jedem Zurück-Tippen.** `MainDocView.onAppear` löste einen vollen Sync aus.
   Jetzt `syncIfStale()`: beim ersten Aufbau sichtbar, danach höchstens alle 20 s und still.
   Zusätzlich verhindert `isSyncRunning`, dass sich zwei Läufe überlagern.
4. **Stiller Sync war nicht still.** `loadFirstPage()` setzte `isSyncing` unabhängig davon.
   Neuer Parameter `silent:`.
5. **Liste klappte beim Aktualisieren zusammen.** `loadFirstPage()` ersetzte die Liste durch die
   erste Seite — wer fünf Seiten nachgeladen hatte, landete wieder bei 25 Dokumenten, mitten im
   Scrollen. Neu: `mergeFirstPage()` pflegt bekannte Dokumente ein und hängt neue vorn an, der
   Blätterstand bleibt.
6. **Unnötige Rechenarbeit bei jedem Nachladen.** `updateFilteredDocs()` filterte und sortierte
   die gewachsene Gesamtliste erneut — bei „Sender A–Z" mit linearer Namenssuche *im*
   Vergleich. Jetzt Schnellpfad (Server hat schon sortiert → direkt übernehmen) und ein
   Wörterbuch für die Namen. Spotlight läuft nur noch beim ersten Aufbau oder alle 15 Minuten
   (`indexDocumentsForSpotlightIfDue()`).

Verifikation: `xcodebuild test` — **94 Tests in 13 Suiten grün**. Das tatsächliche Gefühl beim
Scrollen lässt sich nur auf einem Gerät mit großem Archiv beurteilen.

### C3 Widgets ✅
**Neu:** `PaperlessWidget/AccessoryWidget.swift` (`.accessoryCircular`, `.accessoryRectangular`,
`.accessoryInline` mit der Posteingangszahl), `PaperlessWidget/ScanControl.swift`
(`ScanControl` und `InboxControl` fürs Control Center, Sperrbildschirm und die Aktionstaste,
ab iOS 18). Scan-Knopf im großen Widget (`Button(intent:)`).
Controls können die App nur öffnen, nicht in ihr navigieren — der Wunsch liegt als Marke in der
App Group (`control_request_scan` / `control_request_inbox`) und wird in
`Paperless_TeDiApp.handleControlRequests()` eingelöst und sofort gelöscht.

### C2 App Intents mit Werten ✅
**Neu:** `Paperless24/Intents/DataIntents.swift` — `DocumentEntity` (+ `EntityQuery`),
`FindDocumentsIntent` (Suchbegriff rein, Treffer raus, **ohne** die App zu öffnen),
`InboxCountIntent` (Zahl + gesprochene Antwort, liest die App Group, kein Netz),
`UploadFileIntent` (Datei rein, legt sie wie die Share-Erweiterung in der App Group ab).
`IntentDataSource` arbeitet bewusst ohne `AppStore` — der hängt am Main Actor und an der
Oberfläche, ein Hintergrund-Kurzbefehl darf das nicht brauchen.

### C4 mTLS und eigene Header ✅
**Neu:** `Services/ServerCredentials.swift` (+ `ClientCertSessionProvider`),
`Views/Settings/ServerAccessView.swift`.
Header liegen je Server in den UserDefaults, das PKCS#12-Bündel im Schlüsselbund
(`ThisDeviceOnly`, also nicht in Backups). `URLSession.shared` nimmt keinen Delegate an und
kann eine Zertifikatsanfrage deshalb nicht beantworten — für Server mit Zertifikat gibt es
jetzt eine eigene Session je Server. Beides greift **schon bei `fetchToken`**, sonst käme man
hinter einem Proxy nie bis zum Login.

### C12 Statistik ✅
**Neu:** `Views/Settings/StatisticsView.swift`. Bestand, Dokumente pro Monat als Balkenzeilen
(ohne Diagramm-Bibliothek, damit es in jeder Schriftgröße lesbar bleibt), häufigste Sender,
Speicher. Nennt ausdrücklich, dass nur die geladenen Dokumente ausgewertet werden, wenn das
Archiv größer ist — eine Auswertung, die das verschweigt, wäre schlimmer als keine.

### B5 Import-Regeln ✅
**Neu:** `Models/UploadRule.swift`, `Views/Settings/UploadRulesView.swift` (+ Editor).
Auslöser „Dateiname enthält" oder „Jeder Import", vorbelegt werden Sender, Typ, Tags und ein
Titelmuster (`{dateiname}`, `{datum}`). Erste passende Regel gewinnt, Reihenfolge per Drag
änderbar. Vorbelegt werden nur leere Felder; das Formular nennt die Regel, die gegriffen hat.
Gesichert ausdrücklich über `saveUploadRules()` statt per `didSet` — sonst schriebe jeder
Tastendruck im Editor.

### C7 ASN-Barcode ✅
**Neu:** `Views/Shared/BarcodeScannerView.swift` (VisionKit `DataScannerViewController`, nur
Barcodes, damit kein Text im Dokument mitgelesen wird) und `ASNScannerSheet`.
Aus dem Code wird die erste Zahlenfolge genommen — Etiketten drucken oft ein Präfix oder eine
URL. Fallback: Eingabefeld für die Nummer, auch für Geräte ohne DataScanner-Unterstützung.
API: `fetchDocument(asn:)`, `fetchHighestASN()`; Store: `findDocument(asn:)` (erst lokal),
`nextFreeASN()`. Im Bearbeiten-Dialog schlägt ein Knopf die nächste freie Nummer vor.

### B3 Dublettenprüfung, zweiter Versuch ✅
**Neu:** `Services/DuplicateDetector.swift`, `Paperless24Tests/DuplicateDetectorTests.swift`
(9 Tests, grün).
Statt Textähnlichkeit eine **harte Signatur**: Belegnummer (nur hinter einem Schlüsselwort —
sonst wäre jede Telefonnummer eine Belegnummer), Betrag in Cent (nur mit zwei
Nachkommastellen), Datumsangaben. Ein Treffer verlangt **zwei** übereinstimmende Merkmale:
Eine gleiche Kundennummer steht auf jedem Brief desselben Absenders, ein gleicher Betrag kann
ein Dauerauftrag sein.
Der Schlüsseltest ist `haeltSerienbriefeAuseinander()` — zwei Stromrechnungen aus Januar und
Februar, zu über 90 % derselbe Text. Genau daran ist die erste Fassung gescheitert.
Eingehängt im Importformular (`AppStore.checkForDuplicate(text:)`, OCR der ersten Seite),
als Hinweis mit Begründung, nicht als Sperre. Abschaltbar.

### B4 Wiederkehrende Dokumente ✅
**Neu:** `Services/SeriesDetector.swift`, `Views/Documents/SeriesView.swift`,
`Paperless24Tests/SeriesDetectorTests.swift` (10 Tests, grün).
Gruppiert nach Sender **und** Typ (ein Absender kann mehrere Reihen schicken), verlangt
mindestens 4 Belege und eine Dichte von 60 % im Zeitraum — vier Rechnungen über fünf Jahre sind
keine monatliche Serie. Meldet Lücken mitten in der Reihe und ausbleibende Fortsetzungen.

### B2 Bedeutungsindex ✅
**Neu:** `Services/ArchiveIndex.swift` (ein `actor`), Aufbau-Oberfläche in den Einstellungen.
Speichert je Dokument einen Vektor (`NLEmbedding.vector(for:)`, erste 600 Zeichen) statt des
Textes; eine Frage ist danach ein Kosinus-Vergleich von Zahlenreihen statt tausender
Embedding-Aufrufe. `AskArchiveView` fragt zuerst den Index und holt fehlende Dokumente einzeln
nach. Inkrementell nach jedem Laden, vollständig auf Knopfdruck über das ganze Archiv.

**Verifikation nach B2/B3/B4:** `xcodebuild test` — **113 Tests in 15 Suiten grün**.

### C6 Berechtigungen und Speicherpfade ✅
**Neu:** `Models/StoragePath.swift` (+ `ServerUser`, `ServerGroup`),
`Views/Shared/PermissionsSheet.swift`.
API: `fetchStoragePaths`, `fetchUsers`, `fetchGroups`, `bulkSetPermissions`.
Speicherpfade kommen mit den Stammdaten; Benutzer und Gruppen erst, wenn jemand die Rechte
öffnet — der Server gibt sie nur Administratoren heraus, und ein 403 bei jedem Sync wäre
sinnlos. Ist die Liste leer, sagt das Blatt das und bietet nichts an.
Das Auswahl-Menü in der Liste hat jetzt zusätzlich: Typ zuweisen, Tag entfernen, Speicherpfad,
Rechte, „Als erledigt markieren".

### C8 Seitenwerkzeuge ✅
**Neu:** `Views/Shared/PageEditorView.swift` — Seiten drehen, löschen, umsortieren, mit
Vorschaubildern. Arbeitet auf einer Kopie; erst „Sichern" ersetzt die Upload-Daten. Die letzte
Seite lässt sich nicht löschen. Nach dem Bearbeiten läuft die Dublettenprüfung erneut.
Nicht gebaut: Zusammenführen zweier PDFs und Aufteilen — beides braucht eine zweite Datei bzw.
einen eigenen Ablauf und gehört eher zum Stapel-Scan als ins Importformular.

### C9 Server-Intelligenz ⚠️ teilweise
**Gebaut:** „Ähnliche Dokumente" über `?more_like_id=` — der Server rechnet auf seinem
Volltextindex und kennt damit das ganze Archiv. Sichtbar im Info-Reiter.
**Nicht gebaut:** Der Dokument-Chat und die KI-Vorschläge von ngx 3.0. Deren Endpunkte ließen
sich von hier aus nicht verifizieren, und eine geratene URL ergibt eine Funktion, die beim
Nutzer still nichts tut. Das gehört gegen eine echte 3.0-Instanz gebaut.

### C10 File Provider ⛔️ nicht gebaut
Die Erweiterung braucht ein **eigenes Target** (`NSFileProviderReplicatedExtension`) mit
Bundle-ID, Entitlements, Info.plist und Schema. Ein Target lässt sich in `project.pbxproj` nur
von Hand eintragen; ein Fehler dabei macht die Projektdatei unbrauchbar — und das Ergebnis wäre
erst in Xcode zu sehen. Das ist kein sinnvoller Schritt ohne Oberfläche.

**Nötige Schritte, wenn es gebaut werden soll:**
1. In Xcode: File → New → Target → File Provider Extension, App Group
   `group.com.Thomas.paperless` eintragen.
2. Im Target `NSExtensionFileProviderSupportsEnumeration` setzen.
3. Enumerator gegen `PaperlessAPI` implementieren (Wurzel = Dokumentliste, Ordner = Tags).
4. Schreibzugriff auf `uploadDocument` abbilden.

Alles Übrige aus der Liste ist gebaut.

### L2 Nachbesserung Ladeverhalten (Rückmeldung aus dem Betrieb)
Zwei Punkte, die nach dem ersten Durchgang übrig blieben:

1. **Unzuverlässiges Nachladen — echter Fehler.** `loadFirstPage()` füllt `documents`;
   angezeigt wird bei aktivem Filter oder aktiver Suche aber `filteredDocs`, die Antwort des
   Servers. Nach Upload, übertragener Änderung oder Sammelaktion wurde nur die Gesamtliste
   nachgeladen, die sichtbare Liste blieb stehen. Zusätzlich verhinderte die Prüfung „gleiche
   Anfrage wie eben" das erneute Stellen derselben Abfrage. Neu `reloadVisible()` +
   `invalidateLoadState()`; alle Änderungspfade gehen darüber.
2. **Kopfbereich verschob weiter.** Die Statuszeile fester Höhe war nur die halbe Lösung. Der
   Status steht jetzt in der **Navigationsleiste** (wie in Mail), Fehler- und Offline-Banner
   gleiten, die Erfolgsmeldung schwebt als Kapsel. Dazu: Filterleiste steht von Anfang an,
   und statt des zentrierten Spinners stehen **Platzhalterzeilen** in der Form der späteren
   Einträge.

Im Simulator gegengeprüft (Demo-Modus), 113 Tests grün.

### Zwischenfall beim Aufteilen der Commits
Das Skript, das die Änderungen thematisch auf Commits verteilt, rechnete gegen `HEAD` statt
gegen eine feste Basis. Nach dem ersten Commit war die Basis eine andere, die Blöcke wurden neu
geschnitten, ihre Zuordnung stimmte nicht mehr — und beim Zurückschreiben gingen Teile der
Änderungen im Arbeitsbaum verloren. Fünf Dateien waren danach eine Mischung aus altem und neuem
Code.

Behoben: betroffene Dateien auf den Ursprungsstand zurückgesetzt, alle Änderungen neu
angewendet, Endstand gegen Build und Tests geprüft (113 grün), Historie mit einer festen Basis
neu aufgebaut. **Lehre:** Ein Werkzeug, das Dateien neu schreibt, darf seine Basis nie aus
`HEAD` ziehen, solange es selbst committet.

### Notiz für die Werkzeuge
Deutsche Strings mit Anführungszeichen nie über ein Python-Heredoc mit `\"` schreiben — die
Escape-Ebene geht verloren und Swift bricht mit „unterminated string literal" ab. Entweder
Python-Rohstrings (`r'''…'''`) verwenden oder die Zeichen als `"\u{201E}"` / `"\u{201C}"`
zusammensetzen.

## So geht es weiter

Alle Punkte der Liste sind abgearbeitet — bis auf **C10** (File Provider, braucht ein neues
Xcode-Target) und **C11** (Server-Push, braucht eigene Infrastruktur), beide oben begründet.
**C9** ist zur Hälfte gebaut.

**Was noch fehlt, bevor das ausgeliefert wird:**
1. Gegen echte Server testen — ngx 2.x **und** 3.0. Besonders: Server-Filter (0.1),
   `bulk_edit` (0.3), `/api/tasks/` (0.5), `suggestions` (0.4), `more_like_id` (C9).
2. Auf einem iOS-18-Gerät starten (C1 ist nur build-verifiziert).
3. Changelog und `AppConstants.appVersion` (steht noch auf 2.1.2, während `MARKETING_VERSION`
   bei 2.1.4 liegt) pflegen, Versionsnummer anheben.
4. Neue Oberflächentexte in `Localizable.xcstrings` übersetzen (EN, FR, ES, IT) — die neuen
   Ansichten sind bisher nur auf Deutsch.
5. Ladeverhalten auf einem Gerät mit großem Archiv gegenprüfen (L1). Danach der Reihe nach die Tabelle abarbeiten, nach jedem
Punkt bauen und diese Datei fortschreiben (Status, geänderte Dateien, offene Reste).

**Nicht committet** — alle Änderungen liegen im Arbeitsverzeichnis. `git status` zeigt den
Umfang, `git diff` die Details.
