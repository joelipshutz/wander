import XCTest

@MainActor
final class ClipFlowUITests: XCTestCase {
    func testSaveAndProfileSetupStayInsideClip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AstirClipDemo"]
        app.launch()
        XCTAssertTrue(app.buttons["clip.save"].waitForExistence(timeout: 10))
        capture("clip-place-preview")
        app.buttons["clip.save"].tap()
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
        capture("clip-sign-in")
        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 5))
        capture("clip-profile-setup")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Saved to your Wanna map"].waitForExistence(timeout: 5))
        capture("clip-place-saved")
    }

    func testInvitationJoinsAndShowsListInsideClip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AstirClipDemo", "-AstirClipDemoInvite"]
        app.launch()
        XCTAssertTrue(app.buttons["clip.join"].waitForExistence(timeout: 10))
        capture("clip-list-invitation")
        app.buttons["clip.join"].tap()
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["You're on the list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["clip.place.title"].waitForExistence(timeout: 5))
        capture("clip-list-joined")
    }

    private func capture(_ name: String) {
        // MapKit draws tiles asynchronously after the asserted UI transition.
        Thread.sleep(forTimeInterval: 2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + "-synthetic-demo"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
