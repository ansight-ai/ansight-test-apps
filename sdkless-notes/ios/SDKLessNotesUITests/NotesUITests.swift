import XCTest

final class NotesUITests: XCTestCase {
    func testCreateEditPersistAndDelete() {
        let app = XCUIApplication()
        app.launch()
        let title = "Smoke note " + UUID().uuidString.prefix(8)
        app.buttons["new-note"].tap()
        let titleField = app.textFields["note-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(String(title))
        let body = app.textViews["note-body"]
        body.tap()
        body.typeText("Saved without an SDK.")
        app.buttons["save-note"].tap()
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[String(title)].waitForExistence(timeout: 5))
        app.staticTexts[String(title)].tap()
        XCTAssertEqual(app.textViews["note-body"].value as? String, "Saved without an SDK.")
        app.textViews["note-body"].tap()
        app.textViews["note-body"].typeText("Edited. ")
        let editedBody = app.textViews["note-body"].value as? String
        XCTAssertTrue(editedBody?.contains("Edited. ") == true)
        app.buttons["save-note"].tap()
        app.staticTexts[String(title)].tap()
        XCTAssertEqual(app.textViews["note-body"].value as? String, editedBody)
        app.buttons["delete-note"].tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts[String(title)].exists)
    }

    func testSeedAndScroll() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["add-samples"].tap()
        XCTAssertTrue(app.staticTexts["Sample note 50"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["animation-toggle"].exists)
        app.tables["notes-list"].swipeUp()
        app.tables["notes-list"].swipeDown()
    }
}
