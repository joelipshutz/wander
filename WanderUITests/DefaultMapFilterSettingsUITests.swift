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
        let you = app.buttons["settings.map.defaultFilter.you"]
        XCTAssertTrue(featured.waitForExistence(timeout: 4))
        XCTAssertTrue(friends.exists)
        XCTAssertTrue(you.exists)
        XCTAssertEqual(
            featured.label,
            "Featured. Featured shows you recommendations based on your taste"
        )
        XCTAssertEqual(
            friends.label,
            "Friends. All places from everyone you follow"
        )
        XCTAssertEqual(
            you.label,
            "You. Only your check-ins and Wanna Go places"
        )
        XCTAssertEqual(featured.value as? String, "Selected")

        you.tap()

        XCTAssertEqual(you.value as? String, "Selected")
        XCTAssertEqual(featured.value as? String, "")
        XCTAssertEqual(friends.value as? String, "")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Default map filter NUX descriptions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
