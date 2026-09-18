#if DEBUG
import XCTest

@MainActor final class PlacePlanInvitationUITests: XCTestCase {
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
