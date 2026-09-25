import XCTest

@MainActor final class EventsAccessUITests: XCTestCase {
    private func launch(metro: String, initialTab: String = "discover") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs", "-WanderHomeMetroUITest", metro, "-WanderInitialTab", initialTab, "-WanderHomeCitySearchFixtures"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    func testLAHasEventsAndShowsExistingEventsScreen() {
        let app = launch(metro: "los-angeles", initialTab: "events")
        XCTAssertTrue(app.tabBars.buttons["Events"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["events.comingSoon"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "05 — LA Events tab")
    }

    func testOrangeCountyHasFourTabsAndCannotLaunchHiddenEvents() {
        let app = launch(metro: "orange-county", initialTab: "events")
        XCTAssertTrue(app.tabBars.buttons["Feed"].isSelected)
        XCTAssertFalse(app.tabBars.buttons["Events"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        XCTAssertTrue(app.tabBars.buttons["Map"].exists)
        XCTAssertTrue(app.tabBars.buttons["Lists"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        capture(app, "06 — Outside LA, four tabs")
    }

    func testUnknownHomeHidesEvents() {
        let app = launch(metro: "unknown")
        XCTAssertFalse(app.tabBars.buttons["Events"].exists)
        XCTAssertTrue(app.tabBars.buttons["Feed"].isSelected)
        capture(app, "07 — Unknown home, four tabs")
    }

    func testSettingsHomeChangesUpdateEventsWithoutRestart() {
        let app = launch(metro: "los-angeles", initialTab: "profile")
        for (search, hasEvents) in [("Irvine", false), ("Long Beach", true)] {
            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            // XCTest can fall back to a corner point after the tab bar changes.
            // That point is outside this button's circular content shape.
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let details = app.buttons["settings.account.contactDetails"]
            XCTAssertTrue(details.waitForExistence(timeout: 5))
            details.tap()
            let city = app.textFields["accountContactDetails.city"]
            XCTAssertTrue(city.waitForExistence(timeout: 5))
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: city)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
            app.buttons["accountContactDetails.clearCity"].tap()
            city.typeText(search)
            let result = app.buttons["accountContactDetails.cityResult.\(search).US"]
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            result.tap()
            let save = app.buttons["accountContactDetails.continue"]
            if !save.isEnabled {
                let phone = app.textFields["accountContactDetails.phone"]
                XCTAssertTrue(phone.exists)
                phone.tap()
                phone.typeText("2025550123")
            }
            let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 5), .completed)
            app.buttons["accountContactDetails.continue"].tap()
            XCTAssertTrue(city.waitForNonExistence(timeout: 5))
            app.buttons["settings.back"].tap()
            XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.tabBars.buttons["Events"].exists, hasEvents)
            XCTAssertTrue(app.tabBars.buttons["Profile"].isSelected)
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
