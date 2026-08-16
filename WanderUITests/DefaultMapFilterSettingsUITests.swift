import XCTest

@MainActor
final class DefaultMapFilterSettingsUITests: XCTestCase {
    func testDefaultMapFilterUsesNUXDescriptionsAndUpdatesSelection() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderOpenSettings",
        ]
        app.launch()

        let selector = app.descendants(matching: .any)["settings.map.defaultFilter"]
        XCTAssertTrue(selector.waitForExistence(timeout: 8))
        selector.tap()

        let featured = app.buttons["settings.map.defaultFilter.featured"]
        let friends = app.buttons["settings.map.defaultFilter.friends"]
        XCTAssertTrue(featured.waitForExistence(timeout: 4))
        XCTAssertTrue(friends.exists)
        XCTAssertEqual(
            featured.label,
            "Featured. Featured shows you recommendations based on your taste"
        )
        XCTAssertEqual(
            friends.label,
            "Friends. All places from everyone you follow"
        )
        XCTAssertEqual(featured.value as? String, "Selected")

        friends.tap()

        XCTAssertEqual(friends.value as? String, "Selected")
        XCTAssertEqual(featured.value as? String, "")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Default map filter NUX descriptions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
