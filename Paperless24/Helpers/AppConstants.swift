import Foundation

enum AppConstants {
    static let appGroupId = "group.com.Thomas.paperless"
    static let appVersion = "1.7.0"
    static let urlScheme = "paperless24"

    static let appChangelog: [ChangelogEntry] = [
        ChangelogEntry(version: "1.7.0", date: "02.06.2026", changes: [
            "Neu: Fristen-Radar – die KI erkennt Zahlungsziele, Kündigungsfristen, Garantie- und Widerrufstermine und legt auf Wunsch Erinnerungen an",
            "Neu: Kündigungs-Assistent – entwirft passende Kündigungsschreiben (Absenderprofil in den Einstellungen)",
            "Neu: Dubletten finden – ähnliche/doppelte Dokumente aufspüren",
            "Neu: Stapel scannen – einen Stapel am Stück scannen, die KI trennt automatisch in einzelne Dokumente",
            "Neu: KI-Suche – in eigenen Worten suchen, die KI setzt die passenden Filter",
            "Neu: Dokumente übersetzen (on-device)",
            "Neu: Schon vorhanden? – per Kamera prüfen, ob ein Dokument schon im Archiv ist",
            "Einstellungen: Fristen-Radar, Stapel-Trennung und Übersetzen einzeln an-/abschaltbar",
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
