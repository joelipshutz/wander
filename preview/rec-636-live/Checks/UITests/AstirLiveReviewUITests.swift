import XCTest

/// Standalone review-app coverage. The host chooses large/compact simulators.
/// Screenshots are XCTest attachments, not golden-image or accessibility audits.
final class AstirLiveReviewUITests: XCTestCase {
    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        for _ in 0..<attempts {
            let navigation = app.navigationBars.firstMatch
            let isSheet = navigation.exists
            let top = isSheet ? navigation.frame.maxY + 18 : app.frame.minY + 130
            let tab = app.buttons["tab.profile"]
            let mapMode = app.buttons["yourMap.mode.map"]
            let bottom = !isSheet && tab.exists ? tab.frame.minY - 16
                : !isSheet && mapMode.exists ? mapMode.frame.minY - 16 : app.frame.maxY - 55
            if target.exists && target.isHittable && target.frame.minY >= top && target.frame.maxY <= bottom { return }
            let x = isSheet ? navigation.frame.maxX - 8 : app.frame.maxX - 10
            let upward = !target.exists || target.frame.maxY > bottom
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: upward ? bottom - 20 : top + 20))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: upward ? top + 20 : bottom - 20)))
        }
        XCTAssertTrue(target.exists && target.isHittable)
    }

    @MainActor func testCaptureLiveHalf() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab.profile"].exists)
        capture(app, "01-live-map-and-activity")
    }
    @MainActor func testCaptureLiveFeed() {
        let app = launch(["--feed"])
        XCTAssertTrue(app.buttons["feed.map"].waitForExistence(timeout: 5))
        capture(app, "02-live-full-feed")
    }
    @MainActor func testCaptureProfileContinuity() {
        let app = launch(["--profile"])
        XCTAssertTrue(app.staticTexts["Avery Lane"].exists)
        XCTAssertTrue(app.staticTexts["A 3-week save streak"].exists)
        capture(app, "03-profile-identity-social-streak-activity")
        reveal(app.buttons["profile.yourMap"], in: app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["1"].exists)
        XCTAssertTrue(app.staticTexts["6"].exists)
        capture(app, "04-profile-your-map-calendar")
    }
    @MainActor func testCaptureYourMapAndPatterns() {
        let app = launch(["--your-map"])
        XCTAssertFalse(app.buttons["tab.live"].exists)
        capture(app, "05-profile-your-map")
        app.buttons["yourMap.mode.patterns"].tap()
        XCTAssertTrue(app.staticTexts["Close to home. Open to a detour."].waitForExistence(timeout: 5))
        capture(app, "06-profile-your-map-patterns")
    }
    @MainActor func testCaptureTransition() {
        let app = launch(["--feed", "--show-transition"])
        reveal(app.buttons["Show me"], in: app)
        capture(app, "07-optional-transition-after-first-memory")
    }
    @MainActor func testCaptureOfflineAndEmpty() {
        let offline = launch(["--feed", "--scenario-offline"])
        capture(offline, "08-offline-saved-activity")
        offline.terminate()
        let empty = launch(["--feed", "--scenario-empty"])
        XCTAssertTrue(empty.staticTexts["A little quiet here"].waitForExistence(timeout: 5))
        capture(empty, "09-empty-activity")
    }
    @MainActor func testCaptureAccessibleText() {
        let app = launch(["--feed", "--large-text"])
        XCTAssertTrue(app.buttons["feed.map"].waitForExistence(timeout: 5))
        capture(app, "10-accessibility-text-feed")
    }

    @MainActor func testCaptureDarkPeekAndDrawingWithReducedMotion() {
        let app = launch(["--map", "--dark", "--reduce-motion"])
        XCTAssertTrue(app.buttons["area.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab.profile"].exists)
        capture(app, "15-dark-map-peek-reduced-motion")
        app.buttons["area.open"].tap()
        XCTAssertTrue(app.buttons["area.radius.1000"].waitForExistence(timeout: 5))
        capture(app, "16-dark-draw-area-controls")
    }

    @MainActor func testCaptureSparseActivity() {
        let app = launch(["--feed", "--scenario-sparse"])
        XCTAssertTrue(app.buttons["feed.map"].waitForExistence(timeout: 5))
        capture(app, "17-sparse-activity")
    }

    @MainActor func testDrawerScrollAndMapReturn() {
        let app = launch()
        let scroll = app.scrollViews["live.activityScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let startY = app.buttons["tab.profile"].frame.minY - 35
        origin.withOffset(CGVector(dx: app.frame.maxX - 30, dy: startY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.maxX - 30, dy: scroll.frame.minY + 25)))
        XCTAssertTrue(app.buttons["feed.map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.profile"].exists)
        XCTAssertFalse(app.navigationBars["A place memory"].exists, "Swiping the drawer must not open an activity underneath it")
        app.buttons["feed.map"].tap()
        let tabsHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["tab.profile"])
        XCTAssertEqual(XCTWaiter.wait(for: [tabsHidden], timeout: 5), .completed)
        app.buttons["drawer.expand"].tap()
        XCTAssertTrue(app.buttons["feed.map"].waitForExistence(timeout: 5))
        capture(app, "11-drawer-scroll-handoff-and-map-return")
    }
    @MainActor func testProfileYourMapAndPatternsRemainTogether() {
        let app = launch(["--profile"])
        reveal(app.buttons["profile.yourMap"], in: app)
        app.buttons["profile.yourMap"].tap()
        XCTAssertTrue(app.buttons["yourMap.mode.patterns"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab.live"].exists)
        app.buttons["yourMap.mode.patterns"].tap()
        XCTAssertTrue(app.staticTexts["Close to home. Open to a detour."].waitForExistence(timeout: 5))
        app.buttons["yourMap.mode.map"].tap()
        app.buttons["yourMap.back"].tap()
        XCTAssertTrue(app.buttons["tab.profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.profile"].isSelected)
    }
    @MainActor func testSelectivePlaceExplorationReturnsToYourMap() {
        let app = launch(["--your-map"])
        reveal(app.buttons["yourMap.place.Copper Fig"], in: app)
        app.buttons["yourMap.place.Copper Fig"].tap()
        XCTAssertTrue(app.navigationBars["A place memory"].waitForExistence(timeout: 5))
        reveal(app.buttons["detail.exploreLive"], in: app)
        XCTAssertTrue(app.buttons["detail.exploreLive"].label.contains("Explore this place"))
        app.buttons["detail.exploreLive"].tap()
        XCTAssertTrue(app.buttons["profile.return"].waitForExistence(timeout: 5))
        app.buttons["profile.return"].tap()
        XCTAssertTrue(app.buttons["yourMap.back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab.live"].exists)
    }
    @MainActor func testFiltersCancelAndApply() {
        let app = launch(["--feed"])
        app.buttons["filters.open"].tap()
        app.buttons["Wanna"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["activity.open.Juniper Coffee"].waitForExistence(timeout: 5))
        app.buttons["filters.open"].tap()
        app.buttons["Wanna"].tap()
        reveal(app.buttons["filters.apply"], in: app)
        app.buttons["filters.apply"].tap()
        XCTAssertTrue(app.buttons["activity.open.Little Tide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.open.Juniper Coffee"].exists)
    }
    @MainActor func testWannaPlanCreation() {
        let app = launch(["--fixture-wanna"])
        app.buttons["activity.open.Little Tide"].tap()
        reveal(app.buttons["detail.plan"], in: app)
        app.buttons["detail.plan"].tap()
        reveal(app.buttons["plan.create"], in: app)
        app.buttons["plan.create"].tap()
        XCTAssertTrue(app.staticTexts["Demo plan created · saved in Your Map"].waitForExistence(timeout: 5))
        capture(app, "12-local-plan-created")
    }
    @MainActor func testContextualReplyStaysLocal() {
        let app = launch(["--fixture-reply"])
        let field = app.textViews["reply.message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("A fictional reply for this review.")
        app.buttons["reply.doneTyping"].tap()
        reveal(app.buttons["reply.save"], in: app)
        app.buttons["reply.save"].tap()
        XCTAssertTrue(app.staticTexts["Reply saved in your demo inbox"].waitForExistence(timeout: 5))
        app.buttons["Open demo inbox"].tap()
        XCTAssertTrue(app.staticTexts["Saved locally · not sent"].waitForExistence(timeout: 5))
        capture(app, "13-contextual-local-inbox")
    }
    @MainActor func testGeographicPresetApplies() {
        let app = launch(["--fixture-draw"])
        app.buttons["area.radius.1000"].tap()
        app.buttons["area.apply"].tap()
        XCTAssertTrue(app.buttons["area.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["area.open"].label.contains("1.0 km"))
        capture(app, "14-geographic-circle-applied")
    }
}
