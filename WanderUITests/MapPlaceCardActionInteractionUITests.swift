import XCTest

@MainActor
final class MapPlaceCardActionInteractionUITests: XCTestCase {
    func testActionButtonsCancelAfterDraggingAwayAndStillRespondToTaps() {
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

        let addButton = app.buttons["map.selectedPlaceAction"]
        let shareButton = app.buttons["map.selectedPlaceShare"]
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(shareButton.exists)

        dragAway(from: addButton, onto: card)
        XCTAssertFalse(app.buttons["Close"].waitForExistence(timeout: 1))
        XCTAssertTrue(card.exists)

        dragAway(from: shareButton, onto: card)
        XCTAssertFalse(app.otherElements["ActivityListView"].waitForExistence(timeout: 1))
        XCTAssertTrue(card.exists)
        capture("rec-293-place-action-drag-cancelled")

        addButton.tap()
        let saveClose = app.buttons["Close"]
        XCTAssertTrue(saveClose.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-profile.floating-action.checkIn"].exists)
        saveClose.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let cardIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: card
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cardIsHittable], timeout: 5), .completed)

        app.buttons["map.selectedPlaceShare"].tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertFalse(activityList.waitForExistence(timeout: 3))
    }

    private func dragAway(from button: XCUIElement, onto card: XCUIElement) {
        let start = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.72))
        start.press(forDuration: 0.6, thenDragTo: destination)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
