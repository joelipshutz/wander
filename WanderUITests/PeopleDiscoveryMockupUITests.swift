import XCTest

@MainActor
final class PeopleDiscoveryMockupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testProfileCollapseAndSharedFollowOnInvite() {
        let app = launch("expanded")
        let toggle = app.buttons["peopleReview.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "Expanded")
        capture("Profile expanded")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["People worth following"].exists)
        capture("Profile collapsed")
        toggle.tap()
        let follow = app.buttons["people.recommendation.people-review-maya.follow"]
        reveal(follow, in: app)
        follow.tap()
        XCTAssertTrue(app.buttons["Following Maya Chen"].exists)
        let invite = app.buttons["peopleReview.invite"]
        reveal(invite, in: app)
        invite.tap()
        XCTAssertTrue(app.staticTexts["Invite people"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Following Maya Chen"].exists)
        capture("Invite shared follow state")
        let visibleProfile = app.buttons.matching(identifier: "people.recommendation.people-review-maya.profile")
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(visibleProfile)
        visibleProfile?.tap()
        XCTAssertTrue(app.staticTexts["Sample profile for this design review."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Invite people"].waitForExistence(timeout: 5))
    }

    func testInvitePlacementAndLocalSelection() {
        let app = launch("invite")
        XCTAssertTrue(app.staticTexts["Invite people"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["People worth following"].exists)
        capture("Invite people")
        let search = app.textFields["Name, number, or @username"]
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { search.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Alex")
        XCTAssertFalse(app.staticTexts.matching(identifier: "People worth following")
            .allElementsBoundByIndex.contains(where: { $0.isHittable }))
        let contact = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alex Reed")).firstMatch
        reveal(contact, in: app)
        contact.tap()
        app.buttons["invite.primaryAction"].tap()
        XCTAssertTrue(app.alerts["Preview only"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Preview only"].staticTexts["Your sample selection is ready. This mockup does not send invitations."].exists)
    }

    func testAccessibleExpandedProfile() {
        let app = launch("expanded", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
        let toggle = app.buttons["peopleReview.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        reveal(toggle, in: app)
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        capture("Profile accessibility text")
        let follow = app.buttons["people.recommendation.people-review-maya.follow"]
        reveal(follow, in: app)
        XCTAssertTrue(follow.isHittable)
        capture("People accessibility text")
    }

    private func launch(_ route: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderPeopleMockup", route, "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"] + extra
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
