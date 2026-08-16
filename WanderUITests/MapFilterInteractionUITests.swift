import XCTest

final class MapFilterInteractionUITests: XCTestCase {
    private func launchFriendsMore(resetSeconds: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapMoreFiltersOpen"
        ]
        if let resetSeconds {
            app.launchArguments += ["-WanderMapMoreFiltersAwayResetSeconds", resetSeconds]
        }
        app.launch()
        return app
    }

    func testSourceTapDismissesAndResetsMoreFiltersInOneTap() {
        let app = launchFriendsMore()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectDemoPerson(in: app, panel: panel)

        let you = app.buttons["map.filter.you"]
        XCTAssertTrue(you.isHittable)
        you.tap()

        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue((you.value as? String)?.contains("Selected") == true)
        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("No additional filters") == true
        )
    }

    func testSearchNearbyAndBottomNavigationDismissWithoutResettingMoreFilters() {
        let app = launchFriendsMore()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        selectDemoPerson(in: app, panel: panel)

        let search = app.textFields["map.searchField"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        app.buttons["map.searchCancel"].tap()
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let nearby = app.buttons["Center on my location"]
        XCTAssertTrue(nearby.isHittable)
        nearby.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let add = app.buttons["map.headerAdd"]
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        let closeAdd = app.buttons["Close add place"]
        XCTAssertTrue(closeAdd.waitForExistence(timeout: 3))
        closeAdd.tap()
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let feed = app.buttons["Feed"]
        XCTAssertTrue(feed.isHittable)
        feed.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue(feed.isSelected)

        app.buttons["Map"].tap()
        assertOneSelectedFilter(in: app)
    }

    func testThreeMinutesOnAnotherTabResetsMoreFilters() {
        let app = launchFriendsMore(resetSeconds: "0.2")
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        selectDemoPerson(in: app, panel: panel)

        app.buttons["Feed"].tap()
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["Map"].tap()

        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("No additional filters") == true
        )
    }

    private func selectDemoPerson(in app: XCUIApplication, panel: XCUIElement) {
        let demo = app.buttons["map.more.person.user_demo"]
        for _ in 0..<5 where !demo.isHittable {
            panel.swipeUp()
        }
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertEqual(demo.value as? String, "Selected")
    }

    private func assertOneSelectedFilter(in app: XCUIApplication) {
        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("1 selected filter") == true
        )
    }
}
