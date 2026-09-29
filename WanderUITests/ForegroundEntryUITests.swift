import XCTest

@MainActor
final class ForegroundEntryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOrdinaryReturnsFromEveryTabOpenFeed() {
        let app = launch()
        let tabs = app.tabBars.firstMatch
        for title in ["Map", "Lists", "Profile", "Feed"] {
            tabs.buttons[title].tap()
            XCTAssertTrue(tabs.buttons[title].isSelected)
            XCUIDevice.shared.press(.home)
            app.activate()
            assertSelected("Feed", in: app)
            XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        }
    }

    func testMapLinkWinsOnBackgroundEntryAndNextOrdinaryEntryOpensFeed() {
        let app = launch()
        app.tabBars.buttons["Lists"].tap()
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "recme://map")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        assertSelected("Map", in: app)
        XCTAssertTrue(app.textFields["map.searchField"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        assertSelected("Feed", in: app)
    }

    func testProfileLinkWinsButDoesNotProtectALaterOrdinaryEntry() {
        let app = launch()
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "recme://profiles/user_maya")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        let back = app.buttons["profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10))
        assertSelected("Feed", in: app)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].isHittable)
    }

    func testFeedbackDraftSurvivesBackgroundEntry() {
        let app = launch(extras: ["-WanderFeedbackUITest"])
        app.tabBars.buttons["Profile"].tap()
        assertSelected("Profile", in: app)
        let feedback = app.buttons["profile.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        feedback.tap()
        app.buttons["feedback.tab.text"].tap()
        let text = app.textViews["feedback.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Keep this draft")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, "Keep this draft")
    }

    private func launch(extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"
        ] + extras
        app.launch()
        let feed = app.tabBars.buttons["Feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 20))
        // Native tab accessibility can appear beneath the launch image.
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: feed
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        return app
    }

    private func assertSelected(_ title: String, in app: XCUIApplication) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: app.tabBars.buttons[title]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }
}
