import XCTest

@MainActor
final class DefaultMapFilterSettingsUITests: XCTestCase {
    func testLiveSettingsShowsAppearanceControlsWithoutLegacyDefaultFilter() {
        continueAfterFailure = false
        executionTimeAllowance = 90
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        defer { app.terminate() }
        if app.buttons["productUpsell.secondary"].waitForExistence(timeout: 4) {
            app.buttons["productUpsell.secondary"].tap()
        }
        waitHittable(app.buttons["live.draw"], timeout: 30)
        let introduction = app.buttons["live.introduction.notNow"]
        if introduction.exists && introduction.isHittable { introduction.tap() }
        XCTAssertTrue(app.tabBars.buttons["Live"].exists, "Exercise the actual Live experience.")

        let profile = app.tabBars.buttons["Profile"]
        waitHittable(profile)
        profile.tap()
        let settings = app.buttons["Settings"]
        waitHittable(settings)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitHittable(app.buttons["settings.back"])

        let screen = app.descendants(matching: .any)["settings.screen"].firstMatch
        let dark = app.switches["settings.map.darkMode"]
        let colored = app.switches["settings.map.coloredMap"]
        let controls = [dark, colored]
        for _ in 0..<6 {
            if controls.allSatisfy({ $0.exists && $0.isHittable && app.frame.contains($0.frame) }) { break }
            screen.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)))
        }
        for control in controls {
            waitHittable(control)
            XCTAssertTrue(app.frame.contains(control.frame), "Map appearance controls must be fully visible.")
        }
        XCTAssertEqual(dark.label, "Dark map")
        XCTAssertEqual(colored.label, "Colored map")
        XCTAssertFalse(app.descendants(matching: .any)["settings.map.defaultFilter"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Default map filter"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC663-Live-Settings-Map-appearance-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isEnabled && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }
}
