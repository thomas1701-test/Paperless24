import XCTest

/// Meldung vom Gerät: Nach einem Wechsel von „Dokumente" in einen anderen Tab und zurück
/// ist das Suchfeld weg und kommt erst nach einem Neustart der App wieder.
final class SearchFieldUITests: XCTestCase {

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
        XCTAssertTrue(app.staticTexts["Stromabrechnung 2026"].firstMatch.waitForExistence(timeout: 15),
                      "Demo-Dokumente erschienen nicht")
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func assertSearchFieldVisible(_ app: XCUIApplication, _ step: String) {
        let field = app.searchFields.firstMatch
        let ok = field.waitForExistence(timeout: 5) && field.isHittable
        capture(app, step)
        XCTAssertTrue(ok, "Suchfeld fehlt: \(step)")
    }

    @MainActor
    private func switchTab(_ app: XCUIApplication, _ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
    }

    @MainActor
    func testSuchfeldNachTabwechsel() throws {
        let app = launchInDemoMode()
        assertSearchFieldVisible(app, "1 Start")

        switchTab(app, "Posteingang")
        sleep(1)
        switchTab(app, "Dokumente")
        assertSearchFieldVisible(app, "2 zurück aus Posteingang")

        switchTab(app, "Einstellungen")
        sleep(1)
        switchTab(app, "Dokumente")
        assertSearchFieldVisible(app, "3 zurück aus Einstellungen")
    }

    @MainActor
    func testSuchfeldNachScrollenUndTabwechsel() throws {
        let app = launchInDemoMode()
        app.swipeUp()
        app.swipeUp()
        switchTab(app, "Posteingang")
        sleep(1)
        switchTab(app, "Dokumente")
        app.swipeDown()
        app.swipeDown()
        assertSearchFieldVisible(app, "nach Scrollen, Tabwechsel und zurückscrollen")
    }

    @MainActor
    func testSuchfeldNachSucheUndTabwechsel() throws {
        let app = launchInDemoMode()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Strom")
        sleep(1)
        switchTab(app, "Posteingang")
        sleep(1)
        switchTab(app, "Dokumente")
        assertSearchFieldVisible(app, "nach aktiver Suche und Tabwechsel")
    }

    @MainActor
    func testSuchfeldNachDetailansichtUndTabwechsel() throws {
        let app = launchInDemoMode()
        app.staticTexts["Stromabrechnung 2026"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Notizen"].waitForExistence(timeout: 8))
        switchTab(app, "Posteingang")
        sleep(1)
        switchTab(app, "Dokumente")
        sleep(1)
        capture(app, "Detail nach Tabwechsel")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        assertSearchFieldVisible(app, "zurück aus Detail nach Tabwechsel")
    }

    @MainActor
    func testSuchfeldNachScrollenOhneZurueckscrollen() throws {
        let app = launchInDemoMode()
        app.swipeUp()
        sleep(1)
        capture(app, "a gescrollt")
        switchTab(app, "Posteingang")
        sleep(1)
        switchTab(app, "Dokumente")
        sleep(1)
        capture(app, "b zurück, noch gescrollt")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        assertSearchFieldVisible(app, "c hochgescrollt")
    }

    @MainActor
    func testSuchfeldNachScanTab() throws {
        let app = launchInDemoMode()
        switchTab(app, "Scan")
        sleep(2)
        capture(app, "Scan offen")
        // Sheet schließen: nach unten wischen oder Abbrechen
        let cancel = app.buttons["Abbrechen"].firstMatch
        if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(2)
        assertSearchFieldVisible(app, "nach Scan-Sheet")
    }

    @MainActor
    func testSuchfeldPosteingangMitDetail() throws {
        let app = launchInDemoMode()
        switchTab(app, "Posteingang")
        sleep(1)
        capture(app, "Posteingang")
        switchTab(app, "Einstellungen")
        sleep(1)
        switchTab(app, "Dokumente")
        assertSearchFieldVisible(app, "über Posteingang und Einstellungen zurück")
    }
}

/// Sortier-Menü in „Dokumente": Auswahl muss die Reihenfolge sichtbar ändern.
final class SortMenuUITests: XCTestCase {
    @MainActor
    func testSortierungAendertReihenfolge() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Starten"]
        if start.waitForExistence(timeout: 10) { start.tap() }
        let demo = app.buttons["Demo"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            app.alerts.buttons["Starten"].tap()
        }
        XCTAssertTrue(app.staticTexts["Stromabrechnung 2026"].firstMatch.waitForExistence(timeout: 15))

        let sortButton = app.buttons["Sortieren"].firstMatch
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5), "Sortier-Knopf fehlt")
        sortButton.tap()
        let az = app.buttons["A–Z"].firstMatch
        XCTAssertTrue(az.waitForExistence(timeout: 5), "Sortier-Menü öffnete nicht")
        let shot1 = XCTAttachment(screenshot: app.screenshot()); shot1.name = "Menü offen"; shot1.lifetime = .keepAlways; add(shot1)
        az.tap()
        sleep(2)
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.name = "nach A–Z"; shot2.lifetime = .keepAlways; add(shot2)

        // Demo-Titel alphabetisch: „Einkommensteuerbescheid …" steht vor „Scan 2026-09-12".
        let einkommen = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Einkommensteuer'")).firstMatch
        let scan = app.staticTexts["Scan 2026-09-12"].firstMatch
        XCTAssertTrue(einkommen.waitForExistence(timeout: 5))
        if scan.exists {
            XCTAssertLessThan(einkommen.frame.minY, scan.frame.minY, "A–Z hat die Reihenfolge nicht geändert")
        }

        // Zurück auf Datum (Neu), damit andere Tests die gewohnte Reihenfolge sehen.
        sortButton.tap()
        app.buttons["Datum (Neu)"].firstMatch.tap()
    }
}
