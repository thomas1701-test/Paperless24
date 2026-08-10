import XCTest

/// Führt die Darstellungs-Einstellungen einmal durch: Themenwechsel, OLED-Schwarz und
/// Lesemodus. Die Screenshots hängen am Testergebnis und belegen, dass das Thema wirklich
/// bis in die Dokumentübersicht durchschlägt — genau das ging beim alten `AccentColor`-Asset
/// nicht, weil `Color.accentColor` der Umgebung nicht folgt.
final class AppearanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchInDemoMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons["Starten"]
        if start.waitForExistence(timeout: 10) { start.tap() }

        let demo = app.buttons["Demo"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            let confirm = app.alerts.buttons["Starten"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Demo-Dialog erschien nicht")
            confirm.tap()
        }
        return app
    }

    @MainActor
    private func openAppearance(_ app: XCUIApplication) {
        app.buttons["Einstellungen"].firstMatch.tap()
        let entry = app.buttons["Farbthema & Darstellung"]
        // Der Eintrag liegt unterhalb des Dashboards und ist beim Öffnen nicht sichtbar.
        for _ in 0..<4 where !entry.exists { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Eintrag „Farbthema & Darstellung“ fehlt")
        entry.tap()
        XCTAssertTrue(app.staticTexts["Farbthema"].waitForExistence(timeout: 5),
                      "Darstellungs-Ansicht öffnete nicht")
    }

    /// SwiftUI kippt einen `Toggle` in einer `Form` nur, wenn der Schalter selbst getroffen
    /// wird. `XCUIElement.tap()` auf die Zeile zielt aber auf deren Mitte und landet damit
    /// auf dem Label — der Wert bleibt unverändert. Also den inneren Schalter antippen.
    @MainActor
    private func flip(_ row: XCUIElement) {
        row.switches.firstMatch.tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testThemenwechselWirktBisInDieUebersicht() throws {
        let app = launchInDemoMode()
        openAppearance(app)
        capture(app, "01-darstellung-standard")

        for theme in ["forest", "sunset", "contrast"] {
            let swatch = app.descendants(matching: .any).matching(identifier: "theme-\(theme)").firstMatch
            XCTAssertTrue(swatch.waitForExistence(timeout: 5), "Thema \(theme) nicht gefunden")
            swatch.tap()
            capture(app, "02-thema-\(theme)")
        }

        // Zurück in die Übersicht: dort müssen Chips und Karten die neue Farbe tragen.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Dokumente"].tap()
        XCTAssertTrue(app.staticTexts["Stromabrechnung 2026"].firstMatch.waitForExistence(timeout: 15),
                      "Übersicht zeigte das Demo-Dokument nicht")
        capture(app, "03-uebersicht-mit-thema")
    }

    @MainActor
    func testSchwarzerHintergrundUndLesemodusLassenSichSchalten() throws {
        let app = launchInDemoMode()
        openAppearance(app)

        let amoled = app.switches["Schwarzer Hintergrund"]
        XCTAssertTrue(amoled.waitForExistence(timeout: 5), "OLED-Schalter fehlt")
        // Der Wert überlebt den Neustart der App und wandert über iCloud mit — deshalb wird
        // gegen den Wert vor dem Tipp verglichen und nicht gegen „an".
        let amoledBefore = String(describing: amoled.value)
        flip(amoled)
        let amoledChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                String(describing: (element as? XCUIElement)?.value) != amoledBefore
            },
            object: amoled
        )
        XCTAssertEqual(XCTWaiter().wait(for: [amoledChanged], timeout: 5), .completed,
                       "OLED-Schalter ließ sich nicht umlegen")

        let reading = app.switches["Lesemodus für den Text-Reiter"]
        // Der Schalter liegt unterhalb der Farbthemen und ist erst nach dem Scrollen da.
        for _ in 0..<4 where !reading.exists { app.swipeUp() }
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "Lesemodus-Schalter fehlt")
        // Auch der Lesemodus überlebt den Neustart. Er kann also schon an sein — dann würde
        // ein Tipp ihn abschalten. Umschalten, bis der Schriftgrößen-Regler da ist; der
        // erscheint nur bei aktivem Lesemodus.
        let fontSize = app.staticTexts["Schriftgröße"]
        for _ in 0..<2 where !fontSize.exists {
            flip(reading)
            _ = fontSize.waitForExistence(timeout: 3)
        }

        for _ in 0..<3 where !fontSize.exists { app.swipeUp() }
        XCTAssertTrue(fontSize.waitForExistence(timeout: 5),
                      "Schriftgrößen-Regler erschien nicht")
        capture(app, "04-oled-und-lesemodus")
    }
}
