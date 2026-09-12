import Foundation

enum AppConstants {
    static let appGroupId = "group.com.Thomas.paperless"
    static let appVersion = "2.1.2"
    static let urlScheme = "paperless24"
    static let appStoreId = "6770317210"

    /// Schemata, die als Rückruf-Ziel der Dokumentauswahl (`paperless24://pick?callback=`)
    /// nicht in Frage kommen.
    ///
    /// Den Rückruf darf jede App auf dem Gerät setzen. Ohne Prüfung ließe sich dort eine
    /// Web-Adresse hinterlegen — die App würde nach der Auswahl den Browser öffnen und
    /// Dokument-ID und Titel als Parameter an eine fremde Seite übergeben. Der Rückruf geht
    /// an eine App auf demselben Gerät, ein Web- oder Datei-Schema ergibt hier also nie Sinn.
    private static let blockedCallbackSchemes: Set<String> = [
        "http", "https", "file", "data", "javascript", "mailto", "tel", "sms", "ftp", "about"
    ]

    /// Prüft das Rückruf-Ziel der Dokumentauswahl.
    static func isAllowedPickerCallback(_ raw: String) -> Bool {
        guard let scheme = URL(string: raw)?.scheme?.lowercased(), !scheme.isEmpty else { return false }
        return !blockedCallbackSchemes.contains(scheme)
    }

