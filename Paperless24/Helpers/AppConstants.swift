import Foundation

enum AppConstants {
    static let appGroupId = "group.com.Thomas.paperless"
    static let appVersion = "1.4.1"
    static let urlScheme = "paperless24"

    static let appChangelog: [ChangelogEntry] = [
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
