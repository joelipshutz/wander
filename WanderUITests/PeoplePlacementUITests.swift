import XCTest

@MainActor
final class PeoplePlacementUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testExpandedDefaultResetsAfterTabReturnForegroundAndColdLaunch() {
        let app = launch()
        let toggle = app.buttons["profile.people.toggle"]
        XCTAssertEqual(toggle.value as? String, "Expanded")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["People worth following"].exists)
        capture("Profile collapsed")

        app.tabBars.buttons["Lists"].tap()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["People worth following"].exists)

        toggle.tap()
        backgroundApplication(app)
        app.activate()
        dismissStartupNotificationPromptIfNeeded(in: app)
        // The existing foreground-entry policy returns to Live. Re-enter Profile
        // before checking that its temporary collapsed state was discarded.
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10))
        profileTab.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "Expanded")

        toggle.tap()
        app.terminate()
        app.launch()
        dismissStartupNotificationPromptIfNeeded(in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "Expanded")
    }

    func testProfileKeepsPeopleStreakActivityMapCalendarOrder() {
        let app = launch()
        let people = app.staticTexts["People worth following"]
        let streak = app.descendants(matching: .any)["profile.saveStreak"].firstMatch
        let activity = app.staticTexts["Activity"]
        let map = app.buttons["profile.yourMap.preview"]
        let calendar = app.staticTexts.matching(NSPredicate(format: "label == %@", "Your calendar")).firstMatch
        XCTAssertTrue(people.waitForExistence(timeout: 10))
        XCTAssertTrue(streak.exists)
        XCTAssertTrue(activity.exists)
        XCTAssertTrue(map.exists)
        XCTAssertTrue(calendar.exists)
        XCTAssertLessThan(people.frame.minY, streak.frame.minY)
        XCTAssertLessThan(streak.frame.minY, activity.frame.minY)
        XCTAssertLessThan(activity.frame.minY, map.frame.minY)
        XCTAssertLessThan(map.frame.minY, calendar.frame.minY)
        capture("Profile expanded with streak next")
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.42))
        scrollStart.press(forDuration: 0.1, thenDragTo: scrollEnd, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(streak.isHittable)
        capture("People then streak and activity")
    }

    func testInviteSharesAcknowledgedFollowAndKeepsHorizontalScrolling() {
        let app = launch(contactRepository: true)
        let follow = app.buttons["people.recommendation.user_general_friend.follow"]
        let rail = app.scrollViews["people.recommendations.scroll"].firstMatch
        reveal(rail, in: app)
        for _ in 0..<4 where !follow.isHittable { rail.swipeLeft() }
        reveal(follow, in: app)
        follow.tap()
        let acknowledged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == false", "Following General Friend"), object: follow)
        XCTAssertEqual(XCTWaiter.wait(for: [acknowledged], timeout: 10), .completed)

        let seeAll = app.buttons["profile.people.seeAll"]
        for _ in 0..<4 where !seeAll.isHittable { app.swipeDown() }
        seeAll.tap()
        XCTAssertTrue(app.staticTexts["Invite people"].waitForExistence(timeout: 8))
        let invite = app.scrollViews["invite.contacts.scroll"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10))
        let inviteRail = invite.scrollViews["people.recommendations.scroll"]
        XCTAssertTrue(inviteRail.exists)
        let first = invite.buttons["people.recommendation.user_curated_rachel.profile"]
        let initialX = first.frame.minX
        inviteRail.swipeLeft()
        XCTAssertLessThan(first.frame.minX, initialX - 30)
        let sharedFollow = invite.buttons["people.recommendation.user_general_friend.follow"]
        for _ in 0..<3 where !sharedFollow.isHittable { inviteRail.swipeLeft() }
        XCTAssertEqual(sharedFollow.label, "Following General Friend")
        XCTAssertFalse(sharedFollow.isEnabled)
        capture("Invite shares following and scrolls")
    }

    func testInviteSearchKeepsContactsUsableAndFeedHasNoPeopleCards() {
        let app = launch()
        app.buttons["profile.people.seeAll"].tap()
        XCTAssertTrue(app.staticTexts["Invite people"].waitForExistence(timeout: 8))
        let invite = app.scrollViews["invite.contacts.scroll"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10))
        XCTAssertTrue(invite.staticTexts["People worth following"].exists)
        let rail = invite.scrollViews["people.recommendations.scroll"]
        let contactIndex = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Contact index")).firstMatch
        XCTAssertTrue(contactIndex.exists)
        XCTAssertLessThanOrEqual(rail.frame.maxX, contactIndex.frame.minX)
        capture("Invite people above contacts")
        let search = app.textFields["Name, number, or @username"]
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { search.tap() }
        search.typeText("Maya")
        XCTAssertFalse(invite.staticTexts["People worth following"].exists)
        XCTAssertTrue(invite.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Maya")).firstMatch.exists)
        app.buttons["invite.close"].tap()
        let live = app.tabBars.buttons["Live"]
        (live.exists ? live : app.tabBars.buttons["Feed"]).tap()
        XCTAssertFalse(app.staticTexts["People worth following"].exists)
        XCTAssertFalse(app.scrollViews["people.recommendations.scroll"].exists)
        capture("Live Feed without people carousel")
    }

    func testInviteSuggestionsSurviveMissingOrDeniedContacts() {
        for (page, message) in [("peoplePermission", "Find your people"), ("peopleDenied", "Contacts are off"), ("peopleEmpty", "No contacts found")] {
            let app = XCUIApplication()
            app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderCompactPeopleUITest", "-WanderInviteMockup", page]
            app.launch()
            let card = app.buttons["people.recommendation.user_maya.profile"]
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts[message].exists)
            capture("Invite \(page)")
            app.terminate()
        }
    }

    private func launch(contactRepository: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
                               "-WanderInitialTab", "profile", "-WanderUnifiedLiveUITest"]
        app.launchArguments.append(contactRepository ? "-WanderContactDiscoveryUITest" : "-WanderCompactPeopleUITest")
        app.launchEnvironment["WANDER_PRODUCT_UPSELL_TEST_SUITE"] = "PeoplePlacementUITests.\(UUID().uuidString)"
        app.launch()
        dismissStartupNotificationPromptIfNeeded(in: app)
        XCTAssertTrue(app.buttons["profile.people.toggle"].waitForExistence(timeout: 20))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
