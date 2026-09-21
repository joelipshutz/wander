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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
