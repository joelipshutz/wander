import XCTest

@MainActor
final class MapPlaceCardActionInteractionUITests: XCTestCase {
    func testActionButtonsCancelAfterDraggingAwayAndStillRespondToTaps() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapPlace", "Hearthline Coffee",
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        let addButton = app.buttons["map.selectedPlaceAction"]
        let shareButton = app.buttons["map.selectedPlaceShare"]
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(shareButton.exists)

        dragAway(from: addButton, onto: card)
        XCTAssertFalse(app.buttons["Close"].waitForExistence(timeout: 1))
        XCTAssertTrue(card.exists)

        dragAway(from: shareButton, onto: card)
        XCTAssertFalse(app.otherElements["ActivityListView"].waitForExistence(timeout: 1))
        XCTAssertTrue(card.exists)
        capture("rec-293-place-action-drag-cancelled")

        addButton.tap()
        let saveClose = app.buttons["Close"]
        XCTAssertTrue(saveClose.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-profile.floating-action.checkIn"].exists)
        saveClose.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let cardIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: card
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cardIsHittable], timeout: 5), .completed)

        app.buttons["map.selectedPlaceShare"].tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertFalse(activityList.waitForExistence(timeout: 3))
    }

    private func dragAway(from button: XCUIElement, onto card: XCUIElement) {
        let start = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = card.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.72))
        start.press(forDuration: 0.6, thenDragTo: destination)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class FeedPostcardInteractionUITests: XCTestCase {
    func testPerformanceFixtureMeasuresFirstScrollHitches() {
        let app = performanceFeedApp()
        app.launch()
        let firstPostcard = app.descendants(matching: .any)[
            "feed.activity.perf-feed-000.postcard"
        ]
        XCTAssertTrue(firstPostcard.waitForExistence(timeout: 12))
        let scroll = app.scrollViews["feed.places.scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 3))
        let initialPostcardY = firstPostcard.frame.minY
        var didMeasureColdSwipe = false

        if #available(iOS 19.0, *) {
            // XCTest always invokes a performance block once more than
            // iterationCount and discards that first invocation. Make the
            // discarded pass a no-op so the measured swipe remains cold.
            var invocationCount = 0
            let options = XCTMeasureOptions()
            options.iterationCount = 1
            options.invocationOptions = [.manuallyStart, .manuallyStop]

            measure(metrics: [XCTHitchMetric(application: app)], options: options) {
                invocationCount += 1
                startMeasuring()
                defer { stopMeasuring() }
                guard invocationCount > 1 else { return }
                scroll.swipeUp(velocity: .fast)
                didMeasureColdSwipe = true
            }
        } else {
            scroll.swipeUp(velocity: .fast)
            didMeasureColdSwipe = true
        }

        XCTAssertTrue(didMeasureColdSwipe)
        XCTAssertTrue(
            !firstPostcard.isHittable || firstPostcard.frame.minY < initialPostcardY - 20,
            "The measured first swipe should move Feed content."
        )
    }

    func testPerformanceFixtureReusesWarmFeedSurfaces() {
        let app = performanceFeedApp()
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 12))

        var dismissedSystemBanner = false
        addUIInterruptionMonitor(withDescription: "Dismiss notification banners") { element in
            guard element.identifier == "NotificationShortLookView" else { return false }
            dismissedSystemBanner = true
            element.swipeUp()
            return true
        }

        let people = app.buttons["People"].firstMatch
        let places = app.buttons["Places"].firstMatch
        XCTAssertTrue(people.waitForExistence(timeout: 3))
        XCTAssertTrue(places.waitForExistence(timeout: 3))

        // Materialize both retained roots before timing the warm path. The
        // existence checks intentionally stay outside the measured window:
        // XCTest polls for at least one second even when the element is ready.
        people.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Search people"].waitForExistence(timeout: 3)
        )
        places.tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 3))

        let switchStartedAt = Date()
        people.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Search people"].waitForExistence(timeout: 2)
        )
        places.tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 2))
        if !dismissedSystemBanner {
            XCTAssertLessThan(
                Date().timeIntervalSince(switchStartedAt),
                5,
                "Two warm Feed surface switches should not rebuild their retained roots."
            )
        }
    }

    private func performanceFeedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab", "discover"
        ]
        return app
    }

    func testActionsDoNotOpenTheNextPlace() {
        let app = launch()

        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 6))

        let likeButton = app.buttons["Like activity"].firstMatch
        reveal(likeButton, in: app)
        XCTAssertTrue(likeButton.waitForExistence(timeout: 4))
        XCTAssertTrue(likeButton.isHittable)
        likeButton.tap()

        XCTAssertTrue(app.buttons["Unlike activity"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["place-profile.back"].exists)

        let commentButton = app.buttons["Open comments"].firstMatch
        XCTAssertTrue(commentButton.isHittable)
        commentButton.tap()
        XCTAssertTrue(app.navigationBars["comments"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.otherElements["comments.activity.postcard"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Unlike activity"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Open comments"].exists)
        capture("rec-337-comments-postcard")
        app.navigationBars["comments"].buttons.firstMatch.tap()

        let saveButton = app.buttons.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Add to Wanna", "Not in Wanna")
        ).firstMatch
        reveal(saveButton, in: app)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 4))
        XCTAssertTrue(saveButton.isHittable)
        saveButton.tap()

        let closeSaveButton = app.buttons["save.close"]
        XCTAssertTrue(closeSaveButton.waitForExistence(timeout: 4))
        closeSaveButton.tap()
        XCTAssertFalse(app.buttons["place-profile.back"].exists)
    }

    func testPlaceAndPersonOpenTheirFullPageDestinations() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 6))

        let placeButton = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.place"]
        reveal(placeButton, in: app)
        XCTAssertTrue(placeButton.waitForExistence(timeout: 4))
        XCTAssertTrue(placeButton.isHittable)
        placeButton.tap()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 4))

        app.terminate()

        let profileApp = launch()
        XCTAssertTrue(profileApp.buttons["feed.searchLauncher"].waitForExistence(timeout: 6))

        let actorButton = profileApp.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actorButton, in: profileApp)
        XCTAssertTrue(actorButton.waitForExistence(timeout: 4))
        XCTAssertTrue(actorButton.isHittable)
        actorButton.tap()

        XCTAssertTrue(profileApp.staticTexts["Mina"].waitForExistence(timeout: 4))
        XCTAssertTrue(profileApp.buttons["Back"].firstMatch.exists)
        XCTAssertFalse(profileApp.buttons["place-profile.back"].exists)
    }

    func testWannaBadgeVisualScale() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 12))

        app.swipeUp()
        let wannaBadge = app.descendants(matching: .any)[
            "feed.activity.fixture-feed-ryan-wanna-noodles.postcard.badge"
        ]
        XCTAssertTrue(wannaBadge.waitForExistence(timeout: 4))
        capture("rec-337-wanna-badge")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab", "discover",
        ]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
