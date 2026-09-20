import XCTest

@MainActor
final class ProfileAlignmentUITests: XCTestCase {
    func testMemberProfileStaysWithinScreenWhileScrolling() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderOpenProfile", "user_maya"
        ]
        app.launch()
        let back = app.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        let activity = app.otherElements.matching(identifier: "profile.walkthrough.activitySection").firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        let screen = app.frame
        assertFits(activity, in: screen)
        let initialFrame = activity.frame
        capture("Profile initial alignment")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.40)))
        assertFits(activity, in: screen)
        XCTAssertEqual(activity.frame.minX, initialFrame.minX, accuracy: 1)
        XCTAssertLessThan(activity.frame.minY, initialFrame.minY, "Vertical scrolling must still work")
        capture("Profile after diagonal scroll")
        app.swipeDown()
        assertFits(activity, in: screen)
        XCTAssertEqual(activity.frame.minX, initialFrame.minX, accuracy: 1)
        capture("Profile after reverse scroll")
    }

    func testFeedPlaceAndPersonProfilesCancelSwipeAndReturnToFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        for (suffix, backID) in [("place", "place-profile.back"), ("actor", "Back")] {
            let entry = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.\(suffix)"]
            for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.tap()
            let back = app.buttons[backID].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            capture("REC559 \(suffix) opened")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)), withVelocity: .slow,
                thenHoldForDuration: 0.2)
            XCTAssertTrue(back.isHittable, "A short cancelled swipe must retain the profile")
            capture("REC559 \(suffix) cancelled swipe")
            start.press(forDuration: 0.05, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)), withVelocity: .slow,
                thenHoldForDuration: 0)
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: entry)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
            entry.tap()
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            let returnedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: entry)
            XCTAssertEqual(XCTWaiter.wait(for: [returnedAgain], timeout: 5), .completed)
            capture("REC559 \(suffix) back restored feed")
        }
    }

    func testMapProfileSwipeAndBackRestoreTheSelectedCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderMapCardLocationFixture", "-WanderMapPlace", "Hearthline Coffee"
        ]
        app.launch()
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let back = app.buttons["place-profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        capture("REC559 Map profile opened")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo:
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)), withVelocity: .slow,
            thenHoldForDuration: 0.2)
        XCTAssertTrue(back.isHittable)
        capture("REC559 Map cancelled swipe")
        start.press(forDuration: 0.05, thenDragTo:
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)), withVelocity: .slow,
            thenHoldForDuration: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        card.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let returnedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [returnedAgain], timeout: 5), .completed)
        capture("REC559 Map back restored card")
    }

    private func assertFits(_ element: XCUIElement, in screen: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
