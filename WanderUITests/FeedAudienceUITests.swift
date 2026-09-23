import XCTest

@MainActor
final class FeedAudienceUITests: XCTestCase {
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
        choose("Only Me", in: app, menu: menu)
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
        choose("Only Friends", in: app, menu: menu)
        XCTAssertTrue(app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["feed.activity.fixture-feed-own.actor"].exists)
        XCTAssertFalse(app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"].exists)
        capture("feed-audience-only-friends")

        app.tabBars.buttons["Profile"].tap()
        app.tabBars.buttons["Feed"].tap()
        XCTAssertEqual(menu.value as? String, "Everyone")
        menu.tap()
        choose("Only Me", in: app, menu: menu)
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

    private func choose(_ title: String, in app: XCUIApplication, menu: XCUIElement) {
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.press(forDuration: 0.1)
        XCTAssertTrue(option.waitForNonExistence(timeout: 5))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: menu)
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
