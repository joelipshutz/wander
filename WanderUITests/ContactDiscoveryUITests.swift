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
        XCTAssertTrue(app.staticTexts["In your contacts"].exists)
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
        XCTAssertFalse(app.staticTexts["In your contacts"].exists)
    }
    func testDeniedPermissionCanContinueAndSearch() {
        let app = launch(["-WanderContactDiscoveryDenied"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        XCTAssertTrue(app.staticTexts["onboarding.contacts.error"].waitForExistence(timeout: 5))
        capture("Denied contacts fallback")
        app.buttons["onboarding.contacts.skip"].tap()
        XCTAssertTrue(app.textFields["onboarding.friends.search"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["In your contacts"].exists)
    }
    func testMatchingFailureKeepsGeneralFollowSuggestionsUsable() {
        let app = launch(["-WanderContactDiscoveryFailure"])
        let find = app.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(find.waitForExistence(timeout: 15)); find.tap()
        let general = app.buttons["onboarding.friends.follow.user_general_friend"]
        XCTAssertTrue(general.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["In your contacts"].exists)
        general.tap()
        XCTAssertTrue(app.buttons["Following General Friend"].waitForExistence(timeout: 5))
    }
    private func launchFeed(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderContactDiscoveryUITest", "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover",
            "-WanderFeedSurface", "people"] + extras
        app.launch()
        return app
    }
    private func openContactSettings(_ app: XCUIApplication) {
        let link = app.buttons["feed.contactDiscovery"]
        XCTAssertTrue(link.waitForExistence(timeout: 15)); link.tap()
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
        let friend = app.buttons["people.recommendation.user_contact_friend.follow"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["In your contacts"].exists)
        capture("Following screen contact suggestions")
        friend.tap()
        XCTAssertEqual(friend.label, "Following Contact Friend")
        openContactSettings(app)
        app.buttons["contacts.settings.disable"].tap()
        XCTAssertTrue(app.buttons["contacts.settings.enable"].waitForExistence(timeout: 10))
        backToFeed(app)
        XCTAssertFalse(app.staticTexts["In your contacts"].exists)
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
        XCTAssertTrue(app.staticTexts["In your contacts"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["feed.contactDiscovery"].waitForExistence(timeout: 10))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["In your contacts"])
        wait(for: [gone], timeout: 10)
        openContactSettings(app)
        XCTAssertTrue(app.buttons["contacts.settings.enable"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
