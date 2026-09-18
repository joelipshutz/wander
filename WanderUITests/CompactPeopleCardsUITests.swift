import XCTest

final class CompactPeopleCardsUITests: XCTestCase {
    @MainActor
    func testFollowShowsFollowingBeforeRequestCompletesAndRecoversOnFailure() {
        let app = launch(delayedFollow: true)
        let follow = app.buttons["people.recommendation.user_compact_alex.follow"]
        let profile = app.buttons["people.recommendation.user_compact_alex.profile"]
        XCTAssertTrue(follow.waitForExistence(timeout: 15))
        follow.tap()

        XCTAssertEqual(follow.label, "Following Alex Rivera")
        XCTAssertFalse(follow.descendants(matching: .activityIndicator).firstMatch.exists)
        XCTAssertFalse(follow.isEnabled, "A pending follow must not submit duplicate requests")
        XCTAssertTrue(profile.isHittable, "The profile remains available during the request")
        capture("compact-people-instant-follow")

        let failed = NSPredicate(format: "label CONTAINS %@", "Couldn't follow")
        expectation(for: failed, evaluatedWith: follow)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(follow.isEnabled)
        follow.tap()
        XCTAssertEqual(follow.label, "Following Alex Rivera")
        XCTAssertFalse(follow.descendants(matching: .activityIndicator).firstMatch.exists)
    }

    @MainActor
    func testPeopleReplaceFeaturedAndFollowFailureCanRetry() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["People worth following"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Featured for you"].exists)
        let profile = app.buttons["people.recommendation.user_maya.profile"]
        let follow = app.buttons["people.recommendation.user_compact_alex.follow"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(follow.isHittable)
        XCTAssertGreaterThanOrEqual(follow.frame.height, 44)
        XCTAssertLessThan(follow.frame.maxY - profile.frame.minY, 190)
        XCTAssertTrue(app.staticTexts["Recent"].exists)
        capture("compact-people-default")
        follow.tap()
        let failed = NSPredicate(format: "label CONTAINS %@", "Couldn't follow")
        expectation(for: failed, evaluatedWith: follow)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(follow.isEnabled)
        capture("compact-people-retry")
        follow.tap()
        expectation(for: failed, evaluatedWith: follow)
        waitForExpectations(timeout: 10)
        profile.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
        XCTAssertFalse(profile.isHittable)
    }

    @MainActor
    func testLargerTextKeepsFollowControlAccessible() {
        let app = launch(largeText: true)
        let follow = app.buttons["people.recommendation.user_maya.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 15))
        for _ in 0..<3 where !follow.isHittable { app.swipeUp() }
        XCTAssertTrue(follow.isHittable)
        XCTAssertGreaterThanOrEqual(follow.frame.height, 44)
        capture("compact-people-accessibility-text")
    }

    @MainActor
    private func launch(largeText: Bool = false, delayedFollow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderCompactPeopleUITest", "-WanderInitialTab", "discover"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if delayedFollow {
            app.launchArguments.append("-WanderDelayedFollowUITest")
        }
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
