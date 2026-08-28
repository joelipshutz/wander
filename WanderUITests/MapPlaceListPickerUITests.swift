import XCTest

@MainActor
final class MapPlaceListPickerUITests: XCTestCase {
    func testCollapsedAndFullPlaceCardsOpenTheSameListPicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapPlace", "Hearthline Coffee",
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let collapsedListButton = app.buttons["map.selectedPlaceAddToList"]
        XCTAssertTrue(collapsedListButton.exists)
        capture("REC-342 collapsed place card list icon")
        collapsedListButton.tap()

        XCTAssertTrue(app.otherElements["map-list-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add to lists"].exists)
        XCTAssertTrue(app.buttons["map-list-picker.new-list"].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Only yours")).count,
            0
        )
        XCTAssertTrue(app.buttons["map-list-picker.apply"].label.contains("Done"))
        let existingRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "map-list-picker.list.", "already in list")
        ).firstMatch
        XCTAssertTrue(existingRow.exists)
        XCTAssertFalse(existingRow.isEnabled)
        capture("REC-342 collapsed add-to-list picker")

        let availableRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "map-list-picker.list.", "not selected")
        ).firstMatch
        if availableRow.exists {
            availableRow.tap()
            XCTAssertTrue(availableRow.label.contains("selected"))
        }
        app.buttons["map-list-picker.cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.tap()
        let fullListButton = app.buttons["place-profile.add-to-list"]
        let shareButton = app.buttons["place-profile.share"]
        XCTAssertTrue(fullListButton.waitForExistence(timeout: 8))
        XCTAssertTrue(shareButton.exists)
        XCTAssertLessThan(fullListButton.frame.midX, shareButton.frame.midX)
        capture("REC-342 full place profile list position")

        fullListButton.tap()
        XCTAssertTrue(app.otherElements["map-list-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add to lists"].exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
