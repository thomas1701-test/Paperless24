import XCTest

/// Anmeldeseite: standardmäßig https, http nur über den Schalter „Unverschlüsselt verbinden".
/// Erreicht über Einstellungen → Konten verwalten → Konto hinzufügen (gleiche Maske wie beim
/// ersten Login, funktioniert auch im Demo-Modus).
final class LoginSchemeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testHttpNurPerSchalter() throws {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Starten"]
        if start.waitForExistence(timeout: 10) { start.tap() }
        let demo = app.buttons["Demo"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            app.alerts.buttons["Starten"].tap()
        }

        XCTAssertTrue(app.tabBars.buttons["Einstellungen"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Einstellungen"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Konten verwalten")).firstMatch.tap()
        let add = app.buttons["Konto hinzufügen"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let toggle = app.switches["Unverschlüsselt verbinden (http)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Schalter fehlt")
        XCTAssertEqual(toggle.value as? String, "0", "http darf nicht vorbelegt sein")
        capture(app, "1 Standard https")

        // Eingefügte http-Adresse schaltet nicht still auf http.
        let field = app.textFields["Server"]
        field.tap()
        field.typeText("http://paperless.local:8000")
        XCTAssertEqual(toggle.value as? String, "0", "http:// in der Adresse hat den Schalter eingeschaltet")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "begann mit http://")).firstMatch
            .waitForExistence(timeout: 3), "Hinweis auf http:// fehlt")
        XCTAssertEqual(field.value as? String, "paperless.local:8000", "Schema wurde nicht abgetrennt")
        capture(app, "2 http eingefügt, Schalter aus")

        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "mitlesbar")).firstMatch
            .waitForExistence(timeout: 3), "Warnung bei http fehlt")
        capture(app, "3 Schalter an, Warnung")
    }
}
