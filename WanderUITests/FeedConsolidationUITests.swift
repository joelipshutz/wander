import XCTest

@MainActor final class FeedConsolidationUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
                               "-WanderInitialTab", "discover", "-WanderResetNotificationBadge", "-WanderFollowNotificationUITest",
                               "-WanderCompactPeopleUITest"]
        app.launch()
        return app
    }

    func testUnifiedFeedLayoutSearchAndProfileNavigation() {
        let app = launch()
        let search = app.buttons["feed.searchLauncher"]
        let bell = app.buttons["feed.notifications"]
        let add = app.buttons["feed.headerAdd"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertTrue(bell.exists)
        XCTAssertFalse(app.descendants(matching: .any)["feed.surfaceSwitch"].exists)
        XCTAssertLessThan(bell.frame.midY, search.frame.midY)
        XCTAssertEqual(add.frame.midY, search.frame.midY, accuracy: 4)
        let invite = app.buttons["invite people to Astir"]
        XCTAssertTrue(invite.exists)
        XCTAssertGreaterThan(invite.frame.minY, search.frame.maxY)
        let people = app.staticTexts["People worth following"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(people.frame.minY, invite.frame.maxY)
        capture("REC-597 consolidated Feed")
        search.tap()
        let field = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discover.contactDiscovery"].exists)
        field.tap()
        field.typeText("Ryan")
        let ryan = app.buttons["discover.person.user_ryan"]
        XCTAssertTrue(ryan.waitForExistence(timeout: 5))
        let following = app.buttons["discover.person.user_ryan.follow"]
        XCTAssertEqual(following.label, "Following Ryan")
        XCTAssertFalse(following.isEnabled)
        XCTAssertGreaterThanOrEqual(following.frame.height, 44)
        capture("REC-597 people in combined search")
        ryan.tap()
        let back = app.buttons["profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.buttons["discover.searchBack"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
    }

    func testFollowerInboxAcknowledgesBothBellsAndReturnsToFeed() {
        let app = launch()
        let bell = app.buttons["feed.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        let hasBadge = NSPredicate(format: "value != %@", "No new notifications")
        expectation(for: hasBadge, evaluatedWith: bell)
        waitForExpectations(timeout: 10)
        bell.tap()
        XCTAssertTrue(app.buttons["notifications.follow.user_ryan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Couldn’t refresh notifications"].exists)
        XCTAssertFalse(app.buttons["Find friends from contacts"].exists)
        capture("REC-597 shared follower inbox")
        app.buttons["notifications.follow.user_ryan"].tap()
        XCTAssertTrue(app.buttons["profile.back"].waitForExistence(timeout: 5))
        app.buttons["profile.back"].tap()
        XCTAssertTrue(app.buttons["notifications.follow.user_ryan"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertEqual(bell.value as? String, "No new notifications")
        app.tabBars.buttons["Profile"].tap()
        let profileBell = app.buttons["profile.checkInInvitations"]
        XCTAssertTrue(profileBell.waitForExistence(timeout: 8))
        XCTAssertEqual(profileBell.value as? String, "No new notifications")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
