import XCTest

/// Erzeugt die Bilder für den App-Store-Eintrag.
///
/// Läuft ausschließlich im Demo-Modus, es werden also nur die erfundenen Beispieldaten
/// aus `DemoDataService` abgelichtet — keine echten Dokumente, Namen oder Server.
///
/// Aufruf pro Gerät und Sprache, z. B.:
/// `xcodebuild test -scheme Paperless24 -only-testing:Paperless24UITests/StoreScreenshotTests
///  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -parallel-testing-enabled NO
///  -resultBundlePath out.xcresult`
/// Danach `xcrun xcresulttool export attachments --path out.xcresult --output-path bilder`.
///
/// Die Aufnahmen sind auf mehrere Testmethoden verteilt: jede startet die App neu und
/// beginnt damit oben in der Liste. Das ist verlässlicher, als einen langen Pfad durch
/// Sheets, Tastatur und Zurück-Gesten zu fädeln.
final class StoreScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Beschriftungen

    /// Die Oberfläche folgt der Simulator-Sprache. Für die Bedienung im Test brauchen wir
    /// beide Fassungen der Beschriftungen.
    private var isEnglish: Bool {
        (Locale.preferredLanguages.first ?? "de").hasPrefix("en")
    }

    private func label(_ de: String, _ en: String) -> String { isEnglish ? en : de }

    private var firstDocTitle: String {
        label("Stromabrechnung 2026", "Electricity statement 2026")
    }

    // MARK: - Start

    @MainActor
    private func launchInDemoMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let start = app.buttons[label("Starten", "Start")]
        if start.waitForExistence(timeout: 15) { start.tap() }

        let demo = app.buttons["Demo"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            let confirm = app.alerts.buttons[label("Starten", "Start")]
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        }

        XCTAssertTrue(app.staticTexts[firstDocTitle].waitForExistence(timeout: 30),
                      "Beispieldokumente erschienen nicht")
        ensureGridLayout(app)
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        // Kurz warten, damit Miniaturen und Animationen stehen.
        Thread.sleep(forTimeInterval: 1.2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Auf dem iPhone ist die Tab-Leiste unten, auf dem iPad eine Leiste oben. Beide
    /// Varianten führen dieselben Beschriftungen, nur in unterschiedlichen Containern.
    @MainActor
    private func selectTab(_ app: XCUIApplication, _ de: String, _ en: String) -> Bool {
        let title = label(de, en)
        let inTabBar = app.tabBars.buttons[title].firstMatch
        if inTabBar.waitForExistence(timeout: 5) { inTabBar.tap(); return true }
        let plain = app.buttons.matching(identifier: title).firstMatch
        if plain.waitForExistence(timeout: 5) { plain.tap(); return true }
        return false
    }

    /// Frühere Läufe können das Layout auf Liste gestellt haben — die Einstellung überlebt
    /// den Neustart der App. Für vergleichbare Bilder immer mit dem Raster beginnen.
    @MainActor
    private func ensureGridLayout(_ app: XCUIApplication) {
        let gridToggle = app.buttons["square.grid.2x2"]
        if gridToggle.waitForExistence(timeout: 3) { gridToggle.tap() }
    }

    /// Das `.searchable`-Feld taucht in der Barrierefreiheits-Hierarchie nicht auf. Es sitzt
    /// direkt unter der Werkzeugleiste — auf dem iPhone mittig, auf dem iPad in der linken
    /// Spalte. Darum mehrere Stellen probieren, bis die Tastatur erscheint.
    @MainActor
    private func focusSearchField(_ app: XCUIApplication) -> Bool {
        let candidates = [CGVector(dx: 0.5, dy: 0.143), CGVector(dx: 0.27, dy: 0.118),
                          CGVector(dx: 0.27, dy: 0.135), CGVector(dx: 0.5, dy: 0.12)]
        for offset in candidates {
            app.coordinate(withNormalizedOffset: offset).tap()
            if app.keyboards.element.waitForExistence(timeout: 4) { return true }
        }
        return false
    }

    @MainActor
    private func tapBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    // MARK: - 1: Übersicht und Dokument

    @MainActor
    func testA_uebersichtUndDokument() throws {
        let app = launchInDemoMode()
        let firstDoc = app.staticTexts[firstDocTitle]

        capture(app, "01-uebersicht")

        firstDoc.tap()
        XCTAssertTrue(app.buttons[label("Notizen", "Notes")].waitForExistence(timeout: 15),
                      "Detailansicht öffnete nicht")
        capture(app, "02-dokument")

        if app.buttons["Text"].waitForExistence(timeout: 5) {
            app.buttons["Text"].tap()
            capture(app, "03-text")
        }
        if app.buttons["Info"].waitForExistence(timeout: 5) {
            app.buttons["Info"].tap()
            capture(app, "04-info")
        }
        let notes = app.buttons[label("Notizen", "Notes")]
        if notes.waitForExistence(timeout: 5) {
            notes.tap()
            capture(app, "05-notizen")
        }
    }

    // MARK: - 2: Volltextsuche

    @MainActor
    func testB_suche() throws {
        let app = launchInDemoMode()

        XCTAssertTrue(focusSearchField(app), "Suchfeld bekam keinen Fokus")

        app.typeText(label("Versicherung", "insurance"))
        // Die Suche ist um 400 ms entprellt; danach die Tastatur schließen, damit die
        // Trefferliste das Bild füllt.
        Thread.sleep(forTimeInterval: 1.5)
        app.typeText("\n")
        capture(app, "06-suche")
    }

    // MARK: - 3: Listendarstellung

    @MainActor
    func testC_liste() throws {
        let app = launchInDemoMode()

        // Der Umschalter trägt das Symbol des jeweils anderen Layouts. Steht die App aus
        // einem früheren Lauf schon auf Liste, ist nur „square.grid.2x2" da.
        let toList = app.buttons["list.bullet"]
        XCTAssertTrue(toList.waitForExistence(timeout: 10), "Layout-Umschalter fehlt")
        toList.tap()
        capture(app, "07-liste")

        // Für die folgenden Läufe wieder auf Raster stellen.
        let gridToggle = app.buttons["square.grid.2x2"]
        if gridToggle.waitForExistence(timeout: 5) { gridToggle.tap() }
    }

    // MARK: - 4: Posteingang, Einstellungen, Darstellung

    @MainActor
    func testD_posteingangUndEinstellungen() throws {
        let app = launchInDemoMode()

        XCTAssertTrue(selectTab(app, "Posteingang", "Inbox"), "Posteingang-Tab fehlt")
        capture(app, "08-posteingang")

        XCTAssertTrue(selectTab(app, "Einstellungen", "Settings"), "Einstellungen-Tab fehlt")
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "09-einstellungen")

        let appearance = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@",
                                  label("Farbthema", "theme"))).firstMatch
        for _ in 0..<4 where !appearance.exists { app.swipeUp() }
        XCTAssertTrue(appearance.waitForExistence(timeout: 8),
                      "Eintrag „Farbthema & Darstellung“ nicht gefunden")
        appearance.tap()
        capture(app, "10-darstellung")
        tapBack(app)
    }

    // MARK: - 5: Verwaltung (Tags)

    @MainActor
    func testE_tags() throws {
        let app = launchInDemoMode()

        XCTAssertTrue(selectTab(app, "Einstellungen", "Settings"), "Einstellungen-Tab fehlt")

        // Tags liegen in der Kategorie „Archiv verwalten".
        let library = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", label("Archiv", "Manage"))).firstMatch
        for _ in 0..<4 where !library.exists { app.swipeUp() }
        if library.waitForExistence(timeout: 8) { library.tap() }

        let tagsEntry = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Tags")).firstMatch
        if tagsEntry.waitForExistence(timeout: 8) {
            tagsEntry.tap()
            capture(app, "11-tags")
            tapBack(app)
        }
    }
}
