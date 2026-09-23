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
            "-WanderContactDiscoveryUITest", "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"] + extras
        app.launch()
        return app
    }
    private func openContactSettings(_ app: XCUIApplication) {
        app.tabBars.buttons["Profile"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let link = app.buttons["settings.contactDiscovery"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
    }
    private func backToFeed(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        app.tabBars.buttons["Feed"].tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 10))
    }
    func testFollowingScreenEnableDisableAndExistingFollowSurvives() {
        let app = launchFeed()
        openContactSettings(app)
        let enable = app.buttons["contacts.settings.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5)); enable.tap()
        XCTAssertTrue(app.buttons["contacts.settings.disable"].waitForExistence(timeout: 10))
        backToFeed(app)
        let friend = app.scrollViews["feed.places.scroll"].buttons["people.recommendation.user_contact_friend.follow"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["In your contacts"].firstMatch.exists)
        capture("Following screen contact suggestions")
        friend.tap()
        XCTAssertEqual(friend.label, "Following Contact Friend")
        // The first successful follow can present the contextual notifications
        // campaign. Complete that real flow before reopening contact settings.
        let notificationContinue = app.buttons["productUpsell.primary"]
        if notificationContinue.waitForExistence(timeout: 3) {
            notificationContinue.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")).firstMatch
            if deny.waitForExistence(timeout: 3) { deny.tap() }
        }
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
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 10))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["In your contacts"].firstMatch)
        wait(for: [gone], timeout: 10)
        openContactSettings(app)
        XCTAssertTrue(app.buttons["contacts.settings.enable"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
