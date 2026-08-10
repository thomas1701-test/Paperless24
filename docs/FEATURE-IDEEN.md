# Feature-Ideen & Wettbewerbsvergleich

Stand: 28.07.2026 · Basis: [FEATURES.md](FEATURES.md)

---

## 1. Wettbewerb

### Paperparrot (iOS, kommerziell, aktiv — v3.1.1 Juli 2026)

| Kann Paperparrot | Haben wir? |
|---|---|
| Mehrere Instanzen | ✅ |
| AirScan-Netzwerkscanner | ✅ |
| Face ID / Touch ID | ✅ |
| Spotlight-Suche | ✅ |
| Eigene Ansichten | ✅ |
| Teilen aus anderen Apps | ✅ |
| Offline-Sync | ✅ |
| Dark Mode, 2FA | ✅ |
| **Server-Push-Benachrichtigungen** (legt dafür automatisch einen ngx-Workflow an) | ❌ nur stündliches Polling |
| **mTLS + eigene HTTP-Header** | ❌ |
| **Serverloser Modus**: App komplett ohne Paperless-Server nutzbar, Sync über iCloud | ❌ (nur Demo-Daten) |
| **Spalten der Dokumentliste konfigurierbar** | ❌ |
| **ngx-3.0-KI-Anbindung** (Server-KI statt Geräte-KI) | ❌ |
| Import von Office-Formaten (docx/xlsx) | ❌ nur PDF/Bild |

### Swift Paperless (iOS, kostenlos, quelloffen — De-facto-Standard)

Deckt Suchen, Ansehen, Bearbeiten, Verwalten, Hochladen und Scannen vollständig ab, sehr enge Anlehnung an das ngx-Datenmodell (inkl. Berechtigungen und Speicherpfaden). Stärke: Vollständigkeit gegenüber dem Server. Schwäche: kaum eigene Intelligenz, keine Fristen-/Workflow-Hilfen.

### Paperless Mobile (Android)

Vom ursprünglichen Entwickler eingestellt, bricht mit neueren ngx-Versionen. Android ist damit faktisch **unbesetzt** — das ist die größte offene Marktlücke.

### paperless-ngx 3.0 selbst

Der Server bringt seit 3.0 mit: Tantivy-Suche, Dateiversionen, Sharelink-Bundles, Parser-Plugins, Remote-OCR (Azure), Server-KI (Dokument-Chat, Vorschläge, Ollama-Embeddings, ähnliche Dokumente). Nichts davon nutzt die App bisher.

### Unser Alleinstellungsmerkmal heute

Apple Intelligence on-device (Zusammenfassen, Auto-Metadaten, Stapel-Trennung, Archiv fragen), Übersetzen, Siri-Kurzbefehle, Widget, Vermietoo-Anbindung. Das hat sonst niemand — es lohnt sich, genau dort weiter auszubauen statt nur ngx-Features nachzubauen.

---

## 2. Vorschläge, nach Nutzen sortiert

Bewertung: **Nutzen** = wie oft es im Alltag hilft. **Aufwand** = grobe Schätzung.

### Stufe A — hoher Nutzen, kleiner bis mittlerer Aufwand

