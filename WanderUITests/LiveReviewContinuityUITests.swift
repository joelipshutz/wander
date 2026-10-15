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
        let pin = app.buttons["live.pin.place_noodles"]
        waitHittable(pin)
        XCTAssertTrue(pin.label.contains("Ryan"))
        XCTAssertTrue(pin.label.contains("Wanna"))
        pin.tap()
        let time = app.staticTexts["live.activityTime.fixture-feed-ryan-wanna-noodles"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        XCTAssertEqual(time.label, "5h ago")
        let show = app.buttons["Show in Feed"].firstMatch
        captureRouteDiagnostics("pin-selected-before-show-wait", in: app, startedAt: diagnosticStart,
            queries: [("exact-Show-in-Feed-label", app.buttons.matching(NSPredicate(format: "label == %@", "Show in Feed"))),
                      ("selected-card-scroll-containing-time", app.scrollViews.containing(.staticText,
                          identifier: "live.activityTime.fixture-feed-ryan-wanna-noodles"))])
        let selectedCardScroll = app.scrollViews.containing(.staticText,
            identifier: "live.activityTime.fixture-feed-ryan-wanna-noodles").firstMatch
        reveal(show, in: selectedCardScroll, app: app)
        waitHittable(show)
        show.tap()
        waitDrawer("expanded", in: app)

        let feed = app.scrollViews["feed.places.scroll"]
        let card = app.descendants(matching: .any)["feed.activity.fixture-feed-ryan-wanna-noodles.postcard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        waitForFocusedCardIntersection(card, in: feed, app: app)
        let actor = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"]
        XCTAssertTrue(actor.label.contains("Ryan"))
        let destination = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        XCTAssertTrue(destination.label.contains("Larchmont Noodles"))
        let comments = card.buttons["Open comments"]
        reveal(comments, in: feed, app: app)
        comments.tap()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["comments.activity.actor"].label.contains("Ryan"))
        XCTAssertTrue(app.buttons["comments.activity.place"].label.contains("Larchmont Noodles"))
        capture("original-wanna-activity-from-pin")
        tapNavigationBack(app.navigationBars.firstMatch)
        XCTAssertTrue(send.waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        collapseDrawerToHalf(in: app)
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        let open = app.buttons.matching(NSPredicate(format: "label == %@", "Open")).firstMatch
        waitHittable(open)
        open.tap()
        let placeBack = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBack.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Larchmont Noodles"].firstMatch.waitForExistence(timeout: 5))
        capture("original-place-from-pin")
        placeBack.tap()
        XCTAssertTrue(placeBack.waitForNonExistence(timeout: 5))
        waitDrawer("expanded", in: app)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    func testEmbeddedFeedKeepsInvitePeopleActivityOrderAndProfileReturn() {
        let app = launchLive()
        expandDrawer(in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let invite = app.buttons["invite people to Astir"]
        let people = app.staticTexts["People worth following"].firstMatch
        let activity = app.staticTexts.matching(NSPredicate(format: "label == %@", "Activity")).firstMatch
        reveal(people, in: feed, app: app)
        XCTAssertTrue(physicallyVisible(invite, in: feed, app: app))
        XCTAssertLessThan(invite.frame.maxY, people.frame.minY)
        capture("embedded-invite-before-people")
        reveal(activity, in: feed, app: app)
        XCTAssertTrue(physicallyVisible(people, in: feed, app: app))
        XCTAssertLessThan(people.frame.maxY, activity.frame.minY)
        capture("embedded-people-before-activity")

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
        waitHittable(searchBack)
        searchBack.tap()
        XCTAssertTrue(searchBack.waitForNonExistence(timeout: 5))
        waitDrawer("expanded", in: app)

        collapseDrawerToHalf(in: app)
        app.buttons["Notifications"].tap()
        let inbox = app.navigationBars["Notifications"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        capture("notifications-from-live")
        tapNavigationBack(inbox)
        XCTAssertTrue(inbox.waitForNonExistence(timeout: 5))
        waitDrawer("expanded", in: app)

        collapseDrawerToHalf(in: app)
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

    private func expandDrawer(in app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        waitHittable(handle)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        waitDrawer("expanded", in: app)
    }

    private func collapseDrawerToHalf(in app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        waitHittable(handle)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        waitDrawer("half expanded", in: app)
        waitHittable(app.buttons["live.draw"])
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

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<10 {
            if physicallyVisible(element, in: scroll, app: app) { return }
            // Short vertical drags at the trailing edge avoid the horizontal
            // recommendation rail, native map and bottom tab targets.
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.48)))
        }
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
/// Keep its existing four-case class byte-for-byte; append this separate class.
@MainActor
final class LiveDrawerAndFilterUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let allPlaceIDs: Set<String> = [
        "place_bar_nido", "place_noodles", "place_juniper_table", "place_fern_desk_coffee"
    ]
    private let combinedSummary = "25 km · Los Angeles · Past 24 hours · Wannas · 1 category · 1 person · Only Friends"

    func testEveryDrawerDetentAndNativeMapPanKeepTheLoadedActivity() {
        let app = launchLive()
        assertDrawer("half expanded", count: 5, in: app)
        assertTabs(in: app)
        assertPins(allPlaceIDs, in: app)
        assertMapControls(in: app)
        capture("drawer-initial-half")

        dragDrawer(.up, to: "expanded", count: 5, in: app)
        assertTabs(in: app)
        XCTAssertFalse(app.buttons["live.draw"].exists)
        assertFeedCount(5, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let actor = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        reveal(actor, in: feed, direction: .down, app: app)
        XCTAssertTrue(actor.label.contains("Maya"))
        capture("drawer-expanded-existing-feed")

        dragDrawer(.down, to: "half expanded", count: 5, in: app)
        assertMapControls(in: app)
        dragDrawer(.down, to: "collapsed", count: 5, in: app)
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
        assertDrawer("collapsed", count: 5, in: app)
        assertPins(allPlaceIDs, in: app)
        assertCollapsedFeedDoesNotReceiveTouches(feed)
        capture("drawer-collapsed-after-native-pan")

        dragDrawer(.up, to: "half expanded", count: 5, in: app)
        assertTabs(in: app)
        assertMapControls(in: app)
        XCTAssertEqual(app.buttons["Filters"].value as? String, "0 active filters")
        XCTAssertEqual(summary(in: app).label, "Following · Past 7 days")
        assertFeedCount(5, in: app)
        capture("drawer-half-after-pan-and-return")
    }

    func testCombinedFiltersApplyCancelAndResetKeepMapAndFeedInAgreement() {
        let app = launchLive()
        app.buttons["Filters"].tap()
        let form = filterForm(in: app)
        captureState("filters-initial-before-controls", in: app)
        selectMenu(app.buttons["live.filter.people"], option: "Only Friends", form: form, app: app)
        selectMenu(form.buttons["Activity, Everything"], option: "Wannas", form: form, app: app)
        selectMenu(app.buttons["live.filter.time"], option: "Past 24 hours", form: form, app: app)
        selectMenu(app.buttons["live.filter.scope"], option: "Nearby", form: form, app: app)
        let city = app.buttons["live.filter.city"]
        reveal(city, in: form, direction: .down, app: app)
        city.tap()
        let losAngeles = app.buttons["Los Angeles"]
        waitHittable(losAngeles)
        losAngeles.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        reveal(app.buttons["25 km"], in: form, direction: .down, app: app)
        app.buttons["25 km"].tap()
        setOn(app.switches["live.filter.category.restaurants_food"], in: form, app: app)
        setOn(app.switches["live.filter.person.user_ryan"], in: form, app: app)
        capture("combined-filter-draft")
        app.buttons["live.applyFilters"].tap()

        assertCombinedResult(in: app)
        panMapOnce(anchorID: "place_noodles", in: app)
        assertCombinedResult(in: app)
        dragDrawer(.up, to: "expanded", count: 1, in: app)
        assertFeedCount(1, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let actor = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.actor"]
        let place = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        reveal(place, in: feed, direction: .down, app: app)
        XCTAssertTrue(place.label.contains("Larchmont Noodles"))
        reveal(actor, in: feed, direction: .down, app: app)
        XCTAssertTrue(actor.label.contains("Ryan"))
        let observedCards = feed.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "feed.activity.", ".postcard"))
        XCTAssertEqual(observedCards.allElementsBoundByIndex.map(\.identifier),
                       ["feed.activity.fixture-feed-ryan-wanna-noodles.postcard"])
        capture("combined-filter-only-wanna-in-feed")
        dragDrawer(.down, to: "half expanded", count: 1, in: app)

        app.buttons["Filters"].tap()
        let cancelledForm = filterForm(in: app)
        reveal(app.buttons["live.filter.reset"], in: cancelledForm, direction: .down, app: app)
        app.buttons["live.filter.reset"].tap()
        selectMenu(app.buttons["live.filter.people"], option: "Everyone", form: cancelledForm, direction: .up, app: app)
        app.navigationBars["Filters"].buttons["Cancel"].tap()
        assertCombinedResult(in: app)
        capture("combined-filter-cancel-preserves-result")

        app.buttons["Filters"].tap()
        let retainedForm = filterForm(in: app)
        captureState("filters-retained-before-assertions", in: app)
        XCTAssertEqual(app.buttons["live.filter.people"].value as? String, "Only Friends")
        XCTAssertTrue(retainedForm.buttons["Activity, Wannas"].exists)
        XCTAssertEqual(app.buttons["live.filter.time"].label, "When, Past 24 hours")
        reveal(app.buttons["live.filter.scope"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.buttons["live.filter.scope"].label, "Scope, Nearby")
        reveal(app.buttons["live.filter.city"], in: retainedForm, direction: .down, app: app)
        XCTAssertTrue(app.buttons["live.filter.city"].label.contains("Los Angeles"))
        reveal(app.buttons["25 km"], in: retainedForm, direction: .down, app: app)
        XCTAssertTrue(app.buttons["25 km"].isSelected)
        reveal(app.switches["live.filter.category.restaurants_food"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.switches["live.filter.category.restaurants_food"].value as? String, "1")
        reveal(app.switches["live.filter.person.user_ryan"], in: retainedForm, direction: .down, app: app)
        XCTAssertEqual(app.switches["live.filter.person.user_ryan"].value as? String, "1")
        reveal(app.buttons["live.filter.reset"], in: retainedForm, direction: .down, app: app)
        app.buttons["live.filter.reset"].tap()
        app.buttons["live.applyFilters"].tap()

        assertDrawer("half expanded", count: 2, in: app)
        XCTAssertEqual(summary(in: app).label, "Following · Past 7 days · Only Friends")
        XCTAssertEqual(app.buttons["Filters"].value as? String, "1 active filters")
        assertPins(["place_noodles", "place_juniper_table"], in: app)
        dragDrawer(.up, to: "expanded", count: 2, in: app)
        assertFeedCount(2, in: app)
        let resetFeed = app.scrollViews["feed.places.scroll"]
        reveal(app.buttons["invite people to Astir"], in: resetFeed, direction: .up, app: app)
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
        app.descendants(matching: .any)["live.drawerHandle"].firstMatch
    }

    private func summary(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["live.filter.summary"]
    }

    private func assertDrawer(_ state: String, count: Int, in app: XCUIApplication) {
        let handle = drawer(in: app)
        wait(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", "Activity drawer, \(state)", "\(count) loaded updates."), on: handle)
    }

    private func dragDrawer(_ direction: Direction, to state: String, count: Int, in app: XCUIApplication) {
        let handle = drawer(in: app)
        waitHittable(handle)
        let endY: CGFloat = direction == .up ? 0.12 : 0.85
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
        assertDrawer(state, count: count, in: app)
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
        waitHittable(app.buttons["Filters"])
        waitHittable(app.buttons["Add a place"])
        XCTAssertTrue(app.maps.firstMatch.exists)
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
        let feed = app.scrollViews["feed.places.scroll"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        wait(NSPredicate(format: "value == %@", "\(count) activities loaded"), on: feed)
    }

    private func assertCombinedResult(in app: XCUIApplication) {
        assertDrawer("half expanded", count: 1, in: app)
        XCTAssertEqual(summary(in: app).label, combinedSummary)
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
        let start = CGPoint(x: usable.minX + usable.width * 0.8, y: usable.maxY - 44)
        let end = CGPoint(x: usable.minX + usable.width * 0.65, y: start.y)
        let path = CGRect(x: end.x, y: end.y - 6, width: start.x - end.x, height: 12)
        XCTAssertTrue(usable.contains(start) && usable.contains(end))
        for pin in app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin.")).allElementsBoundByIndex {
            XCTAssertFalse(pin.frame.intersects(path), "The one map pan must start and finish outside the loaded pin controls.")
        }
        let anchor = app.buttons["live.pin.\(anchorID)"]
        XCTAssertTrue(anchor.exists)
        let before = anchor.frame
        XCTAssertTrue(finite(before))
        let zero = app.coordinate(withNormalizedOffset: .zero)
        capture("native-pan-before")
        zero.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.1, thenDragTo: zero.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        wait(NSPredicate { _, _ in
            guard anchor.exists else { return false }
            let after = anchor.frame
            return self.finite(after) && abs(after.midX - before.midX) > 1
        })
        let diagnostic = XCTAttachment(string: "anchorID=\(anchorID); before=\(before); after=\(anchor.frame); usable=\(usable); start=\(start); end=\(end)")
        diagnostic.name = "REC-636-native-map-pan-geometry"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }

    private func filterForm(in app: XCUIApplication) -> XCUIElement {
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        return form
    }

    private func selectMenu(_ picker: XCUIElement, option: String, form: XCUIElement,
                            direction: Direction = .down, app: XCUIApplication) {
        reveal(picker, in: form, direction: direction, app: app)
        picker.tap()
        let choice = app.buttons[option]
        waitHittable(choice)
        choice.tap()
    }

    private func setOn(_ toggle: XCUIElement, in form: XCUIElement, app: XCUIApplication) {
        reveal(toggle, in: form, direction: .down, app: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
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

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        wait(NSPredicate { _, _ in element.exists && element.isEnabled && element.isHittable }, timeout: timeout)
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement? = nil, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
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
