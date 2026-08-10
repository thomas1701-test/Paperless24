import XCTest

/// Deckt das ab, was auf dem Gerät kaputt war: ein Tipp auf eine Kachel in der Übersicht
/// öffnete die Detailansicht nicht. Ursache waren mehrere Erkenner (`.onDrag`,
/// `.onLongPressGesture`, `.contextMenu`) auf derselben Kachel, die den Tap verschluckten.
final class DocumentOpenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Bringt die App in den Demo-Modus, egal ob sie frisch installiert ist
    /// oder aus einem vorherigen Lauf schon angemeldet startet.
    @MainActor
    private func launchInDemoMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons["Starten"]
        if start.waitForExistence(timeout: 10) {
            start.tap()
        }

        let demo = app.buttons["Demo"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            // Bestätigungsdialog des Demo-Modus.
            let confirm = app.alerts.buttons["Starten"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Demo-Dialog erschien nicht")
            confirm.tap()
        }
        return app
    }

    /// Der Segment-Umschalter der Detailansicht. Existiert nur dort, taugt also als Beleg,
    /// dass die Ansicht wirklich aufgeschoben wurde.
    @MainActor
    private func detailIsOpen(_ app: XCUIApplication) -> Bool {
        app.buttons["Notizen"].waitForExistence(timeout: 8)
    }

    @MainActor
    func testTippAufKachelOeffnetDetailansicht() throws {
        let app = launchInDemoMode()

        let card = app.staticTexts["Stromabrechnung 2026"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Demo-Dokument erschien nicht in der Übersicht")

        card.tap()

        XCTAssertTrue(detailIsOpen(app), "Detailansicht wurde nach dem Tipp nicht geöffnet")
    }

    /// Langer Druck darf das Kontextmenü öffnen — und danach muss ein normaler Tipp
    /// weiterhin die Detailansicht aufschieben.
    @MainActor
    func testLangerDruckOeffnetKontextmenueUndBlockiertTippNicht() throws {
        let app = launchInDemoMode()

        let card = app.staticTexts["Stromabrechnung 2026"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Demo-Dokument erschien nicht in der Übersicht")

        card.press(forDuration: 1.2)

        let preview = app.buttons["Vorschau"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Kontextmenü öffnete nicht")

        // Kontextmenü schließen, ohne einen Eintrag auszulösen. Der Punkt muss innerhalb der
        // App liegen und darf weder die Vorschau der gedrückten Kachel noch die Menüliste
        // treffen: die Vorschau öffnet das Dokument, ein Menüeintrag löst seine Aktion aus.
        // Die obere Bildschirmkante taugt nicht — dort liegt die Statusleiste in einem
        // eigenen Systemfenster über der App, der Tipp erreicht das Menü gar nicht.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.62)).tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5), "Kontextmenü blieb offen")
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.tap()
        XCTAssertTrue(detailIsOpen(app), "Detailansicht wurde nach dem Kontextmenü nicht geöffnet")
    }
}