**A1 · Posteingang-Triage („Durchwischen")**
Ein Vollbild-Modus für den Posteingang: Dokumentvorschau oben, darunter drei große Felder für Sender, Typ, Tags — vorbelegt mit KI- bzw. Server-Vorschlägen. Bestätigen, weiter zum nächsten. Das ist die Aufgabe, die jeder Paperless-Nutzer täglich hat, und aktuell braucht sie pro Dokument fünf Tipps und zwei Sheets.
*Nutzen: sehr hoch · Aufwand: mittel*

**A2 · ngx-Vorschläge nutzen (`/api/documents/{id}/suggestions/`)**
Der Server hat einen trainierten Klassifikator, den wir ignorieren. Ein GET liefert passende Sender, Typen, Tags und ASN. Funktioniert auf jedem iPhone, auch ohne Apple Intelligence, und ist in wenigen Stunden eingebaut. Ideal als Vorbelegung für A1.
*Nutzen: hoch · Aufwand: klein*

**A3 · Verarbeitungsstatus nach dem Upload (`/api/tasks/`)**
Heute meldet die App „Fertig", sobald der Server die Datei angenommen hat. Ob der Consumer sie wirklich verarbeitet hat oder an einem Duplikat/OCR-Fehler gescheitert ist, sieht der Nutzer nie. Nach dem Upload die Task-ID pollen und Erfolg oder Fehler anzeigen.
*Nutzen: hoch · Aufwand: klein*

**A4 · Echter Posteingang statt Heuristik**
Der Posteingang ist derzeit „Dokumente ohne Sender". paperless-ngx definiert ihn über den Inbox-Tag (`is_inbox_tag`). Umstellen, und beim Abarbeiten den Tag entfernen — das ist erst der Workflow, den der Server erwartet.
*Nutzen: hoch · Aufwand: klein*

**A5 · Sammelaktionen über `bulk_edit`**
Derzeit ein PATCH pro Dokument, seriell, ohne Rückmeldung. Der Server kann das in einem Aufruf — zusätzlich mit Tags *entfernen*, Speicherpfad setzen, Besitzer ändern, in den Papierkorb verschieben.
*Nutzen: hoch · Aufwand: klein*

**A6 · Mehrfachfilter und Suchtreffer-Vorschau**
Mehrere Tags/Sender/Typen gleichzeitig, Negativfilter („ohne Tag X"), und in der Trefferliste den passenden Textausschnitt anzeigen statt nur den Titel.
*Nutzen: hoch · Aufwand: mittel*

**A7 · mTLS und eigene HTTP-Header**
Viele Self-Hoster stellen ngx hinter Cloudflare Access, Authelia oder einen Proxy mit Client-Zertifikat. Ohne das ist die App für sie schlicht nicht nutzbar — Paperparrot hat es, wir nicht. Umsetzung: Zertifikat importieren, Header-Paare pro Konto speichern, `URLSessionDelegate` für die Challenge.
*Nutzen: hoch für eine kleine, aber laute Gruppe · Aufwand: mittel*

### Stufe B — Alleinstellung ausbauen

**B1 · Fristen-Radar**
Beim Import erkennt die KI Fälligkeits-, Kündigungs- und Garantiedaten und schreibt sie in ein eigenes Feld. Die App warnt rechtzeitig per Benachrichtigung, zeigt eine „Was steht an"-Liste und bietet Export in den Kalender (EventKit). Rechnung überfällig, Vertrag läuft in 6 Wochen aus, Garantie endet — das ist der Grund, warum Leute Dokumente überhaupt archivieren, und kein Konkurrent macht es.
*Nutzen: sehr hoch · Aufwand: mittel bis groß*

**B2 · Dublettenprüfung beim Scannen**
Vor dem Upload den OCR-Text gegen das lokale Archiv prüfen (Embedding-Ähnlichkeit, ergänzend Betrag+Datum+Sender). Warnen statt hochladen. Die Vorarbeit steckt schon im Code (`OCRService`, Kommentar in `PageScannerView`).
*Nutzen: hoch · Aufwand: mittel*

**B3 · Wiederkehrende Dokumente überwachen**
Erkennt Serien (Gehaltsabrechnung, Stromrechnung, Kontoauszug) und meldet, wenn ein Monat fehlt. Klassischer „das hätte ich sonst nie gemerkt"-Moment.
*Nutzen: hoch · Aufwand: mittel*

**B4 · Archiv fragen über das ganze Archiv**
Heute rankt `AskArchiveView` nur die geladenen Dokumente (Seitengröße!). Nötig ist ein lokaler Embedding-Index über alle Dokumente, inkrementell beim Sync gefüllt. Ohne das ist die Antwortqualität Glückssache.
*Nutzen: hoch · Aufwand: mittel*

**B5 · ASN-Barcode-Scanner**
Kamera auf den ASN-Aufkleber halten → Dokument öffnet sich. Umgekehrt beim Erfassen die nächste freie ASN vorschlagen und ein Etikett zum Drucken erzeugen. Für alle, die Papier zusätzlich physisch archivieren, ist das der fehlende Baustein zwischen Ordner und App.
*Nutzen: mittel bis hoch · Aufwand: mittel*

**B6 · Seitenwerkzeuge**
Seiten drehen, löschen, neu sortieren, zwei PDFs zusammenführen, ein PDF teilen — lokal vor dem Upload über PDFKit, für bestehende Dokumente über `bulk_edit` am Server.
*Nutzen: mittel bis hoch · Aufwand: mittel*

### Stufe C — Plattform & Reichweite

**C1 · Dateianbieter-Erweiterung (File Provider)**
Paperless erscheint als Ordner in der Dateien-App: durchsuchen, öffnen, per Drag & Drop hineinlegen — auch aus anderen Apps und vom Mac. Das kann auf iOS bisher niemand und würde die App aus der Nische holen.
*Nutzen: hoch · Aufwand: groß*

**C2 · Server-Push statt Polling**
ngx 3.0 kann Workflows mit Webhook. Ein schlanker Relay-Dienst (Webhook → APNs) macht echte Sofort-Benachrichtigungen möglich; Paperparrot legt den Workflow sogar automatisch an. Kostet allerdings eigenen Serverbetrieb.
*Nutzen: mittel · Aufwand: groß (inkl. Infrastruktur)*

**C3 · Widgets und Systemintegration nachziehen**
Interaktives Widget (Posteingang + Scan-Knopf direkt im Widget), Sperrbildschirm-Widget, Control-Center-Steuerung, Aktionstaste. Alles Standard-APIs seit iOS 17/18, überschaubarer Aufwand, hohe Sichtbarkeit.
*Nutzen: mittel · Aufwand: klein bis mittel*

**C4 · Berechtigungen und Speicherpfade**
Besitzer, Lese-/Schreibrechte, Speicherpfade anzeigen und setzen. Pflicht, sobald mehrere Personen dieselbe Instanz nutzen — und der offensichtlichste Rückstand gegenüber Swift Paperless.
*Nutzen: mittel · Aufwand: mittel*

**C5 · Eigene Felder in der App anlegen und verwalten**
Bisher nur lesen und befüllen. Anlegen/Ändern/Löschen fehlt, obwohl die API es hergibt.
*Nutzen: mittel · Aufwand: klein*

**C6 · Server-KI von ngx 3.0 als Alternative**
Wer ein älteres iPhone hat, bekommt heute keine KI-Funktion. Wenn der Server KI aktiviert hat, ließen sich Chat, Vorschläge und ähnliche Dokumente von dort beziehen — mit klarer Anzeige, wohin die Daten gehen.
*Nutzen: mittel · Aufwand: mittel*

**C7 · Android auf iOS-Stand bringen**
Der einzige aktive Android-Client ist tot. Die Lücken sind bekannt (siehe FEATURES.md, Abschnitt 10). Wer dort zuerst liefert, nimmt einen unbesetzten Markt.
*Nutzen: strategisch hoch · Aufwand: groß*

**C8 · Statistik-Dashboard**
Dokumente pro Monat, häufigste Sender, Speicherentwicklung, Posteingangs-Rückstand über die Zeit. Nettes Beiwerk, kein Kernnutzen.
*Nutzen: niedrig bis mittel · Aufwand: klein*

---

## 3. Empfehlung für die nächste Version

Ein Release mit klarem Thema **„Posteingang schneller leeren"**:

1. A2 ngx-Vorschläge
2. A4 echter Inbox-Tag
3. A3 Verarbeitungsstatus
4. A5 `bulk_edit`
5. A1 Triage-Modus (baut auf 1–4 auf)

Danach als großes Alleinstellungsmerkmal **B1 Fristen-Radar**, flankiert von **B2 Dublettenprüfung**.
A7 (mTLS/Header) parallel einplanen — es entscheidet darüber, ob ein Teil der Nutzer die App überhaupt starten kann.
