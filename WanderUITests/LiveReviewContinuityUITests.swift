import XCTest

/// Additional integrated review journeys. Uses existing local fixtures only;
/// this does not prove hosted delivery, continuous freehand or VoiceOver use.
@MainActor
final class LiveReviewContinuityUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLiveFilterSurvivesProfileYourMapSavedPlaceAndPatternsReturn() {
        let diagnosticStart = ProcessInfo.processInfo.systemUptime
        let app = launchLive()
        app.buttons["Filters"].tap()
        let people = app.buttons["live.filter.people"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.tap()
        app.buttons["Only Friends"].tap()
        app.buttons["live.applyFilters"].tap()
        waitHittable(app.buttons["live.draw"])

        app.tabBars.buttons["Profile"].tap()
        let preview = app.buttons["profile.yourMap.preview"]
        reveal(preview, in: app.scrollViews.firstMatch, app: app)
        XCTAssertTrue(preview.label.contains("4 places"))
        // The pinned Profile header covers the card's center after scrolling.
        // Use its visible lower content, keeping the same destination assertion.
        let previewFrame = preview.frame
        let previewPoint = CGPoint(x: previewFrame.midX, y: previewFrame.minY + previewFrame.height * 0.9)
        let previewViewport = app.scrollViews.firstMatch.frame.intersection(app.frame)
        let navigationBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 60
        let top = max(previewViewport.minY + 8, navigationBottom + 8)
        let bottom = min(previewViewport.maxY - 8, app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 8 : app.frame.maxY - 44)
        let usable = CGRect(x: previewViewport.minX, y: top, width: previewViewport.width, height: max(0, bottom - top))
        XCTAssertTrue(previewPoint.x.isFinite && previewPoint.y.isFinite && usable.contains(previewPoint))
        captureRouteDiagnostics("profile-preview-before-single-tap", in: app, startedAt: diagnosticStart,
            queries: [("exact-preview-ID", app.buttons.matching(identifier: "profile.yourMap.preview"))],
            observations: ["previewTapPoint=\(previewPoint); usableViewport=\(usable)"])
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.navigationBars["Your Map"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["yourMap.snapshot"].exists)
        XCTAssertTrue(app.buttons["yourMap.prototype.filters"].exists)

        selectSavedMapPin(in: app)
        let selected = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let savedName = String(selected.label.split(separator: ",")[0])
        XCTAssertTrue(["Woodcat Coffee", "Circuit Coffee", "Bar Nido", "Elysian Picnic Steps"].contains(savedName))
        waitHittable(selected)
        selected.tap()
        let placeBack = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[savedName].firstMatch.waitForExistence(timeout: 5))
        placeBack.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.hasPrefix(savedName))

        let patterns = app.buttons.matching(identifier: "yourMap.prototype.mode")
            .matching(NSPredicate(format: "label == %@", "Patterns")).firstMatch
        waitHittable(patterns)
        patterns.tap()
        XCTAssertTrue(app.navigationBars["Patterns"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["yourMap.prototype.patterns"].exists)
        capture("profile-patterns-from-live")
        let mapModes = app.buttons.matching(identifier: "yourMap.prototype.mode")
        let exactMapModes = mapModes.matching(NSPredicate(format: "label == %@", "Map"))
        let activePatternsMapModes = app.buttons.matching(identifier: "yourMap.prototype.patterns")
            .matching(NSPredicate(format: "label == %@", "Map"))
        let map = activePatternsMapModes.firstMatch
        captureRouteDiagnostics("profile-map-return-before-wait", in: app, startedAt: diagnosticStart,
            queries: [("all-mode-ID", mapModes), ("exact-mode-ID-and-Map-label", exactMapModes),
                      ("exact-active-patterns-ID-and-Map-label", activePatternsMapModes),
                      ("all-exact-Map-label-buttons", app.buttons.matching(NSPredicate(format: "label == %@", "Map")))])
        waitHittable(map, diagnosticFailure: {
            self.captureRouteDiagnostics("profile-map-return-wait-failed", in: app, startedAt: diagnosticStart,
                queries: [("all-mode-ID", mapModes), ("exact-mode-ID-and-Map-label", exactMapModes),
                          ("exact-active-patterns-ID-and-Map-label", activePatternsMapModes),
                          ("all-exact-Map-label-buttons", app.buttons.matching(NSPredicate(format: "label == %@", "Map")))])
        })
        map.tap()
        XCTAssertTrue(app.navigationBars["Your Map"].waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.hasPrefix(savedName))
        tapNavigationBack(app.navigationBars["Your Map"])
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("4 places"))

        app.tabBars.buttons["Live"].tap()
        waitHittable(app.buttons["live.draw"])
        app.buttons["Filters"].tap()
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        XCTAssertEqual(people.value as? String, "Only Friends")
        app.buttons["Cancel"].tap()
        waitHittable(app.buttons["live.draw"])
        capture("live-filter-after-your-map-return")
    }

    func testPinShowsItsOriginalFeedActivityAndOpensItsPlaceWithReturn() {
        let diagnosticStart = ProcessInfo.processInfo.systemUptime
        let app = launchLive()
        let destinationTopLimit = app.buttons["live.scope.featured"].frame.maxY
        let pin = app.buttons["live.pin.place_noodles"]
        waitHittable(pin)
        XCTAssertTrue(pin.label.contains("Ryan"))
        XCTAssertTrue(pin.label.contains("Wanna"))
        pin.tap()
        let activity = app.descendants(matching: .any)["live.placePreview.activity.fixture-feed-ryan-wanna-noodles"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        // The activity row contains its open-place button and an optional photo
        // control. Read attribution from that button, not its unlabeled container.
        let activityAttribution = activity.buttons.firstMatch
        XCTAssertTrue(activityAttribution.waitForExistence(timeout: 5))
        XCTAssertTrue(activityAttribution.label.contains("Ryan"))
        XCTAssertTrue(activityAttribution.label.contains("Wanna"))
        XCTAssertTrue(activityAttribution.label.contains("5h ago"))
        let open = app.buttons["live.placePreview.open"]
        captureRouteDiagnostics("pin-selected-before-open", in: app, startedAt: diagnosticStart,
            queries: [("selected-place-open", app.buttons.matching(identifier: "live.placePreview.open")),
                      ("selected-activity", app.descendants(matching: .any).matching(
                          identifier: "live.placePreview.activity.fixture-feed-ryan-wanna-noodles"))])
        waitHittable(open)
        XCTAssertEqual(open.label, "Open Larchmont Noodles")
        open.tap()
        let placeBack = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Larchmont Noodles"].firstMatch.waitForExistence(timeout: 5))
        capture("original-place-from-pin-preview")
        placeBack.tap()
        XCTAssertTrue(placeBack.waitForNonExistence(timeout: 5))
        // The full place modal returns to the selected preview. Verify that
        // original place/activity before explicitly closing it to reach Feed.
        waitHittable(open)
        XCTAssertEqual(open.label, "Open Larchmont Noodles")
        XCTAssertTrue(activityAttribution.label.contains("Ryan"))
        XCTAssertTrue(activityAttribution.label.contains("Wanna"))
        XCTAssertTrue(activityAttribution.label.contains("5h ago"))
        capture("original-place-return-to-pin-preview")
        let closePreview = app.buttons["live.placePreview.close"]
        waitHittable(closePreview)
        closePreview.tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
        waitDrawer("collapsed", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        expandDrawer(in: app)

        let feed = app.scrollViews["feed.places.scroll"]
        let card = app.descendants(matching: .any)["feed.activity.fixture-feed-ryan-wanna-noodles.postcard"].firstMatch
        let actor = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"]
        reveal(actor, in: feed, app: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        waitForFocusedCardIntersection(card, in: feed, app: app)
        XCTAssertTrue(actor.label.contains("Ryan"))
        let destination = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        XCTAssertTrue(destination.label.contains("Larchmont Noodles"))
        let comments = card.buttons["Open comments"]
        reveal(comments, in: feed, app: app)
        waitDrawer("expanded", in: app)
        comments.tap()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["comments.activity.actor"].label.contains("Ryan"))
        XCTAssertTrue(app.buttons["comments.activity.place"].label.contains("Larchmont Noodles"))
        assertEmbeddedDestinationFillsViewport(
            app.navigationBars.firstMatch.buttons.element(boundBy: 0),
            in: app, topLimit: destinationTopLimit)
        capture("original-wanna-activity-from-pin")
        tapNavigationBack(app.navigationBars.firstMatch)
        XCTAssertTrue(send.waitForNonExistence(timeout: 5))
        // The preceding pin-profile round trip must not leave a departure
        // snapshot that replaces this later, genuinely scrolled Feed position.
        waitDrawer("expanded", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        waitForFocusedCardIntersection(card, in: feed, app: app)

        reveal(destination, in: feed, app: app)
        waitHittable(destination)
        destination.tap()
        XCTAssertTrue(placeBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Larchmont Noodles"].firstMatch.waitForExistence(timeout: 5))
        capture("same-place-from-original-feed-activity")
        placeBack.tap()
        XCTAssertTrue(placeBack.waitForNonExistence(timeout: 5))
        waitDrawer("expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    func testEmbeddedFeedKeepsInvitePeopleActivityOrderAndProfileReturn() {
        let app = launchLive(extraArguments: ["-WanderLiveFeedPhotosUITest"])
        expandDrawer(in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let invite = app.buttons["live.utility.invite"]
        let people = app.staticTexts["People worth following"].firstMatch
        let activity = app.staticTexts.matching(NSPredicate(format: "label == %@", "Activity")).firstMatch
        reveal(people, in: feed, app: app)
        waitHittable(invite)
        XCTAssertTrue(app.frame.contains(invite.frame))
        XCTAssertFalse(feed.buttons["live.utility.invite"].exists)
        XCTAssertLessThanOrEqual(invite.frame.maxY, feed.frame.minY + 1)
        XCTAssertLessThan(invite.frame.maxY, people.frame.minY)
        capture("drawer-invite-above-people")
        reveal(activity, in: feed, app: app)
        XCTAssertTrue(physicallyVisible(people, in: feed, app: app))
        XCTAssertLessThan(people.frame.maxY, activity.frame.minY)
        capture("embedded-people-before-activity")

        let card = app.descendants(matching: .any)["feed.activity.fixture-feed-maya-been-bar-nido.postcard"].firstMatch
        let photos = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.postcard.photos"]
        reveal(photos, in: feed, app: app)
        XCTAssertEqual(photos.value as? String, "3 photos")
        XCTAssertGreaterThanOrEqual(photos.frame.width, 44)
        XCTAssertGreaterThanOrEqual(photos.frame.height, 44)
        XCTAssertTrue(card.exists)
        // The committed viewport includes four place-backed fixtures, not the
        // place-less list-created event in the unfiltered five-event Feed seed.
        XCTAssertEqual(feed.value as? String, "4 activities loaded")
        let drawer = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        let committedDrawerValue = drawer.value as? String
        XCTAssertNotNil(committedDrawerValue)
        XCTAssertTrue(committedDrawerValue?.hasPrefix("4 activities.") == true)
        waitDrawer("expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        photos.tap()

        let photoBack = app.buttons["activity.photos.back"]
        let position = app.staticTexts["activity.photos.position"]
        XCTAssertTrue(photoBack.waitForExistence(timeout: 5))
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(position.label, "1 of 3")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo of Sample check-in photo 1"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["activity.photos.unavailable"].exists)
        XCTAssertFalse(app.staticTexts["Photo unavailable"].exists)
        XCTAssertFalse(app.buttons["profile.back"].exists)
        XCTAssertFalse(app.buttons["place-profile.back"].exists)
        capture("embedded-photo-first")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        )
        let secondPhoto = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "2 of 3"), object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondPhoto], timeout: 5), .completed)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo of Sample check-in photo 2"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Photo unavailable"].exists)
        capture("embedded-photo-second")
        photoBack.tap()
        XCTAssertTrue(photoBack.waitForNonExistence(timeout: 5))
        waitDrawer("expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        XCTAssertTrue(card.exists)
        XCTAssertEqual(feed.value as? String, "4 activities loaded")
        XCTAssertEqual(drawer.value as? String, committedDrawerValue)
        XCTAssertEqual(photos.value as? String, "3 photos")
        XCTAssertTrue(physicallyVisible(photos, in: feed, app: app))
        XCTAssertFalse(app.buttons["profile.back"].exists)
        XCTAssertFalse(app.buttons["place-profile.back"].exists)
        capture("embedded-photo-return-to-live")

        let actor = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actor, in: feed, app: app)
        XCTAssertTrue(actor.label.contains("Maya"))
        actor.tap()
        let profileBack = app.buttons["profile.back"]
        XCTAssertTrue(profileBack.waitForExistence(timeout: 10))
        let name = app.descendants(matching: .any)["profile.header.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.contains("Maya"))
        profileBack.tap()
        XCTAssertTrue(profileBack.waitForNonExistence(timeout: 5))
        XCTAssertTrue(actor.waitForExistence(timeout: 5))
        waitDrawer("expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        capture("embedded-feed-after-profile-return")
    }

    func testLiveSearchNotificationsAndAddCancelReturnToSameSurface() {
        let diagnosticStart = ProcessInfo.processInfo.systemUptime
        let app = launchLive()
        waitDrawer("half expanded", in: app)
        let originalDrawerLabel = app.staticTexts["live.drawerHandle"].label
        let destinationTopLimit = app.buttons["live.scope.featured"].frame.maxY
        let searchMatches = app.buttons.matching(NSPredicate(format: "label == %@", "Search"))
        let search = readySearch(in: app, startedAt: diagnosticStart)
        captureRouteDiagnostics("search-before-single-tap", in: app, startedAt: diagnosticStart,
            queries: [("exact-Search-label", searchMatches)])
        let tappedAt = ProcessInfo.processInfo.systemUptime
        let destinationDeadline = tappedAt + 10
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let searchBack = app.buttons["discover.searchBack"]
        // Observe the native destination before collecting the full hierarchy.
        let immediateSearchExists = searchBack.exists
        let immediateObservedAt = ProcessInfo.processInfo.systemUptime
        var reachedSearch = immediateSearchExists && immediateObservedAt <= destinationDeadline
        captureRouteDiagnostics("search-after-single-tap", in: app, startedAt: diagnosticStart,
            queries: [("exact-Search-label", searchMatches)], observations: [
                "tapStartedElapsedSeconds=\(tappedAt - diagnosticStart)",
                "immediateSearchExists=\(immediateSearchExists); observedElapsedSeconds=\(immediateObservedAt - diagnosticStart); withinDestinationDeadline=\(immediateObservedAt <= destinationDeadline)"
            ])
        // Capture time counts inside the original ten seconds from the only tap.
        if !reachedSearch {
            let remaining = destinationDeadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                let appeared = searchBack.waitForExistence(timeout: remaining)
                let observedAt = ProcessInfo.processInfo.systemUptime
                reachedSearch = appeared && observedAt <= destinationDeadline
            }
        }
        if !reachedSearch {
            captureRouteDiagnostics("search-destination-wait-failed", in: app, startedAt: diagnosticStart,
                queries: [("exact-Search-label", searchMatches)])
        }
        XCTAssertTrue(reachedSearch)
        dismissFirstKeyboardTutorial(in: app)
        waitHittable(searchBack)
        assertEmbeddedDestinationFillsViewport(searchBack, in: app, topLimit: destinationTopLimit)
        searchBack.tap()
        XCTAssertTrue(searchBack.waitForNonExistence(timeout: 5))
        // Search and Notifications restore the unscrolled detent we left from.
        waitDrawer("half expanded", in: app)
        XCTAssertEqual(app.staticTexts["live.drawerHandle"].label, originalDrawerLabel)
        waitHittable(app.buttons["live.draw"])
        app.buttons["Notifications"].tap()
        let inbox = app.navigationBars["Notifications"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        assertEmbeddedDestinationFillsViewport(
            inbox.buttons.element(boundBy: 0), in: app, topLimit: destinationTopLimit)
        capture("notifications-from-live")
        tapNavigationBack(inbox)
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 5))
        waitDrawer("half expanded", in: app)
        XCTAssertEqual(app.staticTexts["live.drawerHandle"].label, originalDrawerLabel)
        waitHittable(app.buttons["live.draw"])
        app.buttons["Add a place"].tap()
        let close = app.buttons["Close add place"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitHittable(close)
        capture("add-from-live-before-cancel")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        waitHittable(app.buttons["live.draw"])
        waitDrawer("half expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Lists"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        XCTAssertFalse(searchBack.exists)
        XCTAssertFalse(inbox.exists)
        capture("live-after-search-notifications-add-cancel")
    }

    private func launchLive(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture",
            "-WanderInitialTab", "discover",
            "-astir.live.introduction.v1.user_joe.acknowledged", "YES",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        waitHittable(app.buttons["live.draw"], timeout: 20)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        return app
    }

    private func expandDrawer(in app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        waitHittable(handle)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        waitDrawer("expanded", in: app)
    }

    private func waitDrawer(_ state: String, in app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Activity drawer, \(state)"), object: handle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10,
                              diagnosticFailure: (() -> Void)? = nil) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed { diagnosticFailure?() }
        XCTAssertEqual(result, .completed)
    }

    private func readySearch(in app: XCUIApplication, startedAt: TimeInterval) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", "Search"))
        let count = matches.count
        if count != 1 {
            captureRouteDiagnostics("search-readiness-failed", in: app, startedAt: startedAt,
                queries: [("exact-Search-label", matches)])
        }
        XCTAssertEqual(count, 1, "Expected exactly one Search control for its only tap")
        let element = matches.element(boundBy: 0)
        let hittable = element.exists && element.isEnabled && element.isHittable
        let frame = hittable ? element.frame : CGRect.null
        let ready = hittable && !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite })
            && frame.width >= 44 && frame.height >= 44 && app.frame.contains(frame)
        if !ready {
            captureRouteDiagnostics("search-readiness-failed", in: app, startedAt: startedAt,
                queries: [("exact-Search-label", matches)])
        }
        XCTAssertTrue(ready, "Expected one enabled, hittable Search control with a full safe44pt frame")
        return element
    }

    private func captureRouteDiagnostics(_ name: String, in app: XCUIApplication, startedAt: TimeInterval,
                                         queries: [(String, XCUIElementQuery)], observations: [String] = []) {
        func elapsed() -> TimeInterval { ProcessInfo.processInfo.systemUptime - startedAt }
        var lines = ["sampleStartedElapsedSeconds=\(elapsed())"] + observations
        let drawer = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        let liveTab = app.tabBars.buttons["Live"]
        lines.append("liveTabExists=\(liveTab.exists); liveTabSelected=\(liveTab.exists ? String(liveTab.isSelected) : "absent")")
        lines.append("drawerExists=\(drawer.exists); drawerLabel=\(drawer.exists ? drawer.label : "absent")")
        lines.append("discoverBackExists=\(app.buttons["discover.searchBack"].exists)")
        for (label, query) in queries {
            let matches = query.allElementsBoundByIndex
            lines.append("query=\(label); count=\(matches.count); observedElapsedSeconds=\(elapsed())")
            lines.append(query.debugDescription)
            for (index, element) in matches.enumerated() {
                guard element.exists else {
                    lines.append("match=\(index); disappearedBeforeAttributes=true; observedElapsedSeconds=\(elapsed())")
                    continue
                }
                let frame = element.frame
                let finite = !frame.isNull && !frame.isInfinite && !frame.isEmpty
                    && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
                lines.append("match=\(index); id=\(element.identifier); label=\(element.label); value=\(String(describing: element.value)); frame=\(frame); finite=\(finite); enabled=\(element.isEnabled); selected=\(element.isSelected); hittable=\(element.isHittable); observedElapsedSeconds=\(elapsed())")
            }
        }
        lines.append("hierarchyRequestedElapsedSeconds=\(elapsed())")
        let hierarchy = app.debugDescription
        lines.append("hierarchyFinishedElapsedSeconds=\(elapsed())")
        capture(name)
        lines.append("screenFinishedElapsedSeconds=\(elapsed())")
        let state = XCTAttachment(string: lines.joined(separator: "\n"))
        state.name = "REC-636-continuity-\(name)-route-state"
        state.lifetime = .keepAlways
        add(state)
        let tree = XCTAttachment(string: hierarchy)
        tree.name = "REC-636-continuity-\(name)-full-hierarchy"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func physicallyVisible(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) -> Bool {
        guard element.exists, scroll.exists else { return false }
        let frame = element.frame
        guard !frame.isNull, !frame.isInfinite, !frame.isEmpty else { return false }
        let viewport = scroll.frame.intersection(app.frame)
        let navigationBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 60
        let top = max(viewport.minY + 8, navigationBottom + 8)
        let bottom = min(viewport.maxY - 8, app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 8 : app.frame.maxY - 44)
        return frame.minY >= top && frame.maxY <= bottom && element.isHittable
    }

    private func dismissFirstKeyboardTutorial(in app: XCUIApplication) {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        let explanation = introduction.staticTexts[
            "Speed up your typing by sliding your finger across the letters to compose a word."]
        guard explanation.waitForExistence(timeout: 1) else { return }
        let buttons = introduction.buttons.matching(NSPredicate(format: "label == %@", "Continue"))
        let count = buttons.count
        XCTAssertEqual(count, 1, "The recognized system typing tutorial must have one Continue button.")
        guard count == 1 else { return }
        let button = buttons.element
        let actionable = button.isEnabled && button.isHittable
        XCTAssertTrue(actionable)
        guard actionable else { return }
        button.tap()
        XCTAssertTrue(explanation.waitForNonExistence(timeout: 5))
    }

    private func assertEmbeddedDestinationFillsViewport(_ back: XCUIElement,
                                                        in app: XCUIApplication, topLimit: CGFloat) {
        let initialAppFrame = app.frame
        XCTAssertTrue(topLimit.isFinite && topLimit > initialAppFrame.minY && topLimit < initialAppFrame.midY)
        let forbiddenButtons = ["Upcoming events", "Close selected place", "live.draw"]
        var lastValues: [String: Bool] = [:]
        var lastBackFrame = CGRect.null
        var lastAppFrame = CGRect.null
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + 5
        func observeDestination() -> Bool {
            lastValues = [:]
            lastBackFrame = .null
            lastAppFrame = .null
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            // Resolve the requested native element, then inspect its geometry,
            // the app bounds and forbidden chrome in one fresh hierarchy.
            // Serial absence/frame queries can consume the budget and return
            // geometry from different snapshots after keyboard transitions.
            guard let target = try? back.snapshot() else {
                lastValues["backExists"] = false
                return false
            }
            guard ProcessInfo.processInfo.systemUptime <= deadline,
                  let snapshot = try? app.snapshot() else { return false }
            var matches: [XCUIElementSnapshot] = []
            var chromeExists = false
            func visit(_ node: XCUIElementSnapshot) {
                if node.elementType == target.elementType,
                   node.identifier == target.identifier, node.label == target.label {
                    matches.append(node)
                }
                if node.identifier == "live.drawerHandle" || node.label == "live.drawerHandle"
                    || (node.elementType == .button
                        && (forbiddenButtons.contains(node.identifier) || forbiddenButtons.contains(node.label))) {
                    chromeExists = true
                }
                for child in node.children { visit(child) }
            }
            visit(snapshot)
            lastValues["backExists"] = !matches.isEmpty
            lastValues["backUnambiguous"] = matches.count == 1
            lastValues["forbiddenChromeExists"] = chromeExists
            guard matches.count == 1, !chromeExists else { return false }
            let frame = matches[0].frame
            lastBackFrame = frame
            let validFrame = !frame.isNull && !frame.isInfinite && !frame.isEmpty
            lastValues["backFrameValid"] = validFrame
            guard validFrame else { return false }
            let appFrame = snapshot.frame
            lastAppFrame = appFrame
            let contained = appFrame.contains(frame)
            let atTop = frame.minY <= topLimit
            lastValues["backFrameContained"] = contained
            lastValues["backFrameAtTop"] = atTop
            guard contained && atTop,
                  ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            let hittable = back.isHittable
            lastValues["backHittable"] = hittable
            return hittable && ProcessInfo.processInfo.systemUptime <= deadline
        }
        let result: XCTWaiter.Result
        if observeDestination() {
            result = .completed
        } else {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                observeDestination()
            }, object: nil)
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            result = remaining > 0 ? XCTWaiter.wait(for: [expectation], timeout: remaining) : .timedOut
        }
        if result != .completed {
            let values = lastValues.keys.sorted().map { "\($0)=\(lastValues[$0]!)" }.joined(separator: "; ")
            let observation = XCTAttachment(string:
                "\(values); backFrame=\(lastBackFrame); appFrame=\(lastAppFrame); topLimit=\(topLimit); elapsedSeconds=\(ProcessInfo.processInfo.systemUptime - startedAt)")
            observation.name = "REC-636-embedded-viewport-last-observation"
            observation.lifetime = .keepAlways
            add(observation)
        }
        XCTAssertEqual(result, .completed,
                       "Embedded Feed destinations must use the top viewport without Live chrome.")
    }

    private func waitForFocusedCardIntersection(_ card: XCUIElement, in feed: XCUIElement, app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard card.exists, feed.exists else { return false }
            let frame = card.frame
            let viewport = feed.frame.intersection(app.frame)
            guard !frame.isNull, !frame.isInfinite, !frame.isEmpty,
                  !viewport.isNull, !viewport.isInfinite, !viewport.isEmpty else { return false }
            let bottom = min(viewport.maxY - 8, app.tabBars.firstMatch.frame.minY - 8)
            let usable = CGRect(x: viewport.minX, y: viewport.minY + 8,
                                width: viewport.width, height: max(0, bottom - viewport.minY - 8))
            let visible = frame.intersection(usable)
            // The postcard may exceed the compact viewport; require a real
            // visible portion before any manual scrolling can hide a lost focus.
            return !visible.isNull && visible.width >= 44 && visible.height >= 44
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication,
                        leadingPaddingReference: XCUIElement? = nil) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for attempt in 0..<10 {
            let exists = element.exists
            let frame = exists ? element.frame : CGRect.null
            let finite = !frame.isNull && !frame.isInfinite && !frame.isEmpty
                && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
            let hittable = exists && element.isHittable
            let viewport = scroll.frame.intersection(app.frame)
            let navigationBottom = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 60
            let top = max(viewport.minY + 8, navigationBottom + 8)
            let bottom = min(viewport.maxY - 8, app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 8 : app.frame.maxY - 44)
            if finite, frame.minY >= top, frame.maxY <= bottom, hittable { return }
            // A focused card can begin above or below the usable viewport.
            // Re-sample its geometry before each bounded native drag instead
            // of continuing upward after passing the requested action.
            let dragDown = finite && frame.minY < top
            guard top.isFinite, bottom.isFinite, bottom > top,
                  viewport.minX.isFinite, viewport.width.isFinite, viewport.width > 0 else {
                capture("invalid-continuity-scroll-viewport")
                XCTFail("Expected a finite usable scroll viewport")
                return
            }
            // A small overflow needs a small adjustment. Fixed fast drags can
            // fling the action past the opposite edge and oscillate forever.
            let usableHeight: CGFloat = bottom - top
            let maximumDistance: CGFloat = usableHeight * 0.27
            let overflow: CGFloat = finite ? (dragDown ? max(0, top - frame.minY) : max(0, frame.maxY - bottom)) : maximumDistance
            let targetMargin: CGFloat = finite ? frame.height / 2 : 0
            let distance: CGFloat = min(maximumDistance, overflow + targetMargin)
            let x: CGFloat
            if let leadingPaddingReference {
                guard leadingPaddingReference.exists else {
                    capture("selected-card-padding-reference-missing")
                    XCTFail("Expected the selected card content before its native scroll")
                    return
                }
                // selectedPlace has 16pt inner padding. Its timestamp marks the
                // content edge; the midpoint of that padding avoids both the
                // card buttons and the native trailing scroll-indicator strip.
                x = leadingPaddingReference.frame.minX - 8
            } else {
                x = viewport.minX + viewport.width * 0.98
            }
            let startY: CGFloat = top + usableHeight * (dragDown ? 0.48 : 0.75)
            let endY: CGFloat = startY + (dragDown ? distance : -distance)
            if leadingPaddingReference != nil {
                let path = CGRect(x: x - 1, y: min(startY, endY), width: 2, height: abs(endY - startY))
                let touchesButton = scroll.buttons.allElementsBoundByIndex.contains { button in
                    guard button.exists else { return false }
                    let buttonFrame = button.frame
                    return !buttonFrame.isNull && !buttonFrame.isInfinite && buttonFrame.intersects(path)
                }
                guard x.isFinite, x > viewport.minX, x < viewport.maxX, !touchesButton else {
                    capture("selected-card-padding-corridor-missing")
                    XCTFail("Expected a native drag corridor inside selected-card padding and outside its buttons")
                    return
                }
            }
            let diagnostic = XCTAttachment(string: "attempt=\(attempt + 1); exists=\(exists); hittable=\(hittable); targetFrame=\(frame); finite=\(finite); viewport=\(viewport); usableTop=\(top); usableBottom=\(bottom); direction=\(dragDown ? "down" : "up"); overflow=\(overflow); targetMargin=\(targetMargin); distance=\(distance); contactX=\(x); startY=\(startY); endY=\(endY); velocity=slow; endHold=0.1")
            diagnostic.name = "REC-636-continuity-reveal-gesture-\(attempt + 1)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            // Keep both native contacts inside the usable content and release
            // after a short stationary hold instead of ending with a flick.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        // The final allowed gesture still gets its normal observation; this
        // adds no input, delay or visibility exception.
        if physicallyVisible(element, in: scroll, app: app) { return }
        capture("unreachable-continuity-element")
        XCTFail("Expected fixture target to enter the visible scroll content")
    }

    private func selectSavedMapPin(in app: XCUIApplication) {
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin."))
        XCTAssertTrue(pins.firstMatch.waitForExistence(timeout: 8))
        let frames = pins.allElementsBoundByIndex.map(\.frame).filter {
            !$0.isNull && !$0.isInfinite && app.frame.contains($0)
        }
        guard !frames.isEmpty else { return XCTFail("Expected saved fixture pins in the native map viewport") }
        let center = CGVector(dx: frames.map(\.midX).reduce(0, +) / CGFloat(frames.count),
                              dy: frames.map(\.midY).reduce(0, +) / CGFloat(frames.count))
        app.coordinate(withNormalizedOffset: .zero).withOffset(center).tap()
    }

    private func tapNavigationBack(_ bar: XCUIElement) {
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let back = bar.buttons.element(boundBy: 0)
        waitHittable(back)
        back.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-636-continuity-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Evidence-only appendix for LiveReviewContinuityUITests.swift, which imports XCTest.
/// Uses the same current Live fixtures and committed-query contract as the journeys above.
@MainActor
final class LiveDrawerAndFilterUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // Featured commits a viewport polygon: the four place activities match it;
    // Maya’s list-created event has no place and remains outside that query.
    private let allPlaceIDs: Set<String> = [
        "place_bar_nido", "place_noodles", "place_juniper_table", "place_fern_desk_coffee"
    ]
    private let combinedSummary = "25 km · Los Angeles · Past 24 hours · Wannas · 1 category · 1 person · Only Friends"

    func testEveryDrawerDetentAndNativeMapPanKeepTheLoadedActivity() {
        let app = launchLive()
        assertDrawer("half expanded", count: 4, in: app)
        assertTabs(in: app)
        assertPins(allPlaceIDs, in: app)
        assertMapControls(in: app)
        capture("drawer-initial-half")

        dragDrawer(.up, to: "expanded", count: 4, in: app)
        assertTabs(in: app)
        XCTAssertFalse(app.buttons["live.draw"].exists)
        assertFeedCount(4, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let actor = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actor, in: feed, direction: .down, app: app)
        XCTAssertTrue(actor.label.contains("Maya"))
        capture("drawer-expanded-existing-feed")

        dragDrawer(.down, to: "half expanded", count: 4, in: app)
        assertMapControls(in: app)
        dragDrawer(.down, to: "collapsed", count: 4, in: app)
        assertTabs(in: app)
        assertMapControls(in: app)
        captureState("drawer-collapsed-before-accessibility-check", in: app, observations: [
            "feedExists=\(feed.exists); feedHittable=\(feed.exists ? feed.isHittable : false)",
            "feedButtonCount=\(feed.exists ? feed.buttons.count : 0); feedStaticTextCount=\(feed.exists ? feed.staticTexts.count : 0)",
            "mayaActorExists=\(actor.exists); mayaActorHittable=\(actor.exists ? actor.isHittable : false)"
        ])
        assertCollapsedFeedDoesNotReceiveTouches(feed)
        XCTAssertTrue(app.links["Legal"].exists)
        capture("drawer-collapsed-map")

        panMapOnce(anchorID: "place_noodles", in: app)
        assertDrawer("collapsed", count: 4, in: app)
        assertPins(allPlaceIDs, in: app)
        assertCollapsedFeedDoesNotReceiveTouches(feed)
        capture("drawer-collapsed-after-native-pan")

        dragDrawer(.up, to: "half expanded", count: 4, in: app)
        assertTabs(in: app)
        assertMapControls(in: app)
        XCTAssertEqual(app.buttons["Filters"].value as? String, "0 active filters")
        XCTAssertEqual(summary(in: app).label, "All time")
        assertFeedCount(4, in: app)
        capture("drawer-half-after-pan-and-return")
    }

    func testFiltersLeadingEdgeOfMinimumHitTargetOpensSheet() {
        assertFilterEdgeOpensSheet(.leading)
    }

    func testFiltersTrailingEdgeOfMinimumHitTargetOpensSheet() {
        assertFilterEdgeOpensSheet(.trailing)
    }

    private func assertFilterEdgeOpensSheet(_ edge: FilterHitEdge) {
        let app = launchLive()
        openFilters(in: app, pressAtEdge: edge)
        let navigation = app.navigationBars["Filters"]
        XCTAssertTrue(navigation.exists)
        navigation.buttons["Cancel"].tap()
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 5))
        assertDrawer("half expanded", count: 4, in: app)
        XCTAssertEqual(app.buttons["Filters"].value as? String, "0 active filters")
        XCTAssertEqual(summary(in: app).label, "All time")
    }

    func testCombinedFiltersApplyCancelAndResetKeepMapAndFeedInAgreement() {
        let app = launchLive()
        openFilters(in: app)
        let form = filterForm(in: app)
        captureState("filters-initial-before-controls", in: app)
        selectMenu(app.buttons["live.filter.people"], option: "Only Friends", form: form, app: app, selected: {
            $0.identifier == "live.filter.people" && $0.value as? String == "Only Friends"
        })
        selectMenu(form.buttons["Activity, All"], option: "Wannas", form: form, app: app, selected: {
            $0.label == "Activity, Wannas"
        })
        selectMenu(app.buttons["live.filter.time"], option: "Past 24 hours", form: form, app: app, selected: {
            $0.identifier == "live.filter.time" && $0.label == "When, Past 24 hours"
        })
        selectMenu(app.buttons["live.filter.scope"], option: "Nearby", form: form, app: app, selected: {
            $0.identifier == "live.filter.scope" && $0.value as? String == "Nearby"
        })
        let city = app.buttons["live.filter.city"]
        reveal(city, in: form, direction: .down, app: app)
        captureCityPickerState("city-picker-before-tap", in: app, observations: [
            "cityExists=\(city.exists); cityFrame=\(city.frame); cityHittable=\(city.isHittable)"
        ])
        // Use one deliberate native row-center press; destination observation
        // below retains its five-second limit and exact selection assertions.
        city.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2)
        guard let cityTarget = revealNativeCityOption("Los Angeles", in: app) else { return }
        let losAngeles = cityTarget.element
        let contact = CGPoint(x: cityTarget.frame.midX, y: cityTarget.frame.midY)
        let diagnostic = XCTAttachment(string: "city=Los Angeles; verifiedFrame=\(cityTarget.frame); verifiedViewport=\(cityTarget.viewport); verifiedEnabled=true; verifiedHittable=true; contact=\(contact); pressDuration=0.2")
        diagnostic.name = "REC-636-native-city-option-physical-target"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        // Use the row center just verified inside the city list; avoid a second
        // native activation-point lookup before the one explicit city choice.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: contact.x - app.frame.minX, dy: contact.y - app.frame.minY))
            .press(forDuration: 0.2)
        let cityNavigation = app.navigationBars["Area center"]
        XCTAssertTrue(cityNavigation.exists)
        XCTAssertTrue(losAngeles.isSelected)
        let filtersBack = cityNavigation.buttons["Filters"]
        XCTAssertTrue(filtersBack.isHittable)
        filtersBack.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        reveal(app.buttons["25 km"], in: form, direction: .down, app: app)
        app.buttons["25 km"].tap()
        setOn(app.switches["live.filter.category.restaurants_food"], in: form, app: app)
        setOn(app.switches["live.filter.person.user_ryan"], in: form, app: app)
        let workEducation = app.switches["live.filter.category.work_education"]
        reveal(workEducation, in: form, direction: .up, app: app)
        XCTAssertEqual(workEducation.label, "Work & Education")
        let civicFaith = app.switches["live.filter.category.civic_faith"]
        reveal(civicFaith, in: form, direction: .down, app: app)
        XCTAssertEqual(civicFaith.label, "Civic & Faith")
        capture("combined-filter-draft")
        app.buttons["live.applyFilters"].tap()

        assertCombinedResult(in: app)
        panMapOnce(anchorID: "place_noodles", in: app)
        assertCombinedResult(in: app, drawerState: "collapsed")
        dragDrawer(.up, to: "half expanded", count: 1, in: app)
        dragDrawer(.up, to: "expanded", count: 1, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let actor = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"]
        let place = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        reveal(place, in: feed, direction: .down, app: app)
        XCTAssertTrue(place.label.contains("Larchmont Noodles"))
        reveal(actor, in: feed, direction: .down, app: app)
        XCTAssertTrue(actor.label.contains("Ryan"))
        capture("combined-filter-selected-wanna")

        let older = feed.descendants(matching: .any)["feed.olderActivity"].firstMatch
        reveal(older, in: feed, direction: .down, app: app)
        XCTAssertTrue(older.exists, "Older matching activity has its own boundary even when this fixture has no older match.")
        let disclosure = "These posts are outside your selected location, people, categories and activity filters."
        let allBoundary = feed.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", disclosure, "Showing all activity")).firstMatch
        reveal(allBoundary, in: feed, direction: .down, app: app)
        XCTAssertTrue(allBoundary.label.hasPrefix(disclosure),
                      "The disclosure must precede the all-activity divider in the accessibility reading order.")
        XCTAssertLessThanOrEqual(older.frame.maxY, allBoundary.frame.minY)
        let outsideID = "fixture-feed-ryan-added-juniper-list"
        let outsidePlace = app.buttons["feed.activity.\(outsideID).place"]
        reveal(outsidePlace, in: feed, direction: .down, app: app)
        XCTAssertTrue(outsidePlace.label.contains("Juniper Table"))
        let outsideCard = feed.descendants(matching: .any)["feed.activity.\(outsideID).postcard"].firstMatch
        XCTAssertTrue(outsideCard.exists)
        XCTAssertGreaterThanOrEqual(outsideCard.frame.minY, allBoundary.frame.maxY,
                                    "An outside-filter list addition belongs below its explicit disclosure.")
        assertFeedCount(2, in: app)
        XCTAssertEqual(drawer(in: app).value as? String, "1 activity. \(combinedSummary)",
                       "Broadening Feed discovery must not broaden the committed map count or filters.")
        for forbiddenID in ["fixture-feed-maya-been-bar-nido", "fixture-feed-maya-created-sunset-list",
                            "fixture-feed-demo-saved-fern-desk"] {
            XCTAssertFalse(feed.descendants(matching: .any)["feed.activity.\(forbiddenID).postcard"].firstMatch.exists,
                           "The all-activity tail must still exclude activity outside Only Friends.")
        }
        capture("combined-filter-authorized-unfiltered-tail")
        dragDrawer(.down, to: "half expanded", count: 1, in: app)

        openFilters(in: app)
        let cancelledForm = filterForm(in: app)
        resetFilters(in: app)
        selectMenu(app.buttons["live.filter.people"], option: "Everyone", form: cancelledForm, direction: .up, app: app, selected: {
            $0.identifier == "live.filter.people" && $0.value as? String == "Everyone"
        })
        app.navigationBars["Filters"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForNonExistence(timeout: 5))
        assertCombinedResult(in: app)
        capture("combined-filter-cancel-preserves-result")

        openFilters(in: app)
        let retainedForm = filterForm(in: app)
        captureState("filters-retained-before-assertions", in: app)
        XCTAssertEqual(app.buttons["live.filter.people"].value as? String, "Only Friends")
        XCTAssertTrue(retainedForm.buttons["Activity, Wannas"].exists)
        XCTAssertEqual(app.buttons["live.filter.time"].label, "When, Past 24 hours")
        reveal(app.buttons["live.filter.scope"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.buttons["live.filter.scope"].value as? String, "Nearby")
        reveal(app.buttons["live.filter.city"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.buttons["live.filter.city"].value as? String, "Los Angeles")
        reveal(app.buttons["25 km"], in: retainedForm, direction: .down, app: app)
        XCTAssertTrue(app.buttons["25 km"].isSelected)
        reveal(app.switches["live.filter.category.restaurants_food"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.switches["live.filter.category.restaurants_food"].value as? String, "1")
        reveal(app.switches["live.filter.person.user_ryan"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.switches["live.filter.person.user_ryan"].value as? String, "1")
        resetFilters(in: app)
        selectMenu(app.buttons["live.filter.people"], option: "Only Friends", form: retainedForm,
                   direction: .up, app: app, selected: {
            $0.identifier == "live.filter.people" && $0.value as? String == "Only Friends"
        })
        app.buttons["live.applyFilters"].tap()

        assertDrawer("half expanded", count: 2, in: app)
        XCTAssertEqual(summary(in: app).label, "All time")
        XCTAssertEqual(drawer(in: app).value as? String, "2 activities. Featured · All time · Only Friends")
        XCTAssertEqual(app.buttons["Filters"].value as? String, "1 active filters")
        assertPins(["place_noodles", "place_juniper_table"], in: app)
        dragDrawer(.up, to: "expanded", count: 2, in: app)
        assertFeedCount(2, in: app)
        let resetFeed = app.scrollViews["feed.places.scroll"]
        waitHittable(app.buttons["live.utility.invite"])
        reveal(app.staticTexts["Activity"].firstMatch, in: resetFeed, direction: .up, app: app)
        for (activityID, name) in [("fixture-feed-ryan-wanna-noodles", "Larchmont Noodles"),
                                   ("fixture-feed-ryan-added-juniper-list", "Juniper Table")] {
            let destination = app.buttons["feed.activity.\(activityID).place"]
            reveal(destination, in: resetFeed, direction: .down, app: app)
            XCTAssertTrue(destination.label.contains(name))
            XCTAssertTrue(resetFeed.descendants(matching: .any)["feed.activity.\(activityID).postcard"].firstMatch.exists)
            assertFeedCount(2, in: app)
            capture("combined-filter-reset-\(activityID)")
        }
        capture("combined-filter-reset-keeps-friends-audience")
    }

    private enum Direction { case up, down }

    private func launchLive() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture",
            "-WanderInitialTab", "discover",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        waitHittable(app.buttons["live.draw"], timeout: 20)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        return app
    }

    private func drawer(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["live.drawerHandle"]
    }

    private func summary(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["live.filter.summary"]
    }

    private func assertDrawer(_ state: String, count: Int, in app: XCUIApplication,
                              postInputCapture: String? = nil) {
        let loadedCount = count == 1 ? "1 activity." : "\(count) activities."
        // Read only the uniquely identified native drawer snapshot. Keep query
        // resolution inside the timed predicate; .element rejects ambiguity.
        let observationStart = ProcessInfo.processInfo.systemUptime
        let observationDeadline = observationStart + 5
        var evaluations = 0
        var matchingHandles = 0
        var matchingValues = 0
        var snapshotAvailable = false
        var snapshotStartedAt: TimeInterval?
        var snapshotFinishedAt: TimeInterval?
        func observeDrawer() -> Bool {
            guard ProcessInfo.processInfo.systemUptime <= observationDeadline else { return false }
            evaluations += 1
            matchingHandles = 0
            matchingValues = 0
            snapshotAvailable = false
            snapshotStartedAt = ProcessInfo.processInfo.systemUptime
            let handle = app.staticTexts.matching(
                NSPredicate(format: "identifier == %@", "live.drawerHandle")).element
            let snapshot = try? handle.snapshot()
            snapshotFinishedAt = ProcessInfo.processInfo.systemUptime
            guard let snapshot else { return false }
            snapshotAvailable = true
            if snapshot.elementType == .staticText && snapshot.identifier == "live.drawerHandle" {
                matchingHandles = 1
                if snapshot.label == "Activity drawer, \(state)"
                    && (snapshot.value as? String)?.hasPrefix(loadedCount) == true {
                    matchingValues = 1
                }
            }
            return matchingHandles == 1 && matchingValues == 1
                && ProcessInfo.processInfo.systemUptime <= observationDeadline
        }
        // Do not spend the first polling tick before observing a completed
        // native transition. All reads still share the original five seconds.
        let result: XCTWaiter.Result
        if observeDrawer() {
            result = .completed
        } else {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                observeDrawer()
            }, object: nil)
            let remaining = max(0, observationDeadline - ProcessInfo.processInfo.systemUptime)
            result = remaining > 0 ? XCTWaiter.wait(for: [expectation], timeout: remaining) : .timedOut
        }
        let snapshotElapsed = snapshotStartedAt.flatMap { start in snapshotFinishedAt.map { $0 - start } }
        let snapshotWithinDeadline = snapshotFinishedAt.map { $0 <= observationDeadline }
        let observation = XCTAttachment(string: "expectedState=\(state); expectedLoadedCount=\(loadedCount); evaluations=\(evaluations); snapshotAvailable=\(snapshotAvailable); matchingHandles=\(matchingHandles); matchingValues=\(matchingValues); querySnapshotElapsed=\(String(describing: snapshotElapsed)); snapshotWithinDeadline=\(String(describing: snapshotWithinDeadline)); elapsed=\(ProcessInfo.processInfo.systemUptime - observationStart); waitResult=\(result.rawValue)")
        observation.name = "REC-636-drawer-native-observation"
        observation.lifetime = .keepAlways
        add(observation)
        if let postInputCapture {
            captureState(postInputCapture, in: app, observations: [
                "expectedState=\(state); expectedLoadedCount=\(loadedCount); waitResult=\(result)",
                "postWaitSystemUptime=\(ProcessInfo.processInfo.systemUptime)"
            ])
        }
        XCTAssertEqual(result, .completed)
    }

    private func dragDrawer(_ direction: Direction, to state: String, count: Int, in app: XCUIApplication) {
        let handle = drawer(in: app)
        waitHittable(handle)
        // These checks traverse adjacent detents. A full-screen drag now
        // intentionally crosses the middle stop, so move one short native step.
        let distance: CGFloat = direction == .up ? -80 : 80
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        XCTAssertTrue(app.frame.contains(start.screenPoint) && app.frame.contains(end.screenPoint))
        captureState("drawer-before-native-drag", in: app, observations: [
            "expectedState=\(state); expectedLoadedCount=\(count); verticalTravel=\(distance)",
            "handleFrame=\(handle.frame); handleLabel=\(handle.label); handleValue=\(String(describing: handle.value)); handleHittable=\(handle.isHittable)",
            "preDragSystemUptime=\(ProcessInfo.processInfo.systemUptime)"
        ])
        // Use deliberate native input for the existing single drawer transition.
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        assertDrawer(state, count: count, in: app, postInputCapture: "drawer-after-native-drag")
    }

    private func assertTabs(in app: XCUIApplication) {
        for title in ["Live", "Lists", "Profile"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.exists && tab.isEnabled && tab.isHittable)
        }
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
    }

    private func assertMapControls(in app: XCUIApplication) {
        waitHittable(app.buttons["live.draw"])
        waitForEnabledFilters(in: app)
        waitHittable(app.buttons["Add a place"])
        XCTAssertTrue(app.maps.firstMatch.exists)
    }

    private func waitForEnabledFilters(in app: XCUIApplication) {
        // Keep enabled state in the unique exact native query so each timed
        // evaluation needs only the genuine native hit-point computation.
        let filters = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@ AND enabled == true",
            "slider.horizontal.3", "Filters")).element
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + 10
        var reads = 0
        var lastReadFinishedAt: TimeInterval?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            reads += 1
            let hittable = filters.isHittable
            lastReadFinishedAt = ProcessInfo.processInfo.systemUptime
            return hittable && ProcessInfo.processInfo.systemUptime <= deadline
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime))
        let observation = XCTAttachment(string: "reads=\(reads); elapsed=\(ProcessInfo.processInfo.systemUptime - startedAt); lastReadWithinDeadline=\(String(describing: lastReadFinishedAt.map { $0 <= deadline })); waitResult=\(result.rawValue)")
        observation.name = "REC-636-filters-native-hit-observation"
        observation.lifetime = .keepAlways
        add(observation)
        XCTAssertEqual(result, .completed)
    }

    private func assertCollapsedFeedDoesNotReceiveTouches(_ feed: XCUIElement) {
        // UIKit may retain a hidden hosting/scroll wrapper in the raw tree.
        // Test touch reachability; VoiceOver task completion is a separate gate.
        guard feed.exists else { return }
        XCTAssertFalse(feed.isHittable, "Collapsed Feed must not receive map or drawer touches.")
        for action in feed.buttons.allElementsBoundByIndex {
            XCTAssertFalse(action.isHittable, "Collapsed Feed action must not be hittable: \(action.identifier), \(action.label)")
        }
    }

    private func assertPins(_ placeIDs: Set<String>, in app: XCUIApplication) {
        let expected = Set(placeIDs.map { "live.pin.\($0)" })
        wait(NSPredicate { _, _ in
            let observed = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
                .allElementsBoundByIndex.map(\.identifier))
            return observed == expected
        })
    }

    private func assertFeedCount(_ count: Int, in app: XCUIApplication) {
        // Resolve presence and the exact count from one fresh native tree. Separate
        // XCUIElement existence/value queries can exhaust the observation budget
        // while resolving the same scroll view after the drawer changes size.
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 5
        var evaluations = 0
        var matchingScrollViews = 0
        var expectedValueMatches = 0
        var snapshotAvailable = false
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            evaluations += 1
            matchingScrollViews = 0
            expectedValueMatches = 0
            snapshotAvailable = false
            guard let snapshot = try? app.snapshot() else { return false }
            snapshotAvailable = true
            @MainActor
            func visit(_ node: XCUIElementSnapshot) {
                if node.elementType == .scrollView && node.identifier == "feed.places.scroll" {
                    matchingScrollViews += 1
                    if node.value as? String == "\(count) activities loaded" {
                        expectedValueMatches += 1
                    }
                }
                for child in node.children { visit(child) }
            }
            visit(snapshot)
            return matchingScrollViews == 1 && expectedValueMatches == 1
                && ProcessInfo.processInfo.systemUptime <= deadline
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let observation = XCTAttachment(string: "expectedCount=\(count); evaluations=\(evaluations); snapshotAvailable=\(snapshotAvailable); matchingScrollViews=\(matchingScrollViews); expectedValueMatches=\(expectedValueMatches); elapsed=\(elapsed); waitResult=\(result.rawValue)")
        observation.name = "REC-636-feed-count-native-observation"
        observation.lifetime = .keepAlways
        add(observation)
        XCTAssertEqual(result, .completed)
    }

    private func assertCombinedResult(in app: XCUIApplication, drawerState: String = "half expanded") {
        assertDrawer(drawerState, count: 1, in: app)
        XCTAssertEqual(summary(in: app).label, "Past 1 day")
        XCTAssertEqual(drawer(in: app).value as? String, "1 activity. \(combinedSummary)")
        XCTAssertEqual(app.buttons["Filters"].value as? String, "6 active filters")
        assertPins(["place_noodles"], in: app)
        let pin = app.buttons["live.pin.place_noodles"]
        XCTAssertTrue(pin.label.contains("Ryan"))
        XCTAssertTrue(pin.label.contains("Wanna"))
    }

    private func panMapOnce(anchorID: String, in app: XCUIApplication) {
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists)
        let controls = [app.buttons["live.draw"], app.buttons["Filters"], app.buttons["Add a place"]]
        let mapFrame = map.frame.intersection(app.frame)
        let top = max(mapFrame.minY, controls.map { $0.frame.maxY }.max()!) + 12
        let bottom = min(mapFrame.maxY, drawer(in: app).frame.minY) - 12
        let usable = CGRect(x: mapFrame.minX + 20, y: top, width: mapFrame.width - 40, height: bottom - top)
        XCTAssertTrue(finite(usable) && usable.width > 100 && usable.height > 88)
        let loadedPins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin.")).allElementsBoundByIndex
        let beforeFrames = loadedPins.map { (id: $0.identifier, frame: $0.frame) }
        XCTAssertTrue(!beforeFrames.isEmpty && beforeFrames.allSatisfy { finite($0.frame) })
        let pinBounds = beforeFrames.reduce(CGRect.null) { $0.union($1.frame) }
        // Keep the loaded markers inside the map: a fixed leftward pan can
        // remove the left-edge Wanna before its displacement can be observed.
        let movesRight = pinBounds.midX < usable.midX
        let start = CGPoint(x: usable.minX + usable.width * (movesRight ? 0.65 : 0.8), y: usable.maxY - 44)
        let end = CGPoint(x: usable.minX + usable.width * (movesRight ? 0.8 : 0.65), y: start.y)
        let path = CGRect(x: min(start.x, end.x), y: end.y - 6, width: abs(start.x - end.x), height: 12)
        XCTAssertTrue(usable.contains(start) && usable.contains(end))
        for pin in beforeFrames {
            XCTAssertFalse(pin.frame.intersects(path), "The one map pan must start and finish outside the loaded pin controls.")
        }
        let anchor = app.buttons["live.pin.\(anchorID)"]
        XCTAssertTrue(anchor.exists)
        let before = anchor.frame
        XCTAssertTrue(finite(before))
        let zero = app.coordinate(withNormalizedOffset: .zero)
        let beforeDiagnostic = XCTAttachment(string: "anchorID=\(anchorID); before=\(before); loadedFrames=\(beforeFrames); loadedBounds=\(pinBounds); usable=\(usable); start=\(start); end=\(end)")
        beforeDiagnostic.name = "REC-636-native-map-pan-before-geometry"
        beforeDiagnostic.lifetime = .keepAlways
        add(beforeDiagnostic)
        capture("native-pan-before")
        // Use deliberate native input for the existing single-pan displacement check.
        zero.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.1, thenDragTo: zero.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                   withVelocity: XCUIGestureVelocity(rawValue: 60), thenHoldForDuration: 0.1)
        let displacement = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard anchor.exists else { return false }
            let after = anchor.frame
            return self.finite(after) && abs(after.midX - before.midX) > 1
        }, object: nil)
        let result = XCTWaiter.wait(for: [displacement], timeout: 5)
        let afterFrames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex.map { (id: $0.identifier, frame: $0.frame) }
        let diagnostic = XCTAttachment(string: "anchorID=\(anchorID); before=\(before); anchorExists=\(anchor.exists); loadedFrames=\(afterFrames); usable=\(usable); start=\(start); end=\(end); displacementResult=\(result)")
        diagnostic.name = "REC-636-native-map-pan-geometry"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        capture("native-pan-after")
        XCTAssertEqual(result, .completed)
    }

    private enum FilterHitEdge: String { case leading, trailing }

    private func openFilters(in app: XCUIApplication, pressAtEdge edge: FilterHitEdge? = nil) {
        let button = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@ AND enabled == true",
            "slider.horizontal.3", "Filters")).element
        let applicationFrame = app.frame
        var previousFrame = CGRect.null
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + 10
        var stableSince = startedAt
        var observations = 0
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            observations += 1
            // Resolve enabled state and geometry together. Separate queries for
            // each property can consume the entire native observation deadline.
            guard let snapshot = try? button.snapshot(), snapshot.isEnabled,
                  ProcessInfo.processInfo.systemUptime <= deadline,
                  self.finite(snapshot.frame), applicationFrame.contains(snapshot.frame),
                  button.isHittable,
                  ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            let frame = snapshot.frame
            if frame != previousFrame {
                previousFrame = frame
                stableSince = ProcessInfo.processInfo.systemUptime
                return false
            }
            return ProcessInfo.processInfo.systemUptime - stableSince >= 0.5
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime))
        let observation = XCTAttachment(string: "observations=\(observations); elapsed=\(ProcessInfo.processInfo.systemUptime - startedAt); verifiedFrame=\(previousFrame); applicationFrame=\(applicationFrame); requiredStableSeconds=0.5; waitResult=\(result.rawValue)")
        observation.name = "REC-636-filters-open-native-observation"
        observation.lifetime = .keepAlways
        add(observation)
        XCTAssertEqual(result, .completed)
        if let edge {
            XCTAssertGreaterThanOrEqual(previousFrame.width, 44)
            XCTAssertGreaterThanOrEqual(previousFrame.height, 44)
            let point = CGPoint(x: edge == .leading ? previousFrame.minX + 2 : previousFrame.maxX - 2,
                                y: previousFrame.midY)
            XCTAssertTrue(previousFrame.contains(point))
            XCTAssertTrue(applicationFrame.contains(point))
            let contact = XCTAttachment(string: "edge=\(edge.rawValue); verifiedFrame=\(previousFrame); contact=\(point); insetPoints=2; pressDuration=0.1; maximumPressCount=1")
            contact.name = "REC-675-filters-minimum-hit-target"
            contact.lifetime = .keepAlways
            add(contact)
            // Exercise the empty padding inside the same verified 44pt label.
            // One physical press per fresh launch; no activation fallback.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - applicationFrame.minX, dy: point.y - applicationFrame.minY))
                .press(forDuration: 0.1)
        } else {
            button.press(forDuration: 0.1)
        }
        XCTAssertTrue(app.descendants(matching: .any)["live.filters.form"].firstMatch.waitForExistence(timeout: 5))
    }

    private func filterForm(in app: XCUIApplication) -> XCUIElement {
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        return form
    }

    private func selectMenu(_ picker: XCUIElement, option: String, form: XCUIElement,
                            direction: Direction = .down, app: XCUIApplication,
                            selected: @escaping (XCUIElementSnapshot) -> Bool) {
        reveal(picker, in: form, direction: direction, app: app)
        let semanticTitle: String?
        switch picker.identifier {
        case "live.filter.people": semanticTitle = "People"
        case "live.filter.scope": semanticTitle = "Scope"
        default: semanticTitle = nil
        }
        let semanticOptionID = semanticTitle.map { "live.filter.option.\($0).\(option)" }
        picker.tap()
        // Colored People/Scope options are native popover buttons with stable
        // identifiers. Activity/When remain native Picker collection options.
        // Both queries avoid the identically labeled Nearby header button.
        let choice: XCUIElement
        if let semanticOptionID {
            choice = app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND enabled == true", semanticOptionID)).element
        } else {
            choice = app.collectionViews.buttons.matching(NSPredicate(
                format: "label == %@ AND enabled == true", option)).element
        }
        waitForEnabledPopupChoice(choice, diagnosticFailure: {
            // Observe the failed wait once, before its original assertion aborts
            // the test. These reads neither retry the tap nor extend its gate.
            self.capture("popup-option-wait-failed")
            var observations = ["option=\(option)", "postFailureSnapshotRequestedUptime=\(ProcessInfo.processInfo.systemUptime)"]
            do {
                let snapshot = try app.snapshot()
                var choiceCount = 0
                @MainActor
                func visit(_ node: XCUIElementSnapshot, inCollection: Bool) {
                    let collection = inCollection || node.elementType == .collectionView
                    if node.elementType == .button
                        && (semanticOptionID.map { node.identifier == $0 } ?? (collection && node.label == option)) {
                        choiceCount += 1
                    }
                    for child in node.children { visit(child, inCollection: collection) }
                }
                visit(snapshot, inCollection: false)
                observations.append("choiceCountFromPostFailureSnapshot=\(choiceCount)")
                let hierarchy = XCTAttachment(string: String(describing: snapshot.dictionaryRepresentation))
                hierarchy.name = "REC-636-popup-option-wait-failed-snapshot"
                hierarchy.lifetime = .keepAlways
                self.add(hierarchy)
            } catch {
                observations.append("choiceCountFromPostFailureSnapshot=unavailable")
                observations.append("postFailureAppSnapshotError=\(String(describing: error))")
            }
            observations.append("postFailureSnapshotFinishedUptime=\(ProcessInfo.processInfo.systemUptime)")
            let diagnostic = XCTAttachment(string: observations.joined(separator: "\n"))
            diagnostic.name = "REC-636-popup-option-wait-failed-observations"
            diagnostic.lifetime = .keepAlways
            self.add(diagnostic)
        })
        choice.tap()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        wait(NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline,
                  let snapshot = try? app.snapshot() else { return false }
            // Resolve once, then observe popup absence and the exact selected
            // field in the same native tree within the original five seconds.
            var popupChoicePresent = false
            var selectedPickerCount = 0
            @MainActor
            func visit(_ node: XCUIElementSnapshot, inCollection: Bool, inForm: Bool) {
                let collection = inCollection || node.elementType == .collectionView
                let form = inForm || node.identifier == "live.filters.form"
                if node.elementType == .button {
                    if semanticOptionID.map({ node.identifier == $0 }) ?? (collection && node.label == option) {
                        popupChoicePresent = true
                    }
                    if form && selected(node) { selectedPickerCount += 1 }
                }
                for child in node.children { visit(child, inCollection: collection, inForm: form) }
            }
            visit(snapshot, inCollection: false, inForm: false)
            return !popupChoicePresent && selectedPickerCount == 1
                && ProcessInfo.processInfo.systemUptime <= deadline
        })
    }

    private func resetFilters(in app: XCUIApplication) {
        let form = app.collectionViews.matching(NSPredicate(format: "identifier == %@", "live.filters.form")).element
        let navigation = app.navigationBars.matching(NSPredicate(format: "identifier == %@", "Filters")).element
        let cancel = navigation.buttons.matching(NSPredicate(format: "label == %@", "Cancel")).element
        let apply = navigation.buttons.matching(NSPredicate(format: "identifier == %@", "live.applyFilters")).element

        @MainActor
        func readTarget() -> (app: CGRect, form: CGRect, navigation: CGRect, viewport: CGRect, button: CGRect?)? {
            let appFrame = app.frame
            var capturedForm: XCUIElementSnapshot?
            var capturedNavigation: XCUIElementSnapshot?
            var failedPredicate = "none"
            var snapshotErrorCategory = "none"

            @MainActor
            func readSnapshot(_ element: XCUIElement, name: String,
                              into captured: inout XCUIElementSnapshot?) -> XCUIElementSnapshot? {
                do {
                    captured = try element.snapshot()
                    return captured
                } catch {
                    failedPredicate = "\(name).snapshot"
                    let nativeError = error as NSError
                    snapshotErrorCategory = "domain=\(nativeError.domain); code=\(nativeError.code)"
                    return nil
                }
            }

            func checked(_ condition: Bool, _ name: String) -> Bool {
                if !condition { failedPredicate = name }
                return condition
            }

            // Permit only two representable boundary steps for container-frame
            // arithmetic; the usable viewport below stays clipped to the app.
            let containerRoundingTolerance = max(max(appFrame.minX.ulp, appFrame.maxX.ulp),
                                                 max(appFrame.minY.ulp, appFrame.maxY.ulp)) * 2
            guard let formSnapshot = readSnapshot(form, name: "form", into: &capturedForm),
                  let navigationSnapshot = readSnapshot(navigation, name: "navigation", into: &capturedNavigation),
                  checked(formSnapshot.elementType == .collectionView, "form.type"),
                  checked(formSnapshot.identifier == "live.filters.form", "form.identifier"),
                  checked(navigationSnapshot.elementType == .navigationBar, "navigation.type"),
                  checked(navigationSnapshot.identifier == "Filters", "navigation.identifier"),
                  checked(formSnapshot.isEnabled, "form.enabled"),
                  checked(navigationSnapshot.isEnabled, "navigation.enabled"),
                  checked(finite(appFrame), "app.finiteFrame"),
                  checked(finite(formSnapshot.frame), "form.finiteFrame"),
                  checked(finite(navigationSnapshot.frame), "navigation.finiteFrame"),
                  checked(appFrame.insetBy(dx: -containerRoundingTolerance, dy: -containerRoundingTolerance)
                    .contains(formSnapshot.frame), "app.containsForm"),
                  checked(appFrame.contains(navigationSnapshot.frame), "app.containsNavigation"),
                  checked(app.alerts.count == 0, "app.noAlerts"),
                  checked(cancel.isHittable, "cancel.hittable"),
                  checked(apply.isHittable, "apply.hittable") else {
                // Retain only the values already read by this failed guard.
                // Do not query the live app again while diagnosing the failure.
                var observations = ["failedPredicate=\(failedPredicate)",
                                    "snapshotErrorCategory=\(snapshotErrorCategory)",
                                    "appFrame=\(appFrame)"]
                for (name, snapshot) in [("form", capturedForm), ("navigation", capturedNavigation)] {
                    if let snapshot {
                        observations.append("\(name).type=\(snapshot.elementType.rawValue); identifier=\(snapshot.identifier); enabled=\(snapshot.isEnabled); frame=\(snapshot.frame)")
                    } else {
                        observations.append("\(name).snapshot=notReadOrUnavailable")
                    }
                }
                let diagnostic = XCTAttachment(string: observations.joined(separator: "\n"))
                diagnostic.name = "REC-636-reset-foreground-guard-failure"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
                XCTFail("Expected the unique foreground Filters sheet before Reset input")
                return nil
            }
            let sheetFrame = formSnapshot.frame.intersection(appFrame)
            let top = max(sheetFrame.minY + 8, navigationSnapshot.frame.maxY + 8)
            let tabs = app.tabBars.firstMatch
            let bottom = min(sheetFrame.maxY - 8,
                             tabs.exists && tabs.isHittable ? tabs.frame.minY - 8 : sheetFrame.maxY - 8)
            let viewport = CGRect(x: sheetFrame.minX + 12, y: top,
                                  width: sheetFrame.width - 24, height: max(0, bottom - top))
            guard finite(viewport), viewport.width > 44, viewport.height > 88 else {
                XCTFail("Expected usable Filters content below its navigation bar")
                return nil
            }
            var matches: [XCUIElementSnapshot] = []
            @MainActor
            func visit(_ node: XCUIElementSnapshot) {
                if node.elementType == .button && node.identifier == "live.filter.reset" { matches.append(node) }
                for child in node.children { visit(child) }
            }
            visit(formSnapshot)
            guard matches.count <= 1 else {
                XCTFail("Expected at most one exact Reset button inside the Filters form")
                return nil
            }
            let target = matches.first
            if let target, !target.isEnabled {
                XCTFail("Expected the exact Reset button to be enabled")
                return nil
            }
            return (appFrame, formSnapshot.frame, navigationSnapshot.frame, viewport, target?.frame)
        }

        for attempt in 0...16 {
            guard let observed = readTarget() else { return }
            if let frame = observed.button, finite(frame), observed.viewport.contains(frame) {
                // Reset can expose its full enabled row while XCTest cannot
                // obtain a native activation point. Confirm fresh sheet and
                // target geometry before one physical center press.
                guard let confirmed = readTarget(), let confirmedFrame = confirmed.button,
                      confirmed.app == observed.app, confirmed.form == observed.form,
                      confirmed.navigation == observed.navigation, confirmed.viewport == observed.viewport,
                      confirmedFrame == frame, finite(confirmedFrame),
                      confirmed.viewport.contains(confirmedFrame) else {
                    XCTFail("Expected stable fully visible Reset geometry before its one press")
                    return
                }
                let contact = CGPoint(x: confirmedFrame.midX, y: confirmedFrame.midY)
                let diagnostic = XCTAttachment(string: "targetID=live.filter.reset; targetFrame=\(confirmedFrame); viewport=\(confirmed.viewport); sheetFrame=\(confirmed.form); navigationFrame=\(confirmed.navigation); appFrame=\(confirmed.app); contact=\(contact); uniqueEnabledButton=true; geometryConfirmed=true; nativeResetHittabilityQueried=false; pressDuration=0.2")
                diagnostic.name = "REC-636-reset-filter-physical-target"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: contact.x - confirmed.app.minX,
                                           dy: contact.y - confirmed.app.minY)).press(forDuration: 0.2)
                return
            }
            // Reset is the first Form section. If it was virtualized after
            // inspecting lower filters, reveal toward the top; a known frame
            // still chooses the direction that brings that exact row into view.
            guard attempt < 16 else { break }
            let dragDown = observed.button.map { $0.minY < observed.viewport.minY } ?? true
            let from = CGPoint(x: observed.form.maxX - 8,
                               y: observed.viewport.minY + observed.viewport.height * (dragDown ? 0.45 : 0.75))
            let to = CGPoint(x: from.x,
                             y: observed.viewport.minY + observed.viewport.height * (dragDown ? 0.75 : 0.45))
            XCTAssertTrue(observed.form.contains(from) && observed.form.contains(to))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: from.x - observed.app.minX, dy: from.y - observed.app.minY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(
                    CGVector(dx: to.x - observed.app.minX, dy: to.y - observed.app.minY)))
        }
        captureState("reset-filter-target-unreachable", in: app)
        XCTFail("Expected the exact enabled Reset button fully inside the foreground Filters content")
    }

    private func setOn(_ toggle: XCUIElement, in form: XCUIElement, app: XCUIApplication) {
        reveal(toggle, in: form, direction: .down, app: app)
        XCTAssertEqual(toggle.value as? String, "0")
        // SwiftUI exposes the labeled row as a Switch with a native switch
        // descendant. The row's center can fall outside the actual control.
        let nativeSwitches = toggle.switches.allElementsBoundByIndex
        guard nativeSwitches.count == 1, let nativeSwitch = nativeSwitches.first else {
            XCTFail("Expected one native switch inside the exact filter row")
            return
        }
        let rowFrame = toggle.frame
        let nativeFrame = nativeSwitch.frame
        let nativeEnabled = nativeSwitch.isEnabled
        let nativeHittable = nativeSwitch.isHittable
        let viewport = usableViewport(form, app: app)
        let nativeCenter = CGPoint(x: nativeFrame.midX, y: nativeFrame.midY)
        let diagnostic = XCTAttachment(string: "rowID=\(toggle.identifier); rowFrame=\(rowFrame); nativeSwitchFrame=\(nativeFrame); nativeEnabled=\(nativeEnabled); nativeHittable=\(nativeHittable); rowValueBefore=\(String(describing: toggle.value))")
        diagnostic.name = "REC-636-filter-native-switch-target"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        // Native switch bounds can extend beyond SwiftUI's labeled row by a
        // few points. Keep its center in this exact row and the entire native
        // control in the visible form instead of comparing their outer edges.
        guard finite(rowFrame), finite(nativeFrame), finite(viewport),
              rowFrame.contains(nativeCenter), viewport.contains(nativeFrame),
              nativeEnabled, nativeHittable else {
            captureState("filter-native-switch-geometry", in: app)
            XCTFail("Expected the native filter switch inside the visible row")
            return
        }
        nativeSwitch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, direction: Direction, app: XCUIApplication) {
        for _ in 0..<16 {
            let viewport = usableViewport(scroll, app: app)
            if element.exists && finite(element.frame) && viewport.contains(element.frame) && element.isHittable { return }
            XCTAssertTrue(finite(viewport) && viewport.width > 44 && viewport.height > 88)
            let fromY: CGFloat = direction == .down ? 0.75 : 0.45
            let toY: CGFloat = direction == .down ? 0.45 : 0.75
            let zero = app.coordinate(withNormalizedOffset: .zero)
            let scrollFrame = scroll.frame.intersection(app.frame)
            let from = CGPoint(x: scrollFrame.maxX - 8, y: viewport.minY + viewport.height * fromY)
            let to = CGPoint(x: from.x, y: viewport.minY + viewport.height * toY)
            XCTAssertTrue(scrollFrame.contains(from) && scrollFrame.contains(to))
            zero.withOffset(CGVector(dx: from.x - app.frame.minX, dy: from.y - app.frame.minY))
                .press(forDuration: 0.1, thenDragTo: zero.withOffset(CGVector(dx: to.x - app.frame.minX, dy: to.y - app.frame.minY)))
        }
        capture("bounded-scroll-target-unreachable")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "REC-636-bounded-scroll-target-unreachable-hierarchy"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(element.exists && finite(element.frame) && usableViewport(scroll, app: app).contains(element.frame) && element.isHittable)
    }

    private func usableViewport(_ scroll: XCUIElement, app: XCUIApplication) -> CGRect {
        let frame = scroll.frame.intersection(app.frame)
        let navigation = app.navigationBars.firstMatch
        let top = max(frame.minY + 8, navigation.exists ? navigation.frame.maxY + 8 : frame.minY + 8)
        let tabs = app.tabBars.firstMatch
        let bottom = min(frame.maxY - 8, tabs.exists && tabs.isHittable ? tabs.frame.minY - 8 : frame.maxY - 8)
        return CGRect(x: frame.minX + 12, y: top, width: frame.width - 24, height: max(0, bottom - top))
    }

    private func finite(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
    }

    private func waitForEnabledPopupChoice(_ choice: XCUIElement, diagnosticFailure: () -> Void) {
        // The unique popup query already requires enabled == true. Resolve its
        // genuine native hit point once per poll, without a separate snapshot.
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + 10
        var pollCount = 0
        var totalReadSeconds: TimeInterval = 0
        var maximumReadSeconds: TimeInterval = 0
        var lateHitCount = 0
        var lastHittable = false
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            pollCount += 1
            let readStartedAt = ProcessInfo.processInfo.systemUptime
            let hittable = choice.isHittable
            let readFinishedAt = ProcessInfo.processInfo.systemUptime
            let readSeconds = readFinishedAt - readStartedAt
            totalReadSeconds += readSeconds
            maximumReadSeconds = max(maximumReadSeconds, readSeconds)
            lastHittable = hittable
            if hittable && readFinishedAt > deadline { lateHitCount += 1 }
            return hittable && readFinishedAt <= deadline
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            let observation = XCTAttachment(string: "pollCount=\(pollCount); totalNativeReadMS=\(totalReadSeconds * 1_000); maximumNativeReadMS=\(maximumReadSeconds * 1_000); lastHittable=\(lastHittable); hittableReturnedAfterDeadlineCount=\(lateHitCount); elapsedMS=\((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000); waitResult=\(result.rawValue)")
            observation.name = "REC-675-popup-native-hit-observation"
            observation.lifetime = .keepAlways
            add(observation)
            diagnosticFailure()
        }
        XCTAssertEqual(result, .completed)
    }

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10,
                              diagnosticFailure: ((Error?) -> Void)? = nil) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var lastSnapshotError: Error?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // A successful snapshot resolves existence and enabled state together;
            // hittability still comes from the genuine native element query.
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            let snapshot: XCUIElementSnapshot
            do {
                snapshot = try element.snapshot()
            } catch {
                lastSnapshotError = error
                return false
            }
            guard snapshot.isEnabled,
                  ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            let hittable = element.isHittable
            return hittable && ProcessInfo.processInfo.systemUptime <= deadline
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed { diagnosticFailure?(lastSnapshotError) }
        XCTAssertEqual(result, .completed)
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement? = nil, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func revealNativeCityOption(_ name: String, in app: XCUIApplication)
        -> (element: XCUIElement, frame: CGRect, viewport: CGRect)? {
        let navigation = app.navigationBars["Area center"]
        guard navigation.waitForExistence(timeout: 5) else {
            captureCityPickerState("city-picker-route-missing", in: app, observations: [])
            XCTFail("Expected the native Area center picker before choosing a city")
            return nil
        }
        captureCityPickerState("city-picker-after-tap", in: app, observations: [])
        for attempt in 0...16 {
            guard navigation.exists else {
                captureCityPickerState("city-picker-route-lost", in: app, observations: [])
                XCTFail("City option reveal must remain in the native Area center picker")
                return nil
            }
            // Navigation can retain the offscreen Filters form. Use the unique
            // native list with a finite on-screen viewport. Its container may
            // be non-hittable; require the city button itself to be hittable.
            let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            let activeLists = lists.filter { list in
                guard list.exists else { return false }
                let visible = list.frame.intersection(app.frame)
                return finite(visible) && visible.width >= 44 && visible.height > 88
            }
            guard activeLists.count == 1 else {
                captureCityPickerState("city-picker-list-unresolved", in: app,
                    observations: ["activeListCount=\(activeLists.count); attempt=\(attempt + 1)"])
                XCTFail("Expected one active native city list")
                return nil
            }
            let list = activeLists[0]
            let listFrame = list.frame.intersection(app.frame)
            let top = max(listFrame.minY + 8, navigation.frame.maxY + 8)
            let bottom = listFrame.maxY - 8
            let viewport = CGRect(x: listFrame.minX, y: top, width: listFrame.width, height: max(0, bottom - top))
            guard finite(viewport), viewport.width >= 44, viewport.height > 88 else {
                captureCityPickerState("city-picker-viewport-invalid", in: app,
                    observations: ["viewport=\(viewport); attempt=\(attempt + 1)"])
                XCTFail("Expected usable native city-list content below its navigation bar")
                return nil
            }
            let option = list.buttons.matching(NSPredicate(format: "label == %@", name)).element
            let exists = option.exists
            let frame = exists ? option.frame : CGRect.null
            let finiteTarget = finite(frame)
            let enabled = exists && option.isEnabled
            let hittable = exists && option.isHittable
            if finiteTarget, viewport.contains(frame), enabled, hittable { return (option, frame, viewport) }
            // Observe the final drag's outcome without sending a seventeenth.
            guard attempt < 16 else { break }
            let dragDown = finiteTarget && frame.minY < viewport.minY
            let maximumDistance = viewport.height * 0.27
            let overflow = finiteTarget
                ? (dragDown ? max(0, viewport.minY - frame.minY) : max(0, frame.maxY - viewport.maxY))
                : maximumDistance
            let distance = min(maximumDistance, overflow + (finiteTarget ? frame.height / 2 : 0))
            let x = viewport.maxX - 8
            let startY = viewport.minY + viewport.height * (dragDown ? 0.48 : 0.75)
            let endY = startY + (dragDown ? distance : -distance)
            let diagnostic = XCTAttachment(string: "attempt=\(attempt + 1); city=\(name); exists=\(exists); targetFrame=\(frame); hittable=\(hittable); viewport=\(viewport); direction=\(dragDown ? "down" : "up"); distance=\(distance); contactX=\(x); startY=\(startY); endY=\(endY)")
            diagnostic.name = "REC-636-native-city-reveal-gesture-\(attempt + 1)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        captureCityPickerState("city-option-unreachable", in: app, observations: ["city=\(name); maxGestures=16"])
        XCTFail("Expected the explicit city option inside the active native picker viewport")
        return nil
    }

    private func captureCityPickerState(_ name: String, in app: XCUIApplication, observations: [String]) {
        var state = observations + ["sampleRequestedSystemUptime=\(ProcessInfo.processInfo.systemUptime)"]
        let queries: [(String, XCUIElementQuery)] = [
            ("navigation-bars", app.navigationBars),
            ("collection-views", app.collectionViews),
            ("tables", app.tables),
            ("Los-Angeles-any-type", app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Los Angeles")))
        ]
        for (kind, query) in queries {
            let matches = query.allElementsBoundByIndex
            state.append("query=\(kind); count=\(matches.count)")
            for element in matches.prefix(8) {
                guard element.exists else {
                    state.append("query=\(kind); match-disappeared-before-attribute-sample")
                    continue
                }
                state.append("type=\(element.elementType.rawValue); id=\(element.identifier); label=\(element.label); frame=\(element.frame); enabled=\(element.isEnabled); hittable=\(element.isHittable)")
            }
        }
        state.append("hierarchyRequestedSystemUptime=\(ProcessInfo.processInfo.systemUptime)")
        captureState(name, in: app, observations: state)
    }

    private func captureState(_ name: String, in app: XCUIApplication, observations: [String] = []) {
        let hierarchy = app.debugDescription
        capture(name)
        let attachment = XCTAttachment(string: (observations + [hierarchy]).joined(separator: "\n"))
        attachment.name = "REC-636-drawer-filter-\(name)-full-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-636-drawer-filter-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
