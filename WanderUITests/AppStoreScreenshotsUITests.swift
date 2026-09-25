import XCTest

/// Captures dark-mode App Store candidates from deterministic, fictional
/// data. The attached PNGs are extracted and composited by
/// `scripts/capture-app-store-screenshots.sh`.
@MainActor
final class AppStoreScreenshotsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let previous = XCUIDevice.shared.appearance
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = previous }
        XCUIDevice.shared.appearance = .dark
    }

    func test01MapShowsPlacesFromFriends() {
        let app = launch(arguments: [
            "-WanderInitialTab", "map",
            "-WanderMapCaptureMode", "friends",
            "-WanderStorefrontRichMap",
            "-WanderMapPlace", "Marigold Table",
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
        XCTAssertTrue(app.staticTexts["Alex Rivera"].waitForExistence(timeout: 10))
        capture("recme-store-02-feed-places")
        let activityHeading = app.staticTexts["Activity"].firstMatch
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let distance = max(0, activityHeading.frame.minY - 126)
        start.press(forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)
        settleForCapture()
        XCTAssertGreaterThan(activityHeading.frame.minY, 65,
                             "Keep the activity heading below the status bar.")
        capture("recme-store-07-feed-moments")
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
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Some results may be missing"
        )).firstMatch.exists)
        capture("recme-store-03-trusted-search")
    }

    func test04PlaceDetailShowsMemoryAndRatings() {
        let app = launch(arguments: [
            "-WanderInitialTab", "map",
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
            "-WanderInitialTab", "map",
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

    func testAddOptionsRestoresCompactHeightAfterSeeMore() {
        let app = launch(arguments: [])
        let addPlace = app.buttons["map.headerAdd"]
        XCTAssertTrue(addPlace.waitForExistence(timeout: 10))
        addPlace.tap()
        let title = app.staticTexts["add a place"]
        let seeMore = app.buttons["See more"]
        let importTitle = app.staticTexts["Import"].firstMatch
        XCTAssertTrue(seeMore.waitForExistence(timeout: 10))
        settleForCapture()
        let restingTitleY = title.frame.minY
        XCTAssertTrue(seeMore.isHittable)
        // Native sheet transforms can scale accessibility frames slightly.
        XCTAssertGreaterThanOrEqual(seeMore.frame.height, 43)
        XCTAssertTrue(importTitle.isHittable)
        XCTAssertLessThan(importTitle.frame.minY - seeMore.frame.maxY, 35)
        capture("REC-446 compact production Add")

        seeMore.tap()
        let back = app.buttons["Back to add options"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        settleForCapture()
        XCTAssertLessThan(app.staticTexts["I'm here now"].frame.minY, restingTitleY - 40)
        capture("REC-446 expanded production suggestions")

        back.tap()
        XCTAssertTrue(seeMore.waitForExistence(timeout: 5))
        settleForCapture()
        XCTAssertEqual(title.frame.minY, restingTitleY, accuracy: 3)
        XCTAssertTrue(seeMore.isHittable)
        XCTAssertTrue(importTitle.isHittable)
        capture("REC-446 returned compact production Add")
    }

    func test08PostShowsConversation() {
        let app = launch(arguments: [
            "-WanderInitialTab", "discover", "-WanderNotificationPostUITest",
            "-WanderStorefrontComments",
        ])
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 20))
        settleForCapture()
        XCTAssertTrue(app.staticTexts["Adding this to our Saturday plan."].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Get the patio table. Trust me."].exists)
        XCTAssertTrue(app.staticTexts["I'm in. Saving this now."].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("recme-store-08-conversation")
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderDarkMap",
            "-WanderCompactPeopleUITest",
            "-AppleInterfaceStyle", "Dark",
        ] + arguments
        app.launch()
        // Apply after launch as well: older simulator runtimes may restore the
        // application's cached appearance when the process starts.
        XCUIDevice.shared.appearance = .light
        XCUIDevice.shared.appearance = .dark
        XCTAssertEqual(XCUIDevice.shared.appearance, .dark)
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