    static let appChangelog: [ChangelogEntry] = [
        ChangelogEntry(version: "2.1.4", date: "12.09.2026", changes: [
            "Behoben: Der Posteingang zählte viel zu viele Dokumente. Die App hat jeden Eintrag ohne Sender als unbearbeitet gewertet – in einem gepflegten Archiv sind das hunderte längst erledigte Dokumente, und das Abzeichen am Tab zeigte eine ganz andere Zahl als die Übersicht in den Einstellungen.",
            "Der Posteingang richtet sich jetzt nach demselben Merkmal wie die Weboberfläche: nach den Tags, die auf dem Server als Posteingang markiert sind. Ist dort kein Tag so markiert, bleibt der Posteingang leer und sagt das auch.",
            "Behoben: Bei sehr vielen Tags, Sendern oder Dokumenttypen holte die App nur die ersten 1000 und ließ den Rest stillschweigend weg. Jetzt kommt die vollständige Liste an.",
        ]),
        ChangelogEntry(version: "2.1.3", date: "10.08.2026", changes: [
            "Behoben: Teilen aus anderen Apps funktioniert wieder. PDF oder Foto über das Teilen-Menü an Paperless 24 geben, die App öffnet sich und übernimmt die Datei. Klappt der Wechsel einmal nicht, geht nichts verloren – die Datei wird beim nächsten Start übernommen.",
            "Behoben: Die Systemsuche (Spotlight) findet wieder Dokumente – und jetzt das ganze Archiv statt nur der zuletzt geladenen Seite.",
            "Neu: Spotlight-Treffer zeigen die Vorschau des Dokuments statt des App-Symbols.",
            "Behoben: Mehrere Konten bleiben in der Systemsuche sauber getrennt – ein Treffer öffnet nie ein Dokument aus einem anderen Archiv.",
            "Verbessert: „Spotlight-Index neu erstellen“ meldet jetzt, wie viele Dokumente im Index gelandet sind.",
        ]),
        ChangelogEntry(version: "2.1.2", date: "10.08.2026", changes: [
            "Behoben: Beim Bearbeiten eines Dokuments wurde das Erstelldatum überschrieben – gespeichert wurde der heutige Tag statt des tatsächlichen Datums. Je nach Server konnte es außerdem um einen Tag zurückspringen.",
            "Behoben: Beim Import konnte dasselbe Dokument zweimal hochgeladen werden und lag danach doppelt im Archiv.",
            "Behoben: Ließ sich ein Dokument nicht löschen – etwa ohne Verbindung oder ohne Berechtigung –, verschwand es trotzdem aus der Liste und tauchte beim nächsten Abgleich wieder auf. Jetzt bleibt es stehen und die App nennt den Grund.",
            "Behoben: Suchbegriffe mit „&“ oder „+“ lieferten keine oder falsche Treffer.",
            "Behoben: Nach einem Kontowechsel konnten die Miniaturansichten des vorherigen Kontos in der Liste stehen bleiben.",
            "Behoben: In „Darstellung“ blieben die Vorschauen der App-Symbole leer – dort waren nur graue Kacheln zu sehen.",
            "Behoben: Wurden mehrere Dokumente mit gleichem Titel auf einmal geteilt, überschrieben sie sich gegenseitig. Die Zwischenkopien werden jetzt auch wieder aufgeräumt.",
            "Behoben: Unter ungünstigen Umständen konnte die Warteschlange mit noch nicht übertragenen Änderungen verloren gehen.",
            "Behoben: Telefonnummern und Links im erkannten Text waren an der falschen Stelle antippbar, wenn sie mehrfach im Dokument vorkamen.",
            "Sicherheit: Der Anmeldeschlüssel liegt strenger geschützt im Schlüsselbund und wandert nicht mehr in Backups auf andere Geräte.",
            "Sicherheit: Die App-Sperre fragt jetzt nach dem Gerätecode, wenn Face ID nicht verfügbar oder gesperrt ist. Vorher öffnete sich die App in diesem Fall ungeprüft. Nach einem Abbruch bleibt sie gesperrt und lässt sich über „Entsperren“ erneut öffnen.",
            "Sicherheit: Die Dokumentauswahl für Vermietoo nimmt keine Web-Adressen mehr als Rückrufziel an.",
            "Schneller: Die Dokumentliste scrollt flüssiger, die PDF-Ansicht ruckelt nicht mehr beim Blättern, und die App startet zügiger.",
            "Schneller: Texterkennung und „Archiv fragen“ blockieren die Bedienung nicht mehr, während sie rechnen.",
            "Verbessert: Antwortet der Server nicht, bricht die App nach 30 Sekunden ab, statt lange zu warten.",
        ]),
        ChangelogEntry(version: "2.1.1", date: "10.08.2026", changes: [
            "Behoben: In Englisch, Französisch, Spanisch und Italienisch blieben einzelne Texte auf Deutsch stehen – darunter die Kacheln auf der Startseite, der Netzwerkscanner, die Archiv-Frage und die Auswahllisten für Filter, Tags und Sender. Alle vier Sprachen sind jetzt vollständig übersetzt.",
            "Behoben: Werte in eigenen Feldern werden jetzt passend zum Feldtyp angezeigt – Datumsangaben im Format der Gerätesprache, Beträge mit Währung, Ja/Nein statt „true“/„false“ und bei Auswahlfeldern die Bezeichnung statt der internen Kennung. Verknüpfte Dokumente erscheinen mit ihrem Titel.",
        ]),
        ChangelogEntry(version: "2.1.0", date: "10.08.2026", changes: [
            "Neu: Das Design lässt sich jetzt mit diversen Farben anpassen – Indigo, Ozean, Wald, Sonnenuntergang, Graphit und Kontrast stehen als fertige Farbthemen bereit.",
            "Mit „Eigene Farbe“ wählst du deine Akzentfarbe frei über den Farbwähler.",
            "Ein Farbthema färbt nicht nur Knöpfe, sondern auch Verläufe und Chips – die App wirkt aus einem Guss. Tag-Farben kommen weiterhin vom Server und bleiben unverändert.",
            "Alle Farben gibt es in einer hellen und einer dunklen Variante, damit sie in beiden Erscheinungsbildern gut lesbar bleiben.",
        ]),
        ChangelogEntry(version: "2.0.0", date: "28.07.2026", changes: [
            "Unterstützt paperless-ngx 3.0 und neuer. Mit 3.0 hat der Server das Format seiner Antworten umgestellt – Dokumente, Notizen und Auswahlfelder kamen danach anders an, als die App sie erwartet hat.",
            "Die App einigt sich beim ersten Kontakt mit dem Server auf ein gemeinsames Datenformat. Ältere Installationen ab paperless-ngx 2.x funktionieren unverändert weiter, es ist nichts einzustellen.",
            "Nach einem Server-Update genügt ein Start der App – sie erkennt die neue Version von selbst.",
            "Behoben: Nach dem Server-Update konnte dasselbe Dokument mehrfach in der Übersicht landen. Dadurch ließen sich Dokumente nicht mehr per Tipp öffnen, und das Kontextmenü ging auf der falschen Kachel auf.",
            "iPhone: Dokumente und Posteingang lassen sich wieder per Tipp öffnen",
            "iPad: Dokumente lassen sich in der Übersicht wieder per Tipp öffnen",
            "iPad: Neue Dreispalten-Ansicht – Filter links, Dokumente in der Mitte, Vorschau rechts",
            "iPad: Filter, Tags, Sender, Typen und gespeicherte Ansichten jetzt in einer eigenen Seitenleiste statt in der schmalen Chip-Leiste",
            "iPad: Dialoge wie Import, Bearbeiten, Netzwerkscanner und Archiv fragen werden nicht mehr halb leer dargestellt",
            "iPad: Doppelte Navigationsleiste in den Einstellungen entfernt",
            "Suchfeld sitzt jetzt fest in der Navigationsleiste und springt beim Umschalten von Raster und Liste nicht mehr",
            "Lädt eine Vorschau nicht, zeigt die App den Grund an und bietet einen erneuten Versuch – statt eines endlosen Ladekreises",
        ]),
        ChangelogEntry(version: "1.8.1", date: "14.06.2026", changes: [
            "Du kannst die App jetzt direkt aus den Einstellungen heraus bewerten.",
        ]),
        ChangelogEntry(version: "1.8.0", date: "08.06.2026", changes: [
            "Sender, Typ und Tags lassen sich bei Import und Bearbeiten jetzt durchsuchen – Suchfeld statt langer Liste",
        ]),
        ChangelogEntry(version: "1.7.0", date: "02.06.2026", changes: [
            "Neu: Stapel scannen – einen Stapel am Stück scannen, die KI trennt automatisch in einzelne Dokumente",
            "Neu: Dokumente übersetzen (on-device)",
            "Einstellungen: Stapel-Trennung und Übersetzen einzeln an-/abschaltbar",
        ]),
        ChangelogEntry(version: "1.6.0", date: "02.06.2026", changes: [
            "Neu: Apple Intelligence – Dokumente on-device zusammenfassen und das Archiv per Frage durchsuchen (semantische Suche & Antworten)",
            "Neu: Intelligenteres Auto-Tagging mit Apple Intelligence (schlägt auch neue Tags/Sender vor)",
            "Neu: Siri & Kurzbefehle – Scannen, Posteingang, Suche und Archiv-Frage per Sprachbefehl",
            "Neu: Benachrichtigungen über neue Dokumente im Posteingang",
            "Neu: Netzwerkscanner (AirScan) direkt in der App",
            "Neu: Dokumente per Drag & Drop in andere Apps ziehen",
            "Neu: Anklickbare Telefonnummern, Links und Adressen im OCR-Text",
            "Neu: Zwei-Spalten-Ansicht auf iPad und Mac",
            "Neu: Einstellbare Kachelgröße",
            "Neu: Einstellungen werden über iCloud zwischen Geräten synchronisiert",
            "Neu: Mehrere Dokumente gleichzeitig an Vermietoo übergeben",
            "Neu: Suchfeld in der Tags-, Sender- und Typen-Verwaltung",
            "Neu: Mehr Lade-Optionen – 1000, 2000 und Alles",
            "Verbessert: Archiv-Fragen zeigt jetzt einen Ladeindikator mit Statustext",
            "Verbessert: Zwei-Spalten-Ansicht auf iPad/Mac wechselt die Vorschau jetzt zuverlässig",
            "Verbessert: Klare Hinweise, wenn Apple Intelligence noch nicht bereit ist",
            "Einstellungen: KI-Funktionen lassen sich an- und abschalten",
        ]),
        ChangelogEntry(version: "1.5.0", date: "02.06.2026", changes: [
            "Neu: Eigene Felder (Custom Fields) – alle Typen anzeigen und bearbeiten, inkl. Auswahllisten und Dokument-Verknüpfungen",
            "Neu: Info-Tab in der Dokumentansicht zeigt Metadaten und eigene Felder auf einen Blick",
            "Neu: Papierkorb – gelöschte Dokumente wiederherstellen oder endgültig entfernen",
            "Neu: Freigabe-Links erstellen, kopieren und widerrufen – mit optionalem Ablaufdatum",
            "Neu: Gespeicherte Ansichten vom Server werden synchronisiert; bestehende lokale Filter werden automatisch übernommen",
            "Neu: Verschachtelte Tags (Unter-Tags) werden hierarchisch dargestellt",
            "Neu: Nach eigenen Feldern filtern",
        ]),
        ChangelogEntry(version: "1.4.3", date: "02.06.2026", changes: [
            "Fix: Im Auswahl-Modus für Vermietoo öffnete ein Tipp auf ein Dokument nur die Detailansicht, statt es auszuwählen — die Auswahl klappt jetzt direkt",
        ]),
        ChangelogEntry(version: "1.4.2", date: "31.05.2026", changes: [
            "Neu: Frisches App-Icon im modernen Look — mit eigener Dark- und getönter Variante",
        ]),
        ChangelogEntry(version: "1.4.1", date: "26.05.2026", changes: [
            "Fix: Login mit aktivierter 2-Faktor-Authentifizierung (TOTP) funktioniert jetzt korrekt",
        ]),
        ChangelogEntry(version: "1.4.0", date: "24.05.2026", changes: [
            "Neu: Dokument-Auswahl für Vermietoo — Dokument direkt an Vermietoo übergeben",
            "Neu: Picker-Modus mit lila Banner zeigt aktive Auswahl-Sitzung an",
        ]),
        ChangelogEntry(version: "1.3.0", date: "20.05.2026", changes: [
            "Neu: App in 5 Sprachen verfügbar (DE, EN, FR, ES, IT)",
            "Neu: Sprachauswahl direkt in den Einstellungen",
        ]),
        ChangelogEntry(version: "1.2.0", date: "10.05.2026", changes: [
            "Sicherheit: Login-Token wird im iOS Keychain gespeichert",
            "Neu: Infinite Scroll statt Komplettladen",
            "Performance: Dokumentenliste wird gecacht",
            "Code aufgeteilt in modulare Dateien",
        ]),
        ChangelogEntry(version: "1.1.0", date: "15.02.2026", changes: [
            "Fix für Apple Review (iPad Layout)",
            "Fix: FaceID Loop",
            "Fix: Scanner & Import",
        ]),
        ChangelogEntry(version: "1.0.0", date: "06.02.2026", changes: ["Initialer Release"]),
    ]
}
