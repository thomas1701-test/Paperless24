import Testing
import Foundation
@testable import Paperless24

/// Deckt die Prüfung des Rückruf-Ziels der Dokumentauswahl ab.
///
/// `paperless24://pick?callback=…` darf jede App auf dem Gerät aufrufen. Ohne Prüfung ließe
/// sich dort eine Web-Adresse hinterlegen — nach der Auswahl würde die App den Browser öffnen
/// und Dokument-ID und Titel an eine fremde Seite übergeben.
struct PickerCallbackTests {

    @Test("Rückruf an eine App auf demselben Gerät ist erlaubt")
    func allowsCustomAppScheme() {
        #expect(AppConstants.isAllowedPickerCallback("vermietoo://import"))
        #expect(AppConstants.isAllowedPickerCallback("vermietoo://import?session=42"))
    }

    /// Browser-Schemata, die eine Webseite öffnen — an einer Sperrliste vorbei.
    @Test("Browser-Umwege sind ausgeschlossen")
    func rejectsBrowserSchemes() {
        #expect(!AppConstants.isAllowedPickerCallback("x-safari-https://fremde-domain.example/sammel"))
        #expect(!AppConstants.isAllowedPickerCallback("googlechromes://fremde-domain.example"))
        #expect(!AppConstants.isAllowedPickerCallback("firefox://open-url?url=https://fremde-domain.example"))
        #expect(!AppConstants.isAllowedPickerCallback("shortcuts://run-shortcut?name=x"))
    }

    @Test("Web-Adressen sind ausgeschlossen")
    func rejectsWebSchemes() {
        #expect(!AppConstants.isAllowedPickerCallback("https://fremde-domain.example/sammel"))
        #expect(!AppConstants.isAllowedPickerCallback("http://fremde-domain.example/sammel"))
        #expect(!AppConstants.isAllowedPickerCallback("HTTPS://Fremde-Domain.example"))
    }

    @Test("Datei-, Daten- und Skript-Schemata sind ausgeschlossen")
    func rejectsDangerousSchemes() {
        #expect(!AppConstants.isAllowedPickerCallback("file:///etc/passwd"))
        #expect(!AppConstants.isAllowedPickerCallback("data:text/html,<script>"))
        #expect(!AppConstants.isAllowedPickerCallback("javascript:alert(1)"))
        #expect(!AppConstants.isAllowedPickerCallback("mailto:jemand@example.com"))
    }

    @Test("Ohne Schema kein Rückruf")
    func rejectsSchemeless() {
        #expect(!AppConstants.isAllowedPickerCallback(""))
        #expect(!AppConstants.isAllowedPickerCallback("einfach-nur-text"))
        #expect(!AppConstants.isAllowedPickerCallback("/pfad/zur/datei"))
    }
}

/// Deckt die Ablage für das Teilen-Blatt ab. Dokumenttitel sind freier Text und landen
/// unverändert im Dateinamen.
///
/// `.serialized`, weil sich alle Tests hier dasselbe Ablageverzeichnis teilen: `cleanUp()`
/// löscht es komplett, und parallel laufende Tests haben sich damit gegenseitig die Dateien
/// unter den Füßen weggeräumt.
@Suite(.serialized)
struct ShareStagingTests {

    @Test("Schrägstriche und Doppelpunkte verschwinden aus dem Dateinamen")
    func stripsPathSeparators() {
        #expect(ShareStaging.safeFilename("Rechnung 03/2026.pdf") == "Rechnung 03-2026.pdf")
        #expect(!ShareStaging.safeFilename("../../Library/Preferences/x.pdf").contains("/"))
    }

    @Test("Führende Punkte fallen weg — sonst entstünde eine versteckte Datei")
    func stripsLeadingDots() {
        #expect(ShareStaging.safeFilename("...geheim.pdf") == "geheim.pdf")
    }

    @Test("Leerer Titel bekommt einen Rückfallnamen")
    func usesFallbackForEmptyTitle() {
        #expect(ShareStaging.safeFilename("") == "Dokument.pdf")
        #expect(ShareStaging.safeFilename("   ") == "Dokument.pdf")
        #expect(ShareStaging.safeFilename("///") == "Dokument.pdf")
    }

    @Test("Sehr lange Titel werden gekürzt")
    func truncatesLongNames() {
        let long = String(repeating: "a", count: 400) + ".pdf"
        #expect(ShareStaging.safeFilename(long).count <= 100)
    }

    @Test("Zwei Dokumente mit gleichem Titel überschreiben sich nicht")
    func stagesIntoSeparateFolders() throws {
        defer { ShareStaging.cleanUp() }
        let first = try #require(ShareStaging.stage(Data("eins".utf8), filename: "Vertrag.pdf"))
        let second = try #require(ShareStaging.stage(Data("zwei".utf8), filename: "Vertrag.pdf"))

        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("eins".utf8))
        #expect(try Data(contentsOf: second) == Data("zwei".utf8))
    }

    @Test("Aufräumen entfernt die abgelegten Dateien")
    func cleanUpRemovesFiles() throws {
        let url = try #require(ShareStaging.stage(Data("x".utf8), filename: "Test.pdf"))
        ShareStaging.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
