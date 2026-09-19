import XCTest

final class FeedActivityGroupingUITests: XCTestCase {
    @MainActor
    func testAuthenticatedRootSurvivesRepeatedColdLaunches() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"
        ]
        for _ in 0..<3 {
            app.launch()
            XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
            let exited = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in app.state != .runningForeground },
                object: nil
            )
            exited.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [exited], timeout: 3), .completed)
            app.terminate()
        }
    }

    @MainActor
    func testCombinedActivityExpandsInOrderCollapsesAndOpensOriginalPost() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedGroupingUITest", "-WanderInitialTab", "discover"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        let disclosure = app.buttons["feed.activity.fixture-feed-group-wanna.disclosure"]
        for _ in 0..<5 where !disclosure.isHittable { app.swipeUp() }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        capture("feed-group-collapsed")

        let wanna = app.buttons["feed.activity.fixture-feed-group-wanna.sequenceEvent"]
        let visit = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.sequenceEvent"]
        let list = app.buttons["feed.activity.fixture-feed-group-list.sequenceEvent"]
        XCTAssertFalse(wanna.exists)
        disclosure.tap()
        XCTAssertTrue(wanna.waitForExistence(timeout: 3))
        XCTAssertEqual(disclosure.value as? String, "Expanded, 3 activities")
        XCTAssertLessThan(wanna.frame.minY, visit.frame.minY)
        XCTAssertLessThan(visit.frame.minY, list.frame.minY)
        for _ in 0..<3 where !list.isHittable { app.swipeUp() }
        capture("feed-group-expanded")

        for _ in 0..<3 where !disclosure.isHittable { app.swipeDown() }
        disclosure.tap()
        XCTAssertFalse(wanna.exists)
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        disclosure.tap()
        for _ in 0..<3 where !wanna.isHittable { app.swipeUp() }
        wanna.tap()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 5))
        capture("feed-group-original-post")
    }

    @MainActor
    func testNotificationOpensPostWithArrowComposerAndBackReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "map"
        ]
        app.launch()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["comments"].exists)
        XCTAssertFalse(app.staticTexts["Start the conversation"].exists)
        XCTAssertFalse(app.buttons["Post"].exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        capture("REC-543-post-empty")
        let composer = app.descendants(matching: .any)["activity.comment.input"].firstMatch
        composer.tap()
        composer.typeText("Meet you here next time!")
        XCTAssertTrue(send.isEnabled)
        capture("REC-543-post-composer")
        send.tap()
        XCTAssertTrue(app.staticTexts["Meet you here next time!"].waitForExistence(timeout: 5))
        capture("REC-543-post-comment")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)
        capture("REC-543-back-to-feed")
    }

    @MainActor
    func testNotificationPostEdgeSwipeReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "profile"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 20))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.comment.send"].exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
