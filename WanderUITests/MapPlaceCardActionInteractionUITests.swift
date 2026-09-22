import XCTest

@MainActor
final class MapPlaceCardActionInteractionUITests: XCTestCase {
    func testEditingCheckInKeepsScrollPositionAndOpensPhotos() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest", "-WanderResetWalkthroughs",
            "-WanderREC386PhotoFixture", "-WanderMapPlace", "Dudley Market QA",
            "-WanderMapSheetExpanded"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 12))
        let edit = app.buttons["Edit check-in"].firstMatch
        for _ in 0..<7 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        let form = app.scrollViews["save.editorScroll"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let photos = app.buttons["save.photos"]
        for index in 0..<5 where !photos.isHittable {
            form.swipeUp(velocity: .slow)
            capture("REC-443 editor scroll \(index)")
        }
        XCTAssertTrue(photos.isHittable)
        let scrollReset = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: photos
        )
        scrollReset.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [scrollReset], timeout: 2), .completed)
        photos.tap()
        XCTAssertTrue(app.buttons["Choose from Library"].waitForExistence(timeout: 5))
        capture("REC-443 editor photo menu")
    }

    func testEditingCheckInIncludesPhotoControl() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest", "-WanderResetWalkthroughs",
            "-WanderREC386PhotoFixture", "-WanderMapPlace", "Dudley Market QA",
            "-WanderMapSheetExpanded"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 12))
        let edit = app.buttons["Edit check-in"].firstMatch
        for _ in 0..<7 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5))
        let photos = app.buttons["save.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        XCTAssertTrue(photos.isEnabled, "Existing check-ins must allow adding photos")
        XCTAssertTrue(photos.label.contains("photos"))

    }

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

    func testPerformanceFixturePreservesFeedAcrossSearchRoundTrip() {
        let app = performanceFeedApp()
        app.launch()
        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 12))
        launcher.tap()
        XCTAssertTrue(app.textFields["discover.placesSearchField"].waitForExistence(timeout: 3))
        app.buttons["discover.searchBack"].tap()
        XCTAssertTrue(launcher.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["feed.headerAdd"].isHittable)
    }

    func testFeedFullPlaceProfileKeepsFloatingActionsAndHistoryAboveBottomEdge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover", "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        let place = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.place"]
        reveal(place, in: app)
        XCTAssertTrue(place.isHittable)
        place.tap()
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 10))
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertLessThan(checkIn.frame.maxY, app.frame.maxY)
        capture("REC495 Feed full profile top")
        for _ in 0..<5 { app.swipeUp() }
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertTrue(app.buttons["MY CHECK-INS"].exists)
        // The covered Feed may remain in the accessibility tree; only visible,
        // interactive history controls belong to the presented profile.
        let wannaButtons = app.buttons.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Add to Wanna", "Not in Wanna")
        ).allElementsBoundByIndex
        XCTAssertFalse(wannaButtons.contains { $0.isHittable })
        capture("REC495 Feed full profile history")
        checkIn.tap()
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5))
        capture("REC495 Shared attached check-in editor")
        app.buttons["save.close"].tap()
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        app.buttons["place-profile.floating-action.wanna"].tap()
        XCTAssertTrue(app.textFields["save.note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save.checkInDateDisclosure"].exists)
        XCTAssertFalse(app.buttons["Remove from Wanna"].exists)
        app.buttons["save.close"].tap()
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.otherElements["comments.activity.postcard"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Unlike activity"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Open comments"].exists)
        capture("rec-337-comments-postcard")
        app.navigationBars.buttons.firstMatch.tap()

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

    func testInCommonReleaseFlowOpensTheRealSharedMap() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 6))

        let actorButton = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actorButton, in: app)
        XCTAssertTrue(actorButton.waitForExistence(timeout: 4))
        actorButton.tap()

        let inCommonButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "places in common with Mina")
        ).firstMatch
        reveal(inCommonButton, in: app)
        XCTAssertTrue(inCommonButton.waitForExistence(timeout: 4))
        XCTAssertTrue(inCommonButton.isHittable)
        inCommonButton.tap()

        XCTAssertTrue(app.staticTexts["In Common"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["common-ground.collection-title"].exists)
        let sharedMapButton = app.buttons["Open your shared map"]
        XCTAssertTrue(sharedMapButton.waitForExistence(timeout: 4))
        capture("rec-335-in-common-release")

        sharedMapButton.tap()
        XCTAssertTrue(app.navigationBars["Shared map"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["where you agree"].exists)
        capture("rec-335-in-common-shared-map-release")

        let sharedPlace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "in-common.map-place.")).firstMatch
        reveal(sharedPlace, in: app)
        XCTAssertTrue(sharedPlace.isHittable)
        sharedPlace.tap()
        XCTAssertTrue(app.staticTexts["common-ground.invitation.place"].waitForExistence(timeout: 5))
        let linkage = app.staticTexts["common-ground.invitation.heading"]
        XCTAssertTrue(linkage.exists)
        XCTAssertNotEqual(linkage.label, "ASTIR’s taking the wheel")
        XCTAssertTrue(app.buttons["Share invitation"].exists)
        capture("rec486-shared-map-invitation")
    }

    func testLiveInCommonOpensRealPlaceAndPersonalizedComposer() {
        let app = launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 10))
        let actor = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actor, in: app)
        XCTAssertTrue(actor.waitForExistence(timeout: 5))
        actor.tap()
        let inCommon = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "places in common with Mina")
        ).firstMatch
        reveal(inCommon, in: app)
        XCTAssertTrue(inCommon.waitForExistence(timeout: 5))
        inCommon.tap()
        XCTAssertTrue(app.staticTexts["common-ground.collection-title"].waitForExistence(timeout: 5))
        let photo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "common-ground.place.")).firstMatch
        reveal(photo, in: app)
        XCTAssertTrue(photo.isHittable)
        photo.tap()
        let placeBack = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBack.waitForExistence(timeout: 5))
        capture("rec486-live-place-profile")
        placeBack.tap()
        let invite = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "common-ground.invite.")).firstMatch
        reveal(invite, in: app)
        XCTAssertTrue(invite.isHittable)
        XCTAssertTrue(invite.label.contains("Mina"))
        invite.tap()
        XCTAssertTrue(app.staticTexts["common-ground.invitation.place"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share invitation"].exists)
        XCTAssertFalse(app.staticTexts["Design preview · nothing is sent"].exists)
        capture("rec486-live-compose")
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
