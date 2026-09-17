import XCTest
import UIKit

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
    func testSearchPlaceUsesFloatingActionsAndPreservesResults() {
        continueAfterFailure = false
        let app = profileRoutesApp(initialTab: "discover")
        app.launch()
        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 15))
        launcher.tap()
        let field = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("coffee\n")
        let result = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Astir rating"
        )).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        centerProfileEntry(result, in: app)
        result.tap()
        assertFloatingProfile(app, name: "Search")
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "coffee")
    }

    func testPlaceProfileActionsFromListAndProfileHistory() {
        continueAfterFailure = false
        let app = profileRoutesApp(initialTab: "lists")
        app.launch()
        let list = app.staticTexts["Date night short list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        list.tap()
        let entry = app.buttons["Open Marigold Table"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        centerProfileEntry(entry, in: app)
        entry.tap()
        assertFloatingProfile(app, name: "List")
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        app.terminate()

        let profileApp = profileRoutesApp(initialTab: "profile")
        profileApp.launch()
        let activity = profileApp.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Hearthline Coffee,"
        )).firstMatch
        for _ in 0..<6 where !activity.isHittable { profileApp.swipeUp() }
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        assertFloatingProfile(profileApp, name: "Profile activity")
        profileApp.buttons["place-profile.back"].tap()
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
    }

    func testSharedPlaceLinksUseMapProfileActions() throws {
        continueAfterFailure = false
        for urlString in [
            "recme://places/50000000-0000-0000-0000-000000000386",
            "https://getrec.me/places/50000000-0000-0000-0000-000000000386"
        ] {
            let app = linkedProfileRoutesApp()
            let url = try XCTUnwrap(URL(string: urlString))
            // XCUIApplication.open starts a clean instance. Keep cold delivery
            // independent of the runner's ability to issue a warm system URL.
            app.open(url)
            let card = app.buttons["map.selectedPlaceCard"]
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            XCTAssertTrue(card.label.contains("Dudley Market QA"))
            tapWhenSettled(card)
            assertFloatingProfile(app, name: urlString.hasPrefix("https") ? "Universal link" : "Custom link")
            app.buttons["place-profile.back"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testWarmSharedPlaceLinkReplacesFeedProfile() throws {
        continueAfterFailure = false
        let app = linkedProfileRoutesApp()
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        let feedPlace = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        reveal(feedPlace, in: app)
        centerProfileEntry(feedPlace, in: app)
        feedPlace.tap()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 5))

        let url = try XCTUnwrap(URL(string: "recme://places/50000000-0000-0000-0000-000000000386"))
        let urlOpened = expectation(description: "System delivered the warm place link")
        var deliverySucceeded = false
        // Completion follows the Open Astir confirmation, so handle the dialog
        // before waiting. Some simulator runners are rejected as untrusted.
        UIApplication.shared.open(url, options: [:]) { opened in
            deliverySucceeded = opened
            urlOpened.fulfill()
        }
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if open.waitForExistence(timeout: 5) { tapWhenSettled(open) }
        wait(for: [urlOpened], timeout: 10)
        guard deliverySucceeded else {
            throw XCTSkip("iOS rejected the runner's warm URL request; verify this route from a trusted source on device.")
        }
        app.activate()
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.label.contains("Dudley Market QA"))
        tapWhenSettled(card)
        assertFloatingProfile(app, name: "Warm custom link")
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private func linkedProfileRoutesApp() -> XCUIApplication {
        let app = profileRoutesApp(initialTab: "discover")
        // Screenshot mode bypasses AppEntryView's URL handlers.
        app.launchArguments.removeAll { $0 == "-WanderMapCapture" }
        app.launchArguments += ["-WanderREC386PhotoFixture"]
        return app
    }

    private func profileRoutesApp(initialTab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderPlaceProfileSaveTrayV1", "-WanderInitialTab", initialTab
        ]
        return app
    }

    private func centerProfileEntry(_ entry: XCUIElement, in app: XCUIApplication) {
        // Hittable elements can still sit in the floating header/footer's
        // transition region. Put the entry in the clear middle of the screen.
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<3 where entry.frame.midY > app.frame.height * 0.6 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(entry.isHittable)
    }

    private func tapWhenSettled(_ element: XCUIElement) {
        var previousFrame = CGRect.null
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isHittable, element.isEnabled else { return false }
            let frame = element.frame
            if frame != previousFrame {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince) >= 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        element.tap()
    }

    private func assertFloatingProfile(_ app: XCUIApplication, name: String) {
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "\(name) must use the full screen, without the app tab bar")
        let originalY = checkIn.frame.minY
        capture("REC-532 \(name) top")
        let scroll = app.scrollViews["place-profile.scroll"]
        for _ in 0..<5 { scroll.swipeUp() }
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertTrue(wanna.isHittable)
        XCTAssertEqual(checkIn.frame.minY, originalY, accuracy: 1)
        XCTAssertLessThan(wanna.frame.maxY, app.frame.maxY - 12)
        capture("REC-532 \(name) footer")
        wanna.tap()
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5))
        capture("REC-532 \(name) Wanna editor")
        tapWhenSettled(app.buttons["save.close"])
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
    }

    func testPlaceProfileUsesFloatingActionsAndReturnsToFeed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderPlaceProfileSaveTrayV1", "-WanderInitialTab", "discover"
        ]
        app.launch()
        let place = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.place"]
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        reveal(place, in: app)
        centerProfileEntry(place, in: app)
        place.tap()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 5))
        capture("REC-532 Feed profile top")
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.isHittable)
        XCTAssertEqual(checkIn.label, "Check in")
        XCTAssertEqual(wanna.label, "Wanna")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        let originalY = checkIn.frame.minY
        let scroll = app.scrollViews["place-profile.scroll"]
        for _ in 0..<4 { scroll.swipeUp() }
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertTrue(wanna.isHittable)
        XCTAssertEqual(checkIn.frame.minY, originalY, accuracy: 1)
        XCTAssertLessThan(wanna.frame.maxY, app.frame.maxY - 12)
        capture("REC-532 Feed profile footer")
        wanna.tap()
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5))
        capture("REC-532 Feed Wanna editor")
        tapWhenSettled(app.buttons["save.close"])
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        checkIn.tap()
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5))
        capture("REC-532 Feed Check in editor")
        tapWhenSettled(app.buttons["save.close"])
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertTrue(place.waitForExistence(timeout: 5))
    }

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
        XCTAssertTrue(app.staticTexts["you both keep coming back for"].exists)
        let sharedMapButton = app.buttons["Open your shared map"]
        XCTAssertTrue(sharedMapButton.waitForExistence(timeout: 4))
        capture("rec-335-in-common-release")

        sharedMapButton.tap()
        XCTAssertTrue(app.navigationBars["Shared map"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["where you agree"].exists)
        capture("rec-335-in-common-shared-map-release")
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
