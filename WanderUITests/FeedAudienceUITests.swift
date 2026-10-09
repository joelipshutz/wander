import XCTest

@MainActor
final class FeedAudienceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMenuFiltersAndResetsOnTabEntryAndColdLaunch() {
        let app = launch()
        let menu = app.descendants(matching: .any)["feed.audience"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["feed.activity.fixture-feed-own.actor"].waitForExistence(timeout: 20))
        XCTAssertEqual(menu.value as? String, "Everyone")
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        capture("feed-audience-everyone")
        menu.tap()
        XCTAssertTrue(app.buttons["Only Me"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Only Friends"].exists)
        capture("feed-audience-menu")
        choose("Only Me", in: app)
        XCTAssertTrue(app.buttons["feed.activity.fixture-feed-own.actor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"].exists)
        capture("feed-audience-only-me")

        let ownActor = app.buttons["feed.activity.fixture-feed-own.actor"]
        for _ in 0..<4 where !ownActor.isHittable { app.swipeUp() }
        ownActor.tap()
        let back = app.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.value as? String, "Only Me")

        app.buttons["feed.searchLauncher"].tap()
        let close = app.buttons["discover.searchBack"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertEqual(menu.value as? String, "Only Me")
        for _ in 0..<4 where !menu.isHittable { app.swipeDown() }
        menu.tap()
        choose("Only Friends", in: app)
        XCTAssertTrue(app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["feed.activity.fixture-feed-own.actor"].exists)
        XCTAssertFalse(app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"].exists)
        capture("feed-audience-only-friends")

        app.tabBars.buttons["Profile"].tap()
        app.tabBars.buttons["Feed"].tap()
        XCTAssertEqual(menu.value as? String, "Everyone")
        menu.tap()
        choose("Only Me", in: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        XCTAssertEqual(menu.value as? String, "Everyone")
    }

    func testLargeTextKeepsMenuVisibleAndHittable() {
        let app = launch(largeText: true)
        let menu = app.descendants(matching: .any)["feed.audience"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        for _ in 0..<4 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        menu.tap()
        XCTAssertTrue(app.buttons["Only Friends"].waitForExistence(timeout: 3))
        capture("feed-audience-large-text-menu")
    }

    private func choose(_ title: String, in app: XCUIApplication) {
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        var previousFrame = CGRect.null
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let row = app.buttons[title]
            guard row.exists, row.isHittable else { return false }
            let frame = row.frame
            defer { previousFrame = frame }
            return !frame.isEmpty && frame == previousFrame
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(option.isHittable)
        // Wait for the native menu's presentation frame to settle before
        // resolving its touch point. It becomes hittable during the animation.
        // Send a normal touch to the visible row center instead of relying
        // on the native menu's synthesized accessibility activation point.
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(option.waitForNonExistence(timeout: 5))
        // Opening the native menu replaces its accessibility snapshot. Resolve
        // the current control on every observation, including its updated value.
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.descendants(matching: .any)["feed.audience"].firstMatch.value as? String == title
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func launch(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedAudienceUITest", "-WanderInitialTab", "discover"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
