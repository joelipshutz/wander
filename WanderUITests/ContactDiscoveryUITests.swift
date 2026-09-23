import XCTest

@MainActor final class ContactDiscoveryUITests: XCTestCase {
    private func launch(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestStep", "contacts", "-WanderContactDiscoveryUITest", "-WanderDisableWalkthroughs"] + extras
        app.launch()
        return app
    }
    func testConsentShowsContactFirstAndFollowRemainsExplicit() {
        let app = launch()
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["onboarding.contacts.skip"].exists)
        capture("Contacts consent")
        find.tap()
        let friend = app.buttons["onboarding.friends.follow.user_contact_friend"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        XCTAssertEqual(friend.label, "Follow Contact Friend")
        XCTAssertTrue(app.staticTexts["In your contacts"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["3 of your contacts follow General Friend"].firstMatch.exists)
        XCTAssertLessThan(friend.frame.minY, app.buttons["onboarding.friends.follow.user_general_friend"].frame.minY)
        XCTAssertEqual(app.buttons.matching(identifier: "onboarding.friends.follow.user_contact_friend").count, 1)
        capture("Contact suggestion before follow")
        friend.tap()
        XCTAssertTrue(app.buttons["Following Contact Friend"].waitForExistence(timeout: 5))
        capture("Explicit contact follow saved")
    }
    func testSkipShowsGeneralSuggestionsWithoutContactLabel() {
        let app = launch()
        let skip = app.buttons["onboarding.contacts.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15)); skip.tap()
        XCTAssertTrue(app.buttons["onboarding.friends.follow.user_general_friend"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["In your contacts"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["3 of your contacts follow General Friend"].firstMatch.exists)
    }
    func testDeniedPermissionCanContinueAndSearch() {
        let app = launch(["-WanderContactDiscoveryDenied"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        XCTAssertTrue(app.staticTexts["onboarding.contacts.error"].waitForExistence(timeout: 5))
        capture("Denied contacts fallback")
        app.buttons["onboarding.contacts.skip"].tap()
        XCTAssertTrue(app.textFields["onboarding.friends.search"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["In your contacts"].firstMatch.exists)
    }
    func testMatchingFailureKeepsGeneralFollowSuggestionsUsable() {
        let app = launch(["-WanderContactDiscoveryFailure"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        let general = app.buttons["onboarding.friends.follow.user_general_friend"]
        XCTAssertTrue(general.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["In your contacts"].firstMatch.exists)
        general.tap()
        XCTAssertTrue(app.buttons["Following General Friend"].waitForExistence(timeout: 5))
    }
    private func launchFeed(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderContactDiscoveryUITest", "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover",
            "-WanderFeedSurface", "people"] + extras
        app.launchEnvironment["WANDER_PRODUCT_UPSELL_TEST_SUITE"] = "ProductUpsellUITests.ContactDiscovery.\(UUID().uuidString)"
        app.launch()
        completeNotificationPromptIfPresented(app)
        return app
    }
    // A signed-in launch can show the first-visit notification primer before
    // any follow. Finish it as a user would; waiting only for the underlying
    // contact button to exist does not mean that button can receive touches.
    private func completeNotificationPromptIfPresented(_ app: XCUIApplication) {
        let primary = app.buttons["productUpsell.primary"]
        guard primary.waitForExistence(timeout: 8) else { return }
        XCTAssertTrue(app.staticTexts["Keep up with your people"].exists)
        if primary.label == "Open Settings" {
            app.buttons["productUpsell.secondary"].tap()
        } else {
            XCTAssertEqual(primary.label, "Continue")
            primary.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let deny = springboard.alerts.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")
            ).firstMatch
            if deny.waitForExistence(timeout: 5) { deny.tap() }
        }
        XCTAssertTrue(primary.waitForNonExistence(timeout: 10))
    }

    private func openContactSettings(_ app: XCUIApplication) {
        let link = app.buttons["feed.contactDiscovery"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: link)
        wait(for: [hittable], timeout: 10)
        link.tap()
    }
    private func backToFeed(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["feed.contactDiscovery"].waitForExistence(timeout: 10))
    }
    func testFollowingScreenEnableDisableAndExistingFollowSurvives() {
        let app = launchFeed()
        openContactSettings(app)
        let enable = app.buttons["contacts.settings.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5)); enable.tap()
        XCTAssertTrue(app.buttons["contacts.settings.disable"].waitForExistence(timeout: 10))
        backToFeed(app)
        let friend = app.scrollViews["feed.people.scroll"].buttons["people.recommendation.user_contact_friend.follow"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["In your contacts"].firstMatch.exists)
        capture("Following screen contact suggestions")
        friend.tap()
        XCTAssertEqual(friend.label, "Following Contact Friend")
        completeNotificationPromptIfPresented(app)
        openContactSettings(app)
        app.buttons["contacts.settings.disable"].tap()
        XCTAssertTrue(app.buttons["contacts.settings.enable"].waitForExistence(timeout: 10))
        backToFeed(app)
        XCTAssertFalse(app.staticTexts["In your contacts"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Contact Friend"].firstMatch.waitForExistence(timeout: 5))
        capture("Following screen after contact matching disabled")
    }
    func testFollowingScreenRechecksRevokedAccessOnForeground() {
        let app = launchFeed(["-WanderContactDiscoveryRevokeOnForeground"])
        openContactSettings(app)
        let enable = app.buttons["contacts.settings.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5)); enable.tap()
        XCTAssertTrue(app.buttons["contacts.settings.disable"].waitForExistence(timeout: 10))
        backToFeed(app)
        XCTAssertTrue(app.staticTexts["In your contacts"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["feed.contactDiscovery"].waitForExistence(timeout: 10))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["In your contacts"].firstMatch)
        wait(for: [gone], timeout: 10)
        openContactSettings(app)
        XCTAssertTrue(app.buttons["contacts.settings.enable"].waitForExistence(timeout: 5))
    }
    func testOnboardingFollowMatchesShelfPendingAndRetryBehavior() {
        let app = launch(["-WanderContactDiscoveryDelayedFollow"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        let friend = app.buttons["onboarding.friends.follow.user_contact_friend"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10)); friend.tap()
        XCTAssertEqual(friend.label, "Following Contact Friend")
        XCTAssertFalse(friend.isEnabled)
        XCTAssertFalse(friend.descendants(matching: .activityIndicator).firstMatch.exists)
        capture("Onboarding instant Following")
        let failed = expectation(for: NSPredicate(format: "label CONTAINS %@", "Couldn't follow"), evaluatedWith: friend)
        wait(for: [failed], timeout: 8)
        XCTAssertTrue(friend.isEnabled)
        capture("Onboarding retry after failure")
        friend.tap()
        XCTAssertEqual(friend.label, "Following Contact Friend")
    }

    func testOnboardingVerticalDragFromFollowDoesNotSubmit() {
        let app = launch(["-WanderContactDiscoveryLongList", "-WanderContactDiscoveryDelayedFollow"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        let friend = app.buttons["onboarding.friends.follow.user_contact_friend"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        let originalY = friend.frame.minY
        let start = friend.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -70)))
        XCTAssertLessThan(friend.frame.minY, originalY - 20)
        XCTAssertEqual(friend.label, "Follow Contact Friend")
        XCTAssertTrue(friend.isEnabled)
        capture("Onboarding vertical drag cancels Follow")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
