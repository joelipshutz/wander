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
        XCTAssertTrue(app.buttons["Messages"].waitForExistence(timeout: 30))
        app.buttons["Messages"].tap()
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
        let activityTime = app.staticTexts["live.activityTime.fixture-feed-ryan-wanna-noodles"]
        XCTAssertTrue(activityTime.waitForExistence(timeout: 5))
        XCTAssertEqual(activityTime.label, "5h ago")
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
        app.buttons["Make a plan"].firstMatch.tap()
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
        let form = app.descendants(matching: .any)["live.filters.form"].firstMatch
        let five = app.buttons["5 km"]
        for _ in 0..<4 where !five.isHittable { form.swipeUp() }
        XCTAssertTrue(five.isSelected)
        app.buttons["25 km"].tap()
        app.buttons["Cancel"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        XCTAssertTrue((handle.value as? String)?.contains("Following") == true)
        app.buttons["live.scope.nearby"].tap()
        for _ in 0..<4 where !five.isHittable { form.swipeUp() }
        XCTAssertTrue(five.isSelected)
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
        XCTAssertTrue(app.buttons["Messages"].isHittable)
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
