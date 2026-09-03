import XCTest

@MainActor
final class YourMapPrototypeUITests: XCTestCase {
    func testPinSelectionAndSavedLensDeletion() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab", "profile",
        ]
        app.launch()

        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()

        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let pin = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin.")
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 6))
        pin.tap()

        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 6))
        capture("REC-338 selected personal map pin")

        app.buttons["yourMap.prototype.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["This year"].tap()
        app.buttons["yourMap.prototype.saveLens"].tap()

        let savedLens = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
        ).firstMatch
        XCTAssertTrue(savedLens.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(savedLens.frame.width, app.frame.width * 0.9)

        savedLens.swipeLeft()
        XCTAssertLessThan(savedLens.frame.maxX, app.frame.maxX - 40)
        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.deleteLens.")
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        XCTAssertTrue(deleteButton.isHittable)
        capture("REC-338 saved lens delete reveal")

        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["No saved lenses yet"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
            ).count,
            0
        )
    }

    func testSnapshotCreatesListAndOpensEditablePlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderResetWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        let snapshot = app.buttons["yourMap.snapshot"]
        XCTAssertTrue(snapshot.waitForExistence(timeout: 10))
        let pin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin.")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        capture("REC-413 Explore snapshot control")
        snapshot.tap()
        let toast = app.buttons["yourMap.viewSnapshotList"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        capture("REC-413 Snapshot saved toast")
        toast.tap()
        XCTAssertTrue(app.staticTexts["edit list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields.firstMatch.value as? String != nil)
        let title = app.textFields.firstMatch
        title.tap()
        let existing = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Snapshot test\n")
        app.swipeUp()
        XCTAssertTrue(app.buttons["listEditor.addPlaces"].waitForExistence(timeout: 5))
        capture("REC-413 Snapshot list editor")
        app.buttons["listEditor.addPlaces"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
