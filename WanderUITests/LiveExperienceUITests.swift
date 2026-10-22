import XCTest

@MainActor
final class LiveExperienceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testThreeTabsAndProfileContinuity() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Live"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.buttons["Lists"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        XCTAssertFalse(app.tabBars.buttons["Map"].exists)
        XCTAssertFalse(app.tabBars.buttons["Feed"].exists)
        XCTAssertFalse(app.tabBars.buttons["Events"].exists)
        capture("live-home")
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10) || app.staticTexts["Your Map"].exists)
        capture("profile-preserved")
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 10))
    }

    func testDrawingRequiresApplyAndCanBeCleared() {
        let app = launch()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        app.buttons["live.draw"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["live.applyArea"].isEnabled)
        app.buttons["Use visible area"].tap()
        XCTAssertTrue(app.buttons["live.applyArea"].isEnabled)
        capture("draw-review")
        app.buttons["live.applyArea"].tap()
        XCTAssertTrue(app.buttons["live.clearArea"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Lists"].tap()
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["live.clearArea"].exists)
        app.buttons["live.clearArea"].tap()
        XCTAssertFalse(app.buttons["live.clearArea"].exists)
    }

    func testDrawerDragAndExistingFeedSections() {
        let app = launch()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 30))
        XCTAssertTrue((handle.value as? String)?.contains("loaded updates") == true,
                      "The combined drawer element must retain its loaded count for VoiceOver.")
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertTrue(app.buttons["invite people to Astir"].waitForExistence(timeout: 8)
                      || app.staticTexts["Activity"].exists)
        capture("feed-expanded")
        let feed = app.scrollViews["feed.places.scroll"]
        let actor = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.actor"]
        // Short edge drags avoid flinging past a card on the compact phone
        // and do not start inside the horizontal people recommendations.
        for _ in 0..<10 where !actor.isHittable {
            feed.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: feed.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.45)))
        }
        if !actor.isHittable { capture("feed-scroll-diagnostic") }
        XCTAssertTrue(actor.isHittable)
        capture("existing-activity-card")
        let expanded = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        expanded.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["live.draw"].isHittable)
    }

    func testFilterResetCanBeCancelledBeforeApply() {
        let app = launch()
        app.buttons["live.draw"].tap()
        app.buttons["Use visible area"].tap()
        app.buttons["live.applyArea"].tap()
        XCTAssertTrue(app.buttons["live.clearArea"].waitForExistence(timeout: 5))
        app.buttons["Filters"].tap()
        tapResetFilters(in: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["live.clearArea"].waitForExistence(timeout: 5))
        app.buttons["Filters"].tap()
        tapResetFilters(in: app)
        app.buttons["live.applyFilters"].tap()
        XCTAssertFalse(app.buttons["live.clearArea"].exists)
    }

    func testCommittedPeopleFilterSurvivesTabReturn() {
        let app = launch()
        app.buttons["Filters"].tap()
        let people = app.buttons["live.filter.people"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.tap()
        app.buttons["Only Friends"].tap()
        app.buttons["live.applyFilters"].tap()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Lists"].tap()
        app.tabBars.buttons["Live"].tap()
        app.buttons["Filters"].tap()
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        XCTAssertTrue(people.value as? String == "Only Friends" || people.label.contains("Only Friends"))
    }

    func testSettingsCanReplayTheLiveGuide() {
        let app = launch()
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        let replay = app.buttons["settings.whatsChanged"]
        for _ in 0..<5 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        XCTAssertTrue(app.buttons["live.introduction.next"].waitForExistence(timeout: 5))
        capture("migration-guide")
        app.buttons["live.introduction.next"].tap()
        XCTAssertTrue(app.staticTexts["Choose your filters and area"].waitForExistence(timeout: 5))
    }

    func testPrivateDemoReplyAndForegroundPreserveDraft() {
        let app = launch()
        app.tabBars.buttons["Profile"].tap()
        let messages = app.buttons["profile.messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 30))
        messages.tap()
        let conversation = app.buttons["messaging.conversation.63600000-0000-0000-0000-000000000010"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        let composer = app.textFields["messaging.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Let’s go Saturday.")
        XCTAssertTrue(app.buttons["messaging.send"].isHittable)
        capture("private-reply-keyboard")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Let’s go Saturday.")
        app.buttons["messaging.send"].tap()
        XCTAssertTrue(app.staticTexts["Let’s go Saturday."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Simulated"].exists)
        capture("private-demo-reply")
    }

    func testWannaOffersContextualReplyAndHonestPlanRecovery() {
        let app = launch()
        let pin = app.buttons["live.pin.place_noodles"]
        XCTAssertTrue(pin.waitForExistence(timeout: 15))
        XCTAssertTrue(pin.label.contains("Ryan"))
        XCTAssertTrue(pin.label.contains("Wanna"))
        XCTAssertTrue(pin.label.contains("5h ago"), "Pin accessibility must describe the activity time, not current presence.")
        pin.tap()
        let activity = app.descendants(matching: .any)["live.placePreview.activity.fixture-feed-ryan-wanna-noodles"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertTrue(activity.label.contains("Ryan"))
        XCTAssertTrue(activity.label.contains("Wanna"))
        XCTAssertTrue(activity.label.contains("5h ago"))
        app.buttons["live.placePreview.close"].tap()
        setDrawer("expanded", in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        let destination = app.buttons["feed.activity.fixture-feed-ryan-wanna-noodles.place"]
        revealFully(destination, in: feed, app: app)
        XCTAssertTrue(destination.label.contains("Larchmont Noodles"))
        destination.press(forDuration: 1)
        let reply = app.buttons["Reply privately"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        let composer = app.textFields["messaging.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Larchmont Noodles"].exists)
        XCTAssertTrue(app.staticTexts["Ryan"].waitForExistence(timeout: 5), "The private reply must retain the selected activity’s recipient.")
        XCTAssertFalse(app.staticTexts["Demo friend"].exists)
        capture("wanna-contextual-reply")
        app.navigationBars.buttons["Done"].tap()
        revealFully(destination, in: feed, app: app)
        destination.tap()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 10))
        let plans = app.buttons["place-profile.plans"]
        revealFully(plans, in: app.scrollViews["place-profile.scroll"], app: app)
        plans.tap()
        let friend = app.buttons["live.plan.person.user_ryan"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        XCTAssertTrue(friend.label.contains("Ryan"))
        friend.tap()
        let save = app.buttons["live.plan.saveWanna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Share invitation"].exists)
        capture("wanna-plan-recovery")
        save.tap()
        XCTAssertTrue(app.staticTexts["common-ground.invitation.heading"].waitForExistence(timeout: 8))
        let when = app.buttons["common-ground.invitation.when"]
        for _ in 0..<4 where !when.isHittable { app.swipeUp() }
        XCTAssertTrue(when.isHittable)
        when.tap()
        let useDate = app.buttons["common-ground.invitation.use-date"]
        XCTAssertTrue(useDate.waitForExistence(timeout: 5))
        useDate.tap()
        XCTAssertTrue(app.buttons["common-ground.invitation.messages"].waitForExistence(timeout: 5))
        capture("wanna-demo-plan")
        app.buttons["common-ground.invitation.messages"].tap()
        XCTAssertTrue(app.staticTexts["common-ground.messages.preview-notice"].waitForExistence(timeout: 5))
        let invitation = app.buttons["common-ground.messages.open-invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 5))
        capture("wanna-demo-invitation")
        invitation.tap()
        XCTAssertTrue(app.staticTexts["common-ground.invitation.place"].waitForExistence(timeout: 5))
    }

    func testNearbyRadiusIsStagedAndRetainedAcrossTabs() {
        let app = launch()
        app.buttons["live.scope.nearby"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        waitForCondition { (handle.value as? String)?.contains("10 km") == true }
        XCTAssertTrue(app.buttons["live.scope.nearby"].isSelected)
        XCTAssertFalse(app.navigationBars["Filters"].exists, "Nearby applies its 10 km radius directly.")
        app.buttons["Filters"].tap()
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        let ten = app.buttons["10 km"]
        for _ in 0..<4 where !ten.isHittable { form.swipeUp() }
        XCTAssertTrue(ten.isSelected)
        app.buttons["25 km"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue((handle.value as? String)?.contains("10 km") == true)
        app.buttons["Filters"].tap()
        for _ in 0..<4 where !ten.isHittable { form.swipeUp() }
        XCTAssertTrue(ten.isSelected)
        app.buttons["25 km"].tap()
        capture("nearby-radius-filters")
        app.buttons["live.applyFilters"].tap()
        XCTAssertTrue((handle.value as? String)?.contains("25 km") == true)
        app.tabBars.buttons["Lists"].tap()
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue((handle.value as? String)?.contains("25 km") == true)
        app.buttons["live.scope.following"].tap()
        XCTAssertTrue((handle.value as? String)?.contains("Following") == true)
    }

    func testUpcomingInvitationKeepsExistingRecipientAndInboxRoutes() {
        let app = launch(extraArguments: ["-WanderPlacePlanUITest", "-WanderLiveUpcomingUITest"])
        let entry = app.buttons["live.upcomingInvitations"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let row = app.buttons["live.upcoming.invitation.11111111-2222-4333-8444-555555555555"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["From up to 100 recent received invitations"].exists)
        capture("upcoming-invitations")
        row.tap()
        XCTAssertTrue(app.staticTexts["place-plan.message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["place-plan.message"].label, "Coffee on Saturday?")
        capture("upcoming-invitation-detail")
        app.buttons["place-plan.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        app.buttons["live.upcoming.inbox"].tap()
        XCTAssertTrue(app.buttons["place-plan.notification.11111111-2222-4333-8444-555555555555"].waitForExistence(timeout: 10))
    }

    func testAccessibleDrawingControlsRemainReachable() {
        let app = launch(largeText: true)
        app.tabBars.buttons["Profile"].tap()
        let messages = app.buttons["profile.messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 10))
        XCTAssertTrue(messages.isHittable)
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 10))
        app.buttons["live.draw"].tap()
        let visibleArea = app.buttons["Use visible area"]
        XCTAssertTrue(visibleArea.waitForExistence(timeout: 5))
        XCTAssertTrue(visibleArea.isHittable)
        visibleArea.tap()
        XCTAssertTrue(app.buttons["live.applyArea"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("draw-accessibility-text")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["live.clearArea"].exists)
    }

    /// Run this same native journey on the compact and large review phones.
    /// Counts are visible query results, not a claim about network call counts.
    func testSearchThisAreaRequiresTapAndSurvivesPlaceTabsAndReset() throws {
        executionTimeAllowance = 180
        let app = launch()
        waitLiveCount(5, in: app)
        waitFeedCount(5, in: app)
        XCTAssertFalse(app.buttons["live.searchArea"].exists)
        setDrawer("collapsed", in: app)
        XCTAssertFalse(app.buttons["live.searchArea"].exists, "Drawer resizing must not stage a map search.")
        let before = try XCTUnwrap(liveState(in: app))
        let viewport = try exposedMapFrame(in: app)
        // Keep one actual visible pin well inside the pan's endpoint viewport.
        // This permits an original place destination after committing the area.
        let delta = min(32, viewport.width * 0.08)
        let interior = viewport.insetBy(dx: delta + 44, dy: 44)
        let anchor = try XCTUnwrap(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "live.pin.")).allElementsBoundByIndex.first {
                guard let snapshot = try? $0.snapshot() else { return false }
                return interior.contains(CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)) && $0.isHittable
            }, "The fixture needs one visible interior pin for place-return coverage.")
        let anchorID = anchor.identifier
        panMap(in: app, viewport: viewport, distance: delta)
        XCTAssertTrue(app.buttons["live.searchArea"].waitForExistence(timeout: 10))
        XCTAssertEqual(try XCTUnwrap(liveState(in: app)).value, before.value,
                       "Panning must not commit the visible area or change its loaded count.")
        capture("search-area-staged-before-tap")
        app.buttons["live.searchArea"].tap()
        waitForCondition {
            guard let state = self.liveState(in: app) else { return false }
            // The five-event fixture includes one unmapped list event. The
            // area query must remove it while retaining the interior pin.
            return state.count > 0 && state.count < before.count && state.value.contains("Map area")
        }
        let committed = try XCTUnwrap(liveState(in: app))
        XCTAssertTrue(app.buttons["live.searchArea"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["live.clearArea"].exists)
        XCTAssertEqual(app.buttons["live.draw"].label, "Draw area")
        let retainedPin = app.buttons.matching(identifier: anchorID).element
        XCTAssertTrue(retainedPin.waitForExistence(timeout: 5))
        XCTAssertTrue(retainedPin.isHittable)
        capture("search-area-committed")
        retainedPin.tap()
        let open = app.buttons["live.placePreview.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isHittable)
        open.tap()
        let back = app.buttons["place-profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        capture("search-area-original-place")
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        waitLiveCount(committed.count, in: app)
        waitFeedCount(committed.count, in: app)
        XCTAssertTrue(try XCTUnwrap(liveState(in: app)).value.contains("Map area"))
        for tab in ["Lists", "Profile"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
            app.tabBars.buttons["Live"].tap()
            waitLiveCount(committed.count, in: app)
            XCTAssertTrue(try XCTUnwrap(liveState(in: app)).value.contains("Map area"))
        }
        setDrawer("collapsed", in: app)
        XCTAssertFalse(app.buttons["live.searchArea"].exists,
                       "Returning and resizing must preserve the committed camera reference.")
        panMap(in: app, viewport: try exposedMapFrame(in: app), distance: -delta)
        XCTAssertTrue(app.buttons["live.searchArea"].waitForExistence(timeout: 10))
        XCTAssertEqual(try XCTUnwrap(liveState(in: app)).value, committed.value)
        app.buttons["Filters"].tap()
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        let reset = app.buttons.matching(identifier: "live.filter.reset").element
        revealFully(reset, in: form, app: app)
        reset.tap()
        app.buttons["live.applyFilters"].tap()
        waitLiveCount(5, in: app)
        XCTAssertFalse(try XCTUnwrap(liveState(in: app)).value.contains("Map area"))
        XCTAssertFalse(app.buttons["live.clearArea"].exists)
        XCTAssertFalse(app.buttons["live.searchArea"].exists)
        capture("search-area-reset")
    }

    /// Exercises automatic bottom continuation of the existing local buffer.
    func testLiveAutomaticPaginationReachesTerminalBufferedPage() {
        executionTimeAllowance = 300
        let app = launch(extraArguments: ["-WanderFeedPaginationUITest"])
        setDrawer("expanded", in: app)
        waitLiveCount(20, in: app)
        waitFeedCount(20, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        for (current, next) in [(20, 40), (40, 44)] {
            scrollToAutomaticPage(in: app, feed: feed, previousCount: current)
            waitFeedCount(next, in: app, timeout: 15)
            waitLiveCount(next, in: app)
            capture("live-buffered-page-\(next)")
        }
        // The fixture creates 45 events, but event 0 is newer than the fixed
        // committed-until instant. Live therefore exposes the other 44.
        XCTAssertFalse(app.buttons["feed.filteredLoadMore"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["feed.loadingMore"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["feed.loadMoreRetry"].firstMatch.exists)
        feed.swipeUp()
        waitFeedCount(44, in: app)
        XCTAssertFalse(app.buttons["feed.filteredLoadMore"].exists)
        capture("live-buffered-page-exhausted")
    }

    /// Retain the historical case identifier while checking the new automatic
    /// continuation through an empty authorized page and its older stage.
    func testLiveManualLoadMoreContinuesAnEmptyAuthorizedPage() throws {
        executionTimeAllowance = 300
        let app = launch(extraArguments: ["-WanderFeedPaginationUITest", "-WanderLiveManualPaginationUITest"])
        setDrawer("expanded", in: app)
        waitLiveCount(0, in: app)
        waitFeedCount(0, in: app)
        let feed = app.scrollViews["feed.places.scroll"]
        XCTAssertFalse(app.buttons["feed.filteredLoadMore"].exists,
                       "An empty authorized page must continue automatically without a manual control.")
        scrollToAutomaticPage(in: app, feed: feed, previousCount: 0)
        XCTAssertFalse(app.descendants(matching: .any)["feed.loadMoreRetry"].firstMatch.exists)
        capture("live-empty-authorized-page-automatically-loading")
        waitFeedCount(1, in: app, timeout: 15)
        waitLiveCount(1, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["feed.activity.fixture-live-manual-next.postcard"].firstMatch.exists)
        // The fixture's older page overlaps the same event ID. Exhausting it
        // must retain one authorized card, rather than duplicate or drop it.
        let older = app.descendants(matching: .any)["feed.olderActivity"].firstMatch
        XCTAssertTrue(older.waitForExistence(timeout: 15))
        let terminal = app.descendants(matching: .any)["feed.allActivity"].firstMatch
        revealFully(terminal, in: feed, app: app)
        XCTAssertTrue(terminal.waitForExistence(timeout: 15))
        waitFeedCount(1, in: app)
        waitLiveCount(1, in: app)
        XCTAssertFalse(app.buttons["feed.filteredLoadMore"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["feed.loadingMore"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["feed.loadMoreRetry"].firstMatch.exists)
        feed.swipeUp()
        waitFeedCount(1, in: app)
        XCTAssertFalse(app.buttons["feed.filteredLoadMore"].exists)
        capture("live-empty-page-and-older-stage-exhausted")
    }

    private func scrollToAutomaticPage(in app: XCUIApplication, feed: XCUIElement, previousCount: Int) {
        for _ in 0..<24 {
            XCTAssertEqual(app.state, .runningForeground)
            guard let observed = automaticPageSnapshot(in: app) else { return }
            // Loading and its still-committed page must come from the same tree.
            // A second native query can run after the next page has committed.
            XCTAssertEqual(observed.feed.value as? String, "\(previousCount) activities loaded",
                           "The next page must not arrive without observable loading feedback.")
            if observed.loading {
                capture("live-automatic-loading-after-\(previousCount)")
                return
            }
            let viewport = observed.feed.frame.intersection(observed.appFrame)
            let top = max(viewport.minY, observed.navigationFrame?.maxY ?? viewport.minY) + 8
            let bottom = min(viewport.maxY, observed.tabFrame?.minY ?? viewport.maxY) - 8
            let visible = CGRect(x: viewport.minX + 8, y: top, width: viewport.width - 16, height: bottom - top)
            XCTAssertGreaterThan(visible.height, 80)
            XCTAssertGreaterThan(visible.width, 44)
            // Traverse the exposed Feed height: a shorter fixed fraction can
            // exhaust the gesture budget before reaching the loaded page's end.
            // Keep the drag in content, away from the native scrollbar thumb.
            let start = CGPoint(x: visible.midX, y: visible.maxY - 8)
            let end = CGPoint(x: start.x, y: visible.minY + 8)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - observed.appFrame.minX, dy: start.y - observed.appFrame.minY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x - observed.appFrame.minX, dy: end.y - observed.appFrame.minY)))
        }
        waitForCondition(timeout: 5) {
            guard let observed = self.automaticPageSnapshot(in: app) else { return false }
            return observed.loading && (observed.feed.value as? String) == "\(previousCount) activities loaded"
        }
        capture("live-automatic-loading-after-\(previousCount)")
    }

    private func automaticPageSnapshot(in app: XCUIApplication) -> (
        appFrame: CGRect, feed: XCUIElementSnapshot, loading: Bool,
        navigationFrame: CGRect?, tabFrame: CGRect?
    )? {
        guard let root = try? app.snapshot() else {
            XCTFail("The current Feed must have a native accessibility snapshot.")
            return nil
        }
        var feeds: [XCUIElementSnapshot] = []
        var loading = false
        var navigationFrame: CGRect?
        var tabFrame: CGRect?
        @MainActor
        func visit(_ node: XCUIElementSnapshot) {
            if node.elementType == .scrollView && node.identifier == "feed.places.scroll" {
                feeds.append(node)
            }
            if node.identifier == "feed.loadingMore" { loading = true }
            // Bound the gesture with the onscreen chrome from this same tree.
            // An offscreen retained navigation or tab view cannot clip it.
            if !node.frame.isEmpty && root.frame.intersects(node.frame) {
                if node.elementType == .navigationBar && navigationFrame == nil {
                    navigationFrame = node.frame
                }
                if node.elementType == .tabBar && tabFrame == nil {
                    tabFrame = node.frame
                }
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        guard feeds.count == 1, let feed = feeds.first else {
            XCTFail("Exactly one loaded Feed must be present in the native snapshot.")
            return nil
        }
        return (root.frame, feed, loading, navigationFrame, tabFrame)
    }

    private func liveState(in app: XCUIApplication) -> (count: Int, value: String, label: String)? {
        let handle = app.staticTexts.matching(identifier: "live.drawerHandle").element
        guard let snapshot = try? handle.snapshot(), let value = snapshot.value as? String,
              let first = value.split(separator: " ").first, let count = Int(first) else { return nil }
        return (count, value, snapshot.label)
    }

    private func waitForCondition(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime <= deadline else { return false }
            let matches = condition()
            return matches && ProcessInfo.processInfo.systemUptime <= deadline
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitLiveCount(_ count: Int, in app: XCUIApplication) {
        waitForCondition { self.liveState(in: app)?.count == count }
    }

    private func waitFeedCount(_ count: Int, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let feed = app.scrollViews.matching(identifier: "feed.places.scroll")
            .matching(NSPredicate(format: "value == %@", "\(count) activities loaded")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: timeout))
    }

    private func setDrawer(_ state: String, in app: XCUIApplication) {
        for _ in 0..<2 {
            guard liveState(in: app)?.label != "Activity drawer, \(state)" else { return }
            let handle = app.staticTexts.matching(identifier: "live.drawerHandle").element
            XCTAssertTrue(handle.isHittable)
            let oldLabel = liveState(in: app)?.label
            let destination = state == "expanded" ? 0.12 : 0.85
            handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: destination)))
            waitForCondition { self.liveState(in: app)?.label != oldLabel }
        }
        XCTAssertEqual(liveState(in: app)?.label, "Activity drawer, \(state)")
    }

    private func exposedMapFrame(in app: XCUIApplication) throws -> CGRect {
        let map = try app.maps.firstMatch.snapshot().frame.intersection(app.frame)
        let controls = try app.buttons["live.draw"].snapshot().frame
        let drawer = try app.staticTexts.matching(identifier: "live.drawerHandle").element.snapshot().frame
        let top = max(map.minY, controls.maxY) + 12
        let bottom = min(map.maxY, drawer.minY) - 12
        let viewport = CGRect(x: map.minX + 12, y: top, width: map.width - 24, height: bottom - top)
        XCTAssertTrue(viewport.width.isFinite && viewport.height.isFinite && viewport.width > 160 && viewport.height > 120)
        return viewport
    }

    private func panMap(in app: XCUIApplication, viewport: CGRect, distance: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = CGPoint(x: viewport.midX, y: viewport.minY + 24)
        let end = CGPoint(x: start.x + distance, y: start.y)
        XCTAssertTrue(viewport.contains(start) && viewport.contains(end))
        origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
    }

    private func revealFully(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        func requireForeground() -> Bool {
            let state = app.state
            guard state == .runningForeground else {
                capture("live-reveal-not-foreground")
                XCTFail("Expected the app to remain foreground while revealing the control; observed state \(state.rawValue).")
                return false
            }
            return true
        }
        for _ in 0..<24 {
            guard requireForeground() else { return }
            let scrollFrame = scroll.frame
            let viewport = scrollFrame.intersection(app.frame)
            let top = max(viewport.minY, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : viewport.minY) + 8
            let tabFrame = app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable ? app.tabBars.firstMatch.frame : nil
            let bottom = min(viewport.maxY, tabFrame?.minY ?? viewport.maxY) - 8
            let visible = CGRect(x: viewport.minX + 8, y: top, width: viewport.width - 16, height: bottom - top)
            let frame = element.exists ? element.frame : .zero
            let hasFrame = !frame.isEmpty && !frame.isNull && !frame.isInfinite
                && frame.minY.isFinite && frame.maxY.isFinite
            if hasFrame, visible.contains(frame), element.isEnabled, element.isHittable {
                return
            }
            XCTAssertGreaterThan(visible.height, 80)
            let distance = hasFrame
                ? min(visible.height * 0.65, max(24, frame.maxY - visible.maxY + 8))
                : visible.height * 0.65
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Start within the scroll content, as the continuity Reset helper
            // does, rather than beside the bottom system gesture area.
            let start = CGPoint(x: visible.maxX - 8, y: visible.minY + visible.height * 0.75)
            let end = CGPoint(x: start.x, y: max(visible.minY + 8, start.y - distance))
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        guard requireForeground() else { return }
        capture("live-control-reveal-failed")
        XCTFail("Expected the complete enabled control in the native scroll viewport.")
    }

    private func launch(largeText: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture",
                               "-WanderInitialTab", "discover",
                               // Isolate Live journeys from the existing app-open reminder campaign.
                               // OnboardingUITests covers that education; privacy checks must stay in-app.
                               "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3"]
        app.launchArguments += extraArguments
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                               largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        if app.buttons["productUpsell.secondary"].waitForExistence(timeout: 4) {
            app.buttons["productUpsell.secondary"].tap()
        }
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["live.draw"].isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        return app
    }

    private func tapResetFilters(in app: XCUIApplication) {
        let button = app.buttons["Reset filters"]
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<6 where !button.isHittable { form.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-636-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
