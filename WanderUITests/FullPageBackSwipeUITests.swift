import XCTest

@MainActor
final class FullPageBackSwipeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testInCommonCancelsThenReturnsOnlyToMemberProfile() {
        let app = launch(["-WanderOpenProfile", "user_maya"])
        let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "in common")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.staticTexts["In Common"].waitForExistence(timeout: 5))
        capture("In Common full page")
        drag(app, from: 0.01, to: 0.12, duration: 1)
        XCTAssertTrue(app.staticTexts["In Common"].exists)
        drag(app)
        XCTAssertTrue(app.staticTexts["In Common"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back"].firstMatch.exists, "The member must remain open")
        entry.tap()
        XCTAssertTrue(app.staticTexts["In Common"].waitForExistence(timeout: 5))
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        capture("Member restored after In Common")
    }

    func testMapFullPageCancelsAndReturnsToSameCompactCard() {
        let app = launch(["-WanderMapPlace", "Woodcat Coffee"])
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let back = app.buttons["place-profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        capture("Map place full page")
        app.buttons["place-profile.add-to-list"].tap()
        let cancel = app.buttons["map-list-picker.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        drag(app)
        XCTAssertTrue(cancel.exists, "Swiping a sheet must not dismiss the full page below it")
        cancel.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(back.exists, "Vertical scrolling must not go back")
        drag(app, from: 0.01, to: 0.12, duration: 1)
        XCTAssertTrue(back.exists)
        drag(app, from: 0.5, to: 0.8)
        XCTAssertTrue(back.exists, "An ordinary horizontal drag must not go back")
        drag(app)
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Woodcat Coffee"))
        capture("Map compact card restored")
        card.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"] + arguments
        app.launch()
        return app
    }

    private func drag(_ app: XCUIApplication, from: CGFloat = 0.01, to: CGFloat = 0.85, duration: TimeInterval = 0.3) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: duration)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
