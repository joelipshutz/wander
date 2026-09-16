import XCTest

final class FeedActivityGroupingUITests: XCTestCase {
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
        XCTAssertTrue(app.navigationBars["comments"].waitForExistence(timeout: 5))
        capture("feed-group-original-post")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
