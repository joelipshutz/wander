#if DEBUG
import XCTest

@MainActor final class PlacePlanInvitationUITests: XCTestCase {
    func testBellCountClearsOnInboxVisitWithoutOpeningPlanAndStaysClearAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let arguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                         "-WanderDisableWalkthroughs", "-WanderPlacePlanUITest"]
        app.launchArguments = arguments + ["-WanderResetNotificationBadge"]
        app.launch()
        XCTAssertTrue(app.buttons["Profile"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Profile"].firstMatch.tap()
        let bell = app.buttons["profile.checkInInvitations"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        let hasOne = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1 new notification"), object: bell)
        XCTAssertEqual(XCTWaiter.wait(for: [hasOne], timeout: 10), .completed)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "rec486-bell-count"
        before.lifetime = .keepAlways
        add(before)
        bell.tap()
        let row = app.buttons["place-plan.notification.11111111-2222-4333-8444-555555555555"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "Unread")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.value as? String, "No new notifications")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "rec486-bell-cleared"
        after.lifetime = .keepAlways
        add(after)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["Profile"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "Unread", "The plan remains unopened and available")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.value as? String, "No new notifications")
    }

    func testProfileNotificationsKeepReadPlansAvailableToReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderPlacePlanUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["Profile"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Profile"].firstMatch.tap()
        let notifications = app.buttons["profile.checkInInvitations"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()
        let row = app.buttons["place-plan.notification.11111111-2222-4333-8444-555555555555"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "Unread")
        XCTAssertTrue(row.label.contains("Ryan invited you to Narwhal"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "rec486-notifications-plans"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        row.tap()
        XCTAssertTrue(app.staticTexts["place-plan.message"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["common-ground.invitation.messages"].exists)
        XCTAssertTrue(app.textFields.allElementsBoundByIndex.allSatisfy { !$0.isHittable })
        app.buttons["place-plan.close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "Read")
        row.tap()
        XCTAssertTrue(app.staticTexts["place-plan.message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["place-plan.message"].label, "Coffee on Saturday?")
    }

    func testIncomingLinkOpensReadOnlyInvitationAndReplacesItWithUnavailableState() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderPlacePlanUITest"]
        app.launch()
        openInvitation(token: String(repeating: "a", count: 48), in: app)
        XCTAssertTrue(app.staticTexts["place-plan.message"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["place-plan.message"].label, "Coffee on Saturday?")
        XCTAssertEqual(app.staticTexts["common-ground.invitation.link-title"].label, "Let’s go to Narwhal together")
        XCTAssertEqual(app.staticTexts["common-ground.invitation.when-value"].label, "Sep 19, 2026 at 10 AM")
        XCTAssertEqual(app.staticTexts["place-plan.connection"].label, "Both Wanna Go")
        // The map's search field remains in the underlying view hierarchy;
        // no editable field may be interactive through the invitation cover.
        XCTAssertTrue(app.textFields.allElementsBoundByIndex.allSatisfy { !$0.isHittable })
        XCTAssertFalse(app.buttons["common-ground.invitation.when"].exists)
        XCTAssertFalse(app.buttons["common-ground.invitation.messages"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "rec486-real-read-only-recipient"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // A second incoming link must dismiss the first presentation before
        // opening the replacement; unavailable links never show stale content.
        openInvitation(token: String(repeating: "b", count: 48), in: app)
        XCTAssertTrue(app.staticTexts["This invitation is unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["place-plan.message"].exists)
        app.buttons["place-plan.close"].tap()
        XCTAssertFalse(app.buttons["place-plan.close"].waitForExistence(timeout: 2))
    }

    private func openInvitation(token: String, in app: XCUIApplication) {
        app.open(URL(string: "recme://plans/\(token)")!)
        // iOS 26.5 asks SpringBoard to confirm a custom-scheme app open.
        // This is system UI outside the tested application's accessibility tree.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }
}
#endif
