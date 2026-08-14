import XCTest

/// Captures the six approved App Store frames from deterministic, fictional
/// data. The attached PNGs are extracted and composited by
/// `scripts/capture-app-store-screenshots.sh`.
@MainActor
final class AppStoreScreenshotsUITests: XCTestCase {
    func test01MapShowsPlacesFromFriends() {
        let app = launch(arguments: [
            "-WanderMapCaptureMode", "friends",
        ])

        XCTAssertTrue(app.buttons["map.headerAdd"].waitForExistence(timeout: 6))
        settleForCapture()
        capture("recme-store-01-map-friends")
    }

    func test02FeedShowsWhereFriendsWent() {
        let app = launch(arguments: [
            "-WanderInitialTab", "discover",
        ])

        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 6))
        settleForCapture()
        capture("recme-store-02-feed-places")
    }

    func test03TrustedSearchShowsMultipleUsefulResults() {
        let app = launch(arguments: [
            "-WanderInitialTab", "discover",
        ])

        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 6))
        launcher.tap()

        let searchField = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        searchField.tap()
        searchField.typeText("coffee")
        searchField.typeText("\n")

        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No exact matches yet"].exists)
        settleForCapture()
        capture("recme-store-03-trusted-search")
    }

    func test04PlaceDetailShowsMemoryAndRatings() {
        let app = launch(arguments: [
            "-WanderMapPlace", "Hearthline Coffee",
            "-WanderMapSheetExpanded",
        ])

        XCTAssertTrue(app.staticTexts["Hearthline Coffee"].firstMatch.waitForExistence(timeout: 7))
        XCTAssertTrue(app.staticTexts["Ratings"].waitForExistence(timeout: 5))
        settleForCapture()
        capture("recme-store-04-place-detail")
    }

    func test05AddSheetUsesDeterministicNearbyPlaces() {
        let app = launch(arguments: [
            "-WanderMapCaptureMode", "friends",
            "-WanderOpenAdd",
        ])

        XCTAssertTrue(app.staticTexts["add a place"].waitForExistence(timeout: 6))
        XCTAssertTrue(
            app.buttons["Add Sparrow Bakery"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(app.staticTexts["No friends’ places yet."].exists)
        settleForCapture()
        capture("recme-store-05-add")
    }

    func test06ListsShowsPlansTogether() {
        let app = launch(arguments: [
            "-WanderInitialTab", "lists",
        ])

        XCTAssertTrue(app.buttons["lists.headerAdd"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Saturday plan"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Date night short list"].exists)
        settleForCapture()
        capture("recme-store-06-lists")
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
        ] + arguments
        app.launch()
        return app
    }

    private func settleForCapture() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
