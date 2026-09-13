import XCTest

/// Die Einstellungen sind in Kategorien gegliedert. Der Test öffnet jede Kategorie einmal,
/// prüft ein Element darin und legt Screenshots ab.
final class SettingsCategoriesUITests: XCTestCase {

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
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func open(_ app: XCUIApplication, category: String, expect element: XCUIElement) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", category)).firstMatch
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Kategorie „\(category)“ fehlt")
        row.tap()
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Inhalt von „\(category)“ fehlt")
        capture(app, category)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testAlleKategorienOeffnen() throws {
        let app = launchInDemoMode()
        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Einstellungen"].tap()
        capture(app, "0 Einstellungen oben")
        app.swipeUp()
        capture(app, "0 Einstellungen unten")
        app.swipeDown()

        open(app, category: "Archiv verwalten", expect: app.buttons["Tags verwalten"])
        open(app, category: "Offline & Laden", expect: app.buttons["Alle Dokumente herunterladen"])
        open(app, category: "KI & Automatik", expect: app.switches["KI-Funktionen (Apple Intelligence)"])
        open(app, category: "Darstellung", expect: app.staticTexts["Farbthema"])
        open(app, category: "Mitteilungen & Widget", expect: app.switches["Widget aktiv"])
        open(app, category: "Datenschutz & Spotlight", expect: app.switches["Volltext durchsuchbar"])
        open(app, category: "Hilfe & Info", expect: app.buttons["Changelog"])

        // Unterstützungsseite: kein „kostenlos" und kein PayPal mehr (Kauf-App).
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hilfe & Info")).firstMatch.tap()
        app.buttons["Unterstützung"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Danke für deine Unterstützung"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'kostenlos'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'PayPal'")).firstMatch.exists)
        capture(app, "Unterstützung")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let logout = app.buttons["Abmelden"].firstMatch
        for _ in 0..<4 where !logout.isHittable { app.swipeUp() }
        logout.tap()
        // Rückfrage statt sofortigem Abmelden.
        XCTAssertTrue(app.staticTexts["Abmelden?"].waitForExistence(timeout: 5), "Abmelden ohne Rückfrage")
        capture(app, "Abmelden-Rückfrage")
        // iOS 26 zeigt die Rückfrage als Popover ohne „Abbrechen"; ein Tipp daneben schließt sie.
        let cancel = app.buttons["Abbrechen"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            // Neben das Popover tippen; die Abdunklung fängt den Tipp ab.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        }
        capture(app, "nach Abbrechen")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hilfe & Info")).firstMatch
            .waitForExistence(timeout: 5), "Nach Abbrechen nicht mehr in den Einstellungen")
        XCTAssertFalse(app.staticTexts["Abmelden?"].exists, "Rückfrage ging nicht zu")
        XCTAssertFalse(app.buttons["Starten"].exists || app.buttons["Demo"].exists, "Abmelden wurde trotzdem ausgeführt")
    }
}
