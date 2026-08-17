import XCTest

@MainActor
final class MapFilterInteractionUITests: XCTestCase {
    func testSourceFiltersFitWithoutOverlapOnSmallPhones() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let filters = [
            app.buttons["map.filter.featured"],
            app.buttons["map.filter.friends"],
            app.buttons["map.filter.you"],
            app.buttons["map.filter.more"]
        ]
        let appFrame = app.windows.firstMatch.frame

        for filter in filters {
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
            XCTAssertTrue(filter.isHittable)
            XCTAssertGreaterThanOrEqual(filter.frame.minX, appFrame.minX)
            XCTAssertLessThanOrEqual(filter.frame.maxX, appFrame.maxX)
            XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        }

        for (leading, trailing) in zip(filters, filters.dropFirst()) {
            XCTAssertLessThanOrEqual(leading.frame.maxX, trailing.frame.minX)
        }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-278 Option B small-phone filter geometry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSelectedTicketClearsSearchDockWithoutRedundantResultMessage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace", "Woodcat Coffee"
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        let message = app.staticTexts["map.searchMessage"]
        let search = app.textFields["map.searchField"]
        let addButton = app.buttons["map.headerAdd"]
        let nearby = app.buttons["map.nearby"]

        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.contains("Woodcat Coffee"))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
        XCTAssertLessThanOrEqual(card.frame.maxY, search.frame.minY)
        XCTAssertGreaterThanOrEqual(addButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(addButton.frame.height, 44)
        XCTAssertTrue(addButton.isHittable)
        XCTAssertFalse(nearby.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-293 selected card with Nearby hidden"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLongPressShowsDroppedPinAsAStandardPlaceCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.45))
            .press(forDuration: 0.7)

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-289 dropped pin standard place card"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if card.label.contains("Dropped pin") {
            XCTAssertFalse(app.staticTexts["map.searchMessage"].exists)
            let coordinates = app.staticTexts["map.droppedPinCoordinates"]
            XCTAssertTrue(coordinates.waitForExistence(timeout: 2))
            coordinates.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Copy coordinates"].waitForExistence(timeout: 2))
        }
    }

    func testNearbyPermissionEducationAppearsBeforeTheSystemPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let nearby = app.buttons["map.nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 5))
        guard nearby.value as? String == "Location permission needed" else {
            throw XCTSkip("Simulator already has location permission")
        }

        nearby.tap()
        XCTAssertTrue(
            app.buttons["map.locationEducation.allow"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["map.locationEducation.cancel"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-289 Nearby location education"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        let cancelLocationEducation = app.buttons["map.locationEducation.cancel"]
        if cancelLocationEducation.waitForExistence(timeout: 1) {
            cancelLocationEducation.tap()
        }
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
