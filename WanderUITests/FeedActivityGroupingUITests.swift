import XCTest
import UIKit

final class FeedActivityGroupingUITests: XCTestCase {
    @MainActor
    func testJointCheckInShowsBothOwnedNotesInOneCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderJointCheckInUITest", "-WanderInitialTab", "discover"]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
        let ryan = app.descendants(matching: .any)["joint.contribution.joint-fixture-person-0"].firstMatch
        for _ in 0..<5 where !ryan.isHittable { app.swipeUp() }
        XCTAssertTrue(ryan.exists)
        let joe = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Joe's note:")).firstMatch
        XCTAssertTrue(joe.exists)
        XCTAssertLessThan(ryan.frame.minY, joe.frame.minY)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "joint.contribution.joint-fixture-person-0").count, 1)
        XCTAssertFalse(app.buttons["joint.expand"].exists)
        capture("joint-two-people-feed")
    }

    @MainActor
    func testJointTenPeopleExpandsAndCollapsesWithoutDuplicateRows() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderJointCheckInUITest", "-WanderJointTenPeople", "-WanderInitialTab", "discover"]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
        let expand = app.buttons["joint.expand"]
        for _ in 0..<6 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        XCTAssertGreaterThanOrEqual(expand.frame.height, 44)
        capture("joint-ten-people-collapsed")
        expand.tap()
        let last = app.descendants(matching: .any)["joint.contribution.joint-fixture-person-9"].firstMatch
        for _ in 0..<8 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "joint.contribution.joint-fixture-person-9").count, 1)
        capture("joint-ten-people-expanded")
        for _ in 0..<3 where !expand.isHittable { app.swipeUp() }
        expand.tap()
        XCTAssertFalse(last.exists)
    }

    @MainActor
    func testJointProfileShowsJoeFirstAndSharesTheFeedConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderJointCheckInUITest", "-WanderInitialTab", "discover"]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
        app.buttons["Profile"].firstMatch.tap()
        let joe = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Joe's note:")).firstMatch
        let ryan = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ryan's note:")).firstMatch
        for _ in 0..<9 where !joe.isHittable { app.swipeUp() }
        XCTAssertTrue(joe.exists)
        XCTAssertTrue(ryan.exists)
        XCTAssertLessThan(joe.frame.minY, ryan.frame.minY)
        capture("joint-joe-profile")
        let comments = app.buttons["Open comments"].firstMatch
        for _ in 0..<3 where !comments.isHittable { app.swipeUp() }
        comments.tap()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        let composer = app.descendants(matching: .any)["activity.comment.input"].firstMatch
        composer.tap()
        composer.typeText("Same plan, same conversation.")
        send.tap()
        XCTAssertTrue(app.staticTexts["Same plan, same conversation."].waitForExistence(timeout: 5))
        capture("joint-shared-comment")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Feed"].firstMatch.tap()
        for _ in 0..<7 where !joe.isHittable { app.swipeUp() }
        let feedComments = app.buttons["Open comments"].firstMatch
        for _ in 0..<3 where !feedComments.isHittable { app.swipeUp() }
        XCTAssertEqual(feedComments.value as? String, "3 comments")
        feedComments.tap()
        XCTAssertTrue(app.staticTexts["Same plan, same conversation."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testJointOtherProfileKeepsRyanFirstAndOneConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderJointCheckInUITest", "-WanderInitialTab", "discover"]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
        let profile = app.buttons["Open Ryan's profile"].firstMatch
        for _ in 0..<6 where !profile.isHittable { app.swipeUp() }
        XCTAssertTrue(profile.isHittable)
        profile.tap()
        let ryan = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ryan's note:")).firstMatch
        let joe = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Joe's note:")).firstMatch
        for _ in 0..<10 where !ryan.isHittable { app.swipeUp() }
        XCTAssertTrue(ryan.exists)
        XCTAssertTrue(joe.exists)
        XCTAssertLessThan(ryan.frame.minY, joe.frame.minY)
        capture("joint-ryan-profile")
        let comments = app.buttons["Open comments"].firstMatch
        for _ in 0..<4 where !comments.isHittable { app.swipeUp() }
        comments.tap()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Joe's profile"].exists)
    }

    @MainActor
    func testJointTenPeopleCanExpandWithLargeTextInDarkAppearance() {
        let previousAppearance = XCUIDevice.shared.appearance
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = previousAppearance }
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments = ["-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderJointCheckInUITest", "-WanderJointTenPeople", "-WanderInitialTab", "discover",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
        let expand = app.buttons["joint.expand"]
        for _ in 0..<12 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        XCTAssertGreaterThanOrEqual(expand.frame.height, 44)
        // The iPad compatibility app reports its logical phone bounds while
        // descendants report screen positions. Use the physical screen here.
        XCTAssertGreaterThanOrEqual(expand.frame.minX, 0)
        XCTAssertLessThanOrEqual(expand.frame.maxX, XCUIScreen.main.screenshot().image.size.width)
        capture("joint-large-text-dark-collapsed")
        expand.tap()
        let last = app.descendants(matching: .any)["joint.contribution.joint-fixture-person-9"].firstMatch
        for _ in 0..<20 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        capture("joint-large-text-dark-expanded")
    }

    @MainActor
    func testAuthenticatedRootSurvivesRepeatedColdLaunches() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"
        ]
        for _ in 0..<3 {
            app.launch()
            XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
            let exited = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in app.state != .runningForeground },
                object: nil
            )
            exited.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [exited], timeout: 3), .completed)
            app.terminate()
        }
    }

    @MainActor
    func testCombinedActivityExpandsInOrderCollapsesAndOpensOriginalPost() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedGroupingUITest", "-WanderInitialTab", "discover"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        let disclosure = app.buttons["feed.activity.fixture-feed-group-wanna.disclosure"]
        for _ in 0..<5 where !disclosure.isHittable { app.swipeUp() }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        capture("feed-group-collapsed")

        let wanna = app.buttons["feed.activity.fixture-feed-group-wanna.sequenceEvent"]
        let visit = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.sequenceEvent"]
        let list = app.buttons["feed.activity.fixture-feed-group-list.sequenceEvent"]
        XCTAssertFalse(wanna.exists)
        disclosure.tap()
        XCTAssertTrue(wanna.waitForExistence(timeout: 3))
        XCTAssertEqual(disclosure.value as? String, "Expanded, 3 activities")
        XCTAssertLessThan(wanna.frame.minY, visit.frame.minY)
        XCTAssertLessThan(visit.frame.minY, list.frame.minY)
        for _ in 0..<3 where !list.isHittable { app.swipeUp() }
        capture("feed-group-expanded")

        for _ in 0..<3 where !disclosure.isHittable { app.swipeDown() }
        disclosure.tap()
        XCTAssertFalse(wanna.exists)
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        disclosure.tap()
        for _ in 0..<3 where !wanna.isHittable { app.swipeUp() }
        wanna.tap()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 5))
        capture("feed-group-original-post")
    }

    @MainActor
    func testNotificationOpensPostWithArrowComposerAndBackReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "map"
        ]
        app.launch()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["comments"].exists)
        XCTAssertFalse(app.staticTexts["Start the conversation"].exists)
        XCTAssertFalse(app.buttons["Post"].exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        capture("REC-543-post-empty")
        let composer = app.descendants(matching: .any)["activity.comment.input"].firstMatch
        composer.tap()
        composer.typeText("Meet you here next time!")
        XCTAssertTrue(send.isEnabled)
        capture("REC-543-post-composer")
        send.tap()
        XCTAssertTrue(app.staticTexts["Meet you here next time!"].waitForExistence(timeout: 5))
        capture("REC-543-post-comment")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)
        capture("REC-543-back-to-feed")
    }

    @MainActor
    func testNotificationPostEdgeSwipeReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "profile"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 20))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.comment.send"].exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
