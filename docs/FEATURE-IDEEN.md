# Feature-Ideen

Stand: 12.09.2026 · App-Version 2.1.4 · Basis: [FEATURES.md](FEATURES.md) + Code-Inventur

Die vorherige Fassung (28.07.2026) steckt in der Git-Historie. Diese Fassung korrigiert den
Stand, ergänzt Befunde aus dem Code und sortiert neu.

---

## 1. Stand der letzten Vorschlagsliste

| Vorschlag (Juli) | Status heute |
|---|---|
| A4 Echter Posteingang über Inbox-Tag | ✅ erledigt (v2.1.4, `AppStore.loadInbox`) |
| A2 ngx-Vorschläge (`/api/documents/{id}/suggestions/`) | ❌ offen |
| A3 Verarbeitungsstatus (`/api/tasks/`) | ❌ offen |
| A5 `bulk_edit` | ❌ offen — Sammelaktionen sind weiter N Einzel-PATCH |
| A1 Triage-Modus | ❌ offen |
| A6 Mehrfach-/Negativfilter | ❌ offen |
| A7 mTLS + eigene Header | ❌ offen |
| B1 Fristen-Radar | ⚠️ war gebaut, am 04.06.2026 **wieder entfernt** („funktioniert mittelgut") |
| B2 Dublettenprüfung | ⚠️ war gebaut (Wort-Jaccard + Kamera-Check), am 04.06.2026 **wieder entfernt** |
| B3 Wiederkehrende Dokumente | ❌ offen |
| B4 Embedding-Index über das ganze Archiv | ❌ offen (`SemanticRanker` wurde mit ausgebaut) |
| B5 ASN-Barcode | ❌ offen — kein Barcode-Code in der App |
| B6 Seitenwerkzeuge | ❌ offen |
| C1 File Provider · C2 Server-Push · C4 Berechtigungen · C5 eigene Felder anlegen · C6 Server-KI · C7 Statistik | ❌ offen |
| C3 Widgets/Systemintegration nachziehen | ❌ offen — Widget kennt nur `systemSmall/Medium/Large` |

Was seit Juli tatsächlich kam: Inbox-Tag-Logik, Spotlight mit Vorschaubildern, Sicherheitsrunde,
Teilen-Reparatur, Android-Port wieder entfernt.

**Wichtig zur Vorgeschichte:** Fristen-Radar, Kündigungs-Assistent, Dublettenansicht, Kamera-Check
(„Schon vorhanden?") und die KI-Suche waren für 1.7.0 fertig und wurden am 04.06.2026 auf Wunsch
wieder entfernt — Begründung: „funktioniert mittelgut". Diese Ideen sind also keine Lücken,
sondern Qualitätsprobleme. Wer sie erneut angeht, muss sagen, was diesmal anders ist (siehe B1/B3).

---

## 2. Neue Befunde aus dem Code (die wichtigsten)

### 2.1 Filter laufen nur über die geladene Seite — nicht über das Archiv

`AppStore.updateFilteredDocs()` (Zeile 578 ff.) filtert `documents` **lokal**, und
`PaperlessAPI.fetchDocuments(page:ordering:)` schickt außer `ordering`, `page` und `page_size`
keinen einzigen Filterparameter. Standard-Seitengröße ist 25.

Folge: Wer bei 3.000 Dokumenten auf „Tag = Versicherung" tippt, filtert die 25 geladenen
Dokumente. Sortierung geht an den Server, Filterung nicht — das ist inkonsistent, und die
Einstellung „Seitengröße bis 2000 / alles" ist im Grunde der Workaround dafür (mit dem Preis:
langsamer Start, viel Speicher, viel Netz).

Das ist kein Komfortthema, sondern ein Korrektheitsthema: Die Liste behauptet, ein Filter sei
angewendet, zeigt aber ein zufälliges Teilergebnis.

### 2.2 Der Posteingang lässt sich nicht abarbeiten

`InboxView` bietet Bearbeiten und Löschen — und sonst nichts. Um ein Dokument aus dem
Posteingang zu nehmen, muss man „Bearbeiten" öffnen, in der Tag-Liste den Inbox-Tag suchen und
abwählen, speichern. Es gibt keinen Auswahlmodus (den hat nur `MainDocView`) und keine
Sammelaktion.

Der Posteingang ist der einzige Bildschirm, den ein Paperless-Nutzer *täglich* benutzt, und
genau dort fehlt die Hauptaktion.

### 2.3 Sammelaktionen können Tags nur hinzufügen

`bulkAssignTags` bildet `Set(doc.tags).union(neue)` — Entfernen ist gar nicht vorgesehen. Dazu
läuft jede Sammelaktion als ein PATCH pro Dokument über die Warteschlange, ohne Fortschritt und
ohne Fehlerbilanz.

### 2.4 „Archiv fragen" sieht fast nichts

`AskArchiveView.rankedDocuments` rankt `store.documents` — also die geladene Seite. Bei
Standardeinstellung durchsucht die semantische Suche 25 von 3.000 Dokumenten. Die Funktion ist
das Aushängeschild der App und liefert derzeit Zufallsqualität.

### 2.5 Die Siri-Kurzbefehle sind reine Türöffner

Alle vier Intents in `AppShortcuts.swift` setzen ein Flag und öffnen die App. Keiner nimmt einen
Parameter, keiner gibt einen Wert zurück. Damit ist in Kurzbefehlen keine Automation baubar
(„Rechnung aus Mail an Paperless schicken", „Posteingangszahl vorlesen"), und Aktionstaste sowie
Control Center bleiben ungenutzt.

### 2.6 Mindestanforderung iOS 26 ist wahrscheinlich zu teuer

`IPHONEOS_DEPLOYMENT_TARGET = 26.0`. Im ganzen Projekt gibt es aber genau **zwei**
`#available(iOS 26, *)`-Stellen, beide in `AIService` um `FoundationModels` herum — sauber
gekapselt und ohnehin abschaltbar. Kein Liquid-Glass-API, kein anderes 26er-Symbol im Code.

Für eine kostenpflichtige App heißt iOS 26 als Untergrenze: alles vor iPhone 11 fällt weg, und
jedes Gerät, das noch auf 18 steht, ebenfalls. Apple Intelligence braucht ohnehin ein 15 Pro
oder neuer — die KI-Funktionen sind also auch mit niedrigerem Target nicht schlechter erreichbar.
Ein Absenken auf iOS 18 wäre einen Build-Versuch wert; das ist die billigste Reichweiten-
verdopplung, die zu haben ist.

---

## 3. Vorschläge

Bewertung: **Nutzen** = wie oft es im Alltag hilft · **Aufwand** = grobe Schätzung.

### Stufe 0 — Fundament. Zuerst, weil alles andere darauf aufbaut

**0.1 · Filter an den Server geben**
`tags__id__all`, `correspondent__id__in`, `document_type__id__in`, `created__date__gte/lte`,
`custom_fields__…` als Query-Parameter, Paginierung innerhalb des Filters (analog zur schon
vorhandenen Such-Paginierung). Danach stimmt die Trefferzahl, Mehrfach- und Negativfilter fallen
fast gratis ab, Server-Saved-Views funktionieren wirklich, und die Standard-Seitengröße kann bei
25 bleiben.
*Nutzen: sehr hoch · Aufwand: mittel*

**0.2 · „Erledigt" im Posteingang**
Wisch nach rechts entfernt den Inbox-Tag. Dazu Auswahlmodus im Posteingang und „Auswahl als
erledigt markieren". Zwei Tage Arbeit für die Aktion, die den Alltag ausmacht.
*Nutzen: sehr hoch · Aufwand: klein*

**0.3 · `bulk_edit` statt N Einzel-PATCH**
`POST /api/documents/bulk_edit/` mit `modify_tags` (add **und** remove), `set_correspondent`,
`set_document_type`, `set_storage_path`, `delete`. Ein Aufruf, eine Rückmeldung. Voraussetzung
für 0.2 im Stapel und für den Triage-Modus.
*Nutzen: hoch · Aufwand: klein*

**0.4 · ngx-Vorschläge nutzen**
`GET /api/documents/{id}/suggestions/` liefert Sender, Typ, Tags und ASN aus dem trainierten
Klassifikator des Servers. Funktioniert auf **jedem** iPhone, auch ohne Apple Intelligence, und
ist in Stunden eingebaut. Ideal als Vorbelegung für 0.2 und A1.
*Nutzen: hoch · Aufwand: klein*

**0.5 · Verarbeitungsstatus nach dem Upload**
Heute meldet die App „Fertig", sobald der Server die Datei angenommen hat. Ob der Consumer sie
verarbeitet hat oder an Duplikat/OCR gescheitert ist, erfährt der Nutzer nie. Task-ID pollen
(`/api/tasks/`), Ergebnis anzeigen, bei Fehler den Grund nennen.
*Nutzen: hoch · Aufwand: klein*

### Stufe A — Bedienung

**A1 · Posteingang-Triage („Durchwischen")**
Vollbild: Vorschau oben, darunter drei große Felder für Sender, Typ, Tags — vorbelegt aus 0.4
bzw. Apple Intelligence. Bestätigen, nächstes Dokument. Nach 0.2–0.4 ist das überwiegend
Oberfläche.
*Nutzen: sehr hoch · Aufwand: mittel*

**A2 · Im Detail zum nächsten Dokument wischen**
`DocumentDetailView` zeigt genau ein Dokument; zurück zur Liste, nächstes antippen. Eine
`TabView(.page)` über `filteredDocs` ersetzt zwei Tipps pro Dokument.
*Nutzen: hoch · Aufwand: klein*

**A3 · Textausschnitt im Suchtreffer**
Bei `?query=` liefert ngx Trefferinformationen mit; die App zeigt trotzdem nur Titel und Sender.
Der Satz, in dem der Begriff steht, entscheidet aber darüber, ob man das Dokument öffnen muss.
*Nutzen: hoch · Aufwand: klein bis mittel*

**A4 · Anzeigefelder der Liste konfigurierbar**
Welche Zeile welche Metadaten zeigt (ASN, Typ, Hinzugefügt-Datum, eigenes Feld) — Paperparrot
kann das, wir nicht. Nach 0.1 auch sinnvoll sortierbar.
*Nutzen: mittel · Aufwand: klein*

**A5 · Diagnose-Ansicht**
Server-Version, die tatsächlich verhandelte API-Version (`APIVersionNegotiator` kennt sie, zeigt
sie nirgends), Token-Status, letzte Netzfehler, Cache-Größe, Queue-Länge — als kopierbarer
Textblock. Bei einer bezahlten App gegen Self-Hosting-Zoo ist das gelebte Supportkosten-Senkung.
*Nutzen: mittel (hoch für den Support) · Aufwand: klein*

### Stufe B — Alleinstellung ausbauen

**B1 · Fristen-Radar, zweiter Versuch**
Der Nutzen ist unbestritten (Rechnung überfällig, Vertrag läuft aus, Garantie endet — der
eigentliche Grund, warum Menschen archivieren, und kein Konkurrent macht es). Version 1 wurde
verworfen, weil sie „mittelgut" funktionierte. Was anders sein müsste:

- **Nicht das LLM raten lassen.** Zuerst deterministisch: `NSDataDetector` plus feste Muster
  („zahlbar bis", „Kündigungsfrist", „gültig bis", „Garantie", IBAN-Nähe, Betragszeile). Die KI
  nur zur Einordnung *gefundener* Daten (Fälligkeit vs. Rechnungsdatum vs. Vertragsbeginn).
- **Kein stiller Hintergrundlauf über 10 Dokumente pro Sync.** Stattdessen genau dort fragen, wo
  der Nutzer sowieso hinsieht: beim Import und im Posteingang-Triage, mit sichtbarem Vorschlag
  („Fällig 30.09.2026 — übernehmen?").
- **Nur bestätigte Fristen zählen.** Was der Nutzer bestätigt, landet im eigenen Feld und in die
  Erinnerung; was er ablehnt, verschwindet. Keine Liste voller Falschtreffer, die Vertrauen
  kostet.
- **Ein Dokumenttyp zuerst** (Rechnungen mit Zahlungsziel), messen, dann erweitern.

*Nutzen: sehr hoch · Aufwand: mittel · Voraussetzung: Genauigkeit vor Abdeckung*

**B2 · Embedding-Index über das ganze Archiv**
Ohne das bleibt „Archiv fragen" (siehe 2.4) Glückssache: inkrementell beim Sync gefüllter
lokaler Index, Vektoren je Konto auf der Platte. Reparatur einer beworbenen Funktion, nicht
Ausbau.
*Nutzen: hoch · Aufwand: mittel*

**B3 · Dublettenprüfung, zweiter Versuch**
Version 1 (Wort-Jaccard je Korrespondenten-Bucket, plus Kamera-Check) fiel ebenfalls raus. Der
wahrscheinliche Grund: Textähnlichkeit schlägt bei Serienbriefen desselben Absenders ständig an —
zwei Stromrechnungen aus Januar und Februar sind zu 95 % derselbe Text. Besser als Ähnlichkeit
ist die harte Signatur: **Sender + Betrag + Belegdatum**, ergänzt um Rechnungs-/Kundennummer aus
dem OCR-Text. Das trifft entweder genau oder gar nicht, und ein einzelner Treffer lässt sich als
„Das hast du schon: <Titel>, hochgeladen am …" belastbar anzeigen.
Alternative ohne eigene Logik: den Server entscheiden lassen — ngx erkennt Duplikate beim
Verarbeiten und meldet sie als Task-Fehler, was mit 0.5 ohnehin sichtbar wird.
*Nutzen: hoch · Aufwand: mittel (klein, wenn nur über 0.5 gelöst)*

**B4 · Wiederkehrende Dokumente überwachen**
Serien erkennen (Gehaltsabrechnung, Stromrechnung, Kontoauszug) und melden, wenn ein Monat
fehlt. Der „das hätte ich sonst nie gemerkt"-Moment.
*Nutzen: hoch · Aufwand: mittel*

**B5 · Upload-Regeln**
Vorbelegung pro Quelle: was über die Share-Extension aus der Banking-App kommt, wird
Typ „Kontoauszug" + Tag „Bank"; was der Netzwerkscanner liefert, landet im Posteingang mit
Standardsender. Regeln als Liste in den Einstellungen, ausgewertet in der bestehenden
Warteschlange.
*Nutzen: mittel bis hoch · Aufwand: mittel*

### Stufe C — Plattform & Reichweite

**C1 · Mindest-iOS senken (siehe 2.6)**
Build gegen iOS 18 versuchen, die zwei `#available`-Stellen bleiben wie sie sind. Reine
Reichweite, keine neue Funktion — für eine gekaufte App aber der direkteste Umsatzhebel.
*Nutzen: hoch · Aufwand: klein (falls der Build durchläuft)*

**C2 · App Intents mit Parametern und Rückgabewerten**
„Dokument hochladen" mit Datei-Parameter, „Dokumente suchen" gibt Treffer als Entities zurück,
„Posteingangszahl" als Wert. Damit werden Kurzbefehl-Automationen, Aktionstaste und Control
Center nutzbar. Die vier bestehenden Intents bleiben als Türöffner daneben stehen.
*Nutzen: hoch · Aufwand: klein bis mittel*

**C3 · Sperrbildschirm-, Control-Center- und interaktives Widget**
`.accessoryCircular`/`.accessoryRectangular` mit der Posteingangszahl, `ControlWidget`
„Scannen" fürs Control Center, Scan-Knopf direkt im Homescreen-Widget. Standard-APIs,
überschaubar, sehr sichtbar.
*Nutzen: mittel bis hoch · Aufwand: klein*

**C4 · mTLS und eigene HTTP-Header**
Cloudflare Access, Authelia, Proxy mit Client-Zertifikat: ohne das startet die App für einen
Teil der Self-Hoster gar nicht — Paperparrot hat es. `makeRequest` ist die einzige Stelle für
Header, dazu ein `URLSessionDelegate` für die Zertifikats-Challenge und Import per PKCS#12.
*Nutzen: hoch für eine kleine, laute Gruppe · Aufwand: mittel*

**C5 · Eigene Felder anlegen und ändern**
`PaperlessAPI` hat nur `fetchCustomFields`. Anlegen/Ändern/Löschen kann die API längst.
*Nutzen: mittel · Aufwand: klein*

**C6 · Berechtigungen, Besitzer, Speicherpfade**
Pflicht, sobald mehrere Personen eine Instanz nutzen, und der offensichtlichste Rückstand
gegenüber Swift Paperless.
*Nutzen: mittel · Aufwand: mittel*

**C7 · ASN-Barcode**
Kamera auf den Aufkleber → Dokument öffnet sich; beim Erfassen die nächste freie ASN vorschlagen
und ein Etikett erzeugen. Für alle, die zusätzlich physisch archivieren, der fehlende Baustein.
*Nutzen: mittel · Aufwand: mittel*

**C8 · Seitenwerkzeuge**
Seiten drehen, löschen, sortieren, zwei PDFs zusammenführen, eines teilen — lokal vor dem Upload
über PDFKit.
*Nutzen: mittel · Aufwand: mittel*

**C9 · Server-KI von ngx 3.0 als Alternative**
Wer kein Apple-Intelligence-Gerät hat, bekommt heute keine KI. Wenn der Server sie aktiviert
hat: Chat, Vorschläge, ähnliche Dokumente von dort — mit klarer Anzeige, wohin die Daten gehen.
*Nutzen: mittel · Aufwand: mittel*

**C10 · Dateianbieter-Erweiterung (File Provider)**
Paperless als Ordner in der Dateien-App, auch am Mac. Kann auf iOS bisher niemand.
*Nutzen: hoch · Aufwand: groß*

**C11 · Server-Push statt stündliches Polling**
ngx-3.0-Workflow mit Webhook → eigener Relay → APNs. Bedeutet eigenen Serverbetrieb und
Datenschutz-Aufwand; deshalb hinten.
*Nutzen: mittel · Aufwand: groß*

**C12 · Statistik-Dashboard**
Dokumente pro Monat, häufigste Sender, Posteingangs-Rückstand über die Zeit. Beiwerk.
*Nutzen: niedrig bis mittel · Aufwand: klein*

---

## 4. Empfehlung

**v2.2 — „Filter und Posteingang, die halten was sie versprechen"**
0.1 Server-Filter · 0.2 Erledigt-Wisch · 0.3 `bulk_edit` · 0.5 Upload-Status · A2 Wischen im Detail

Das sind vier Reparaturen und eine Kleinigkeit, alle im Kern der täglichen Nutzung. 0.1 räumt
gleich das „Seitengröße = alles"-Problem mit weg.

**v2.3 — „Posteingang leeren"**
0.4 ngx-Vorschläge · A1 Triage · A3 Trefferausschnitt · C3 Widgets · C2 App Intents

**v2.4 — „Merkt sich, was wichtig ist"**
B2 Archiv-Index (Reparatur einer beworbenen Funktion) · B1 Fristen-Radar im neuen Anschnitt ·
B3 Dubletten, zunächst nur als Task-Fehler aus 0.5

B1 und B3 sind bewusst hinten: Beide waren schon einmal gebaut und wurden wegen Qualität
verworfen. Sie gehören erst wieder angefasst, wenn 0.5 (Task-Status) und der Triage-Modus stehen
— dann gibt es die Oberfläche, in der ein Vorschlag bestätigt statt stillschweigend gespeichert
wird, und genau daran hing die Qualität.

**Parallel, unabhängig vom Thema:**
C1 (iOS-Target prüfen — je früher, desto mehr Käufer) und C4 (mTLS/Header — entscheidet, ob ein
Teil der Nutzer die App überhaupt starten kann).

---

## 5. Wettbewerb, kurz

**Paperparrot** (kommerziell): Server-Push per selbst angelegtem ngx-Workflow, mTLS + eigene
Header, serverloser Modus mit iCloud-Sync, konfigurierbare Listenspalten, Office-Import,
ngx-3.0-KI. Alles davon fehlt uns.

**Swift Paperless** (kostenlos, quelloffen): vollständig am ngx-Datenmodell, inklusive
Berechtigungen und Speicherpfaden. Stärke Vollständigkeit, Schwäche eigene Intelligenz.

**paperless-ngx 3.0** selbst: Tantivy-Suche, Dateiversionen, Sharelink-Bundles, Remote-OCR,
Server-KI mit Dokument-Chat und ähnlichen Dokumenten. Nichts davon nutzt die App.

**Unser Vorsprung:** Apple Intelligence on-device, Übersetzen, Siri, Widget, AirScan,
Vermietoo-Anbindung. Den Vorsprung hält man, indem die KI-Funktionen *verlässlich* werden
(B1–B3) — nicht, indem noch mehr ngx-Features nachgebaut werden.
