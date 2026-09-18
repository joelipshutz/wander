import XCTest

@MainActor final class EventsComingSoonUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testEventsIsMiddleNativeTabAndRepeatedSwitchesPreserveNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "events"]
        app.launch()
        let artwork = app.descendants(matching: .any)["events.comingSoon"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 20))
        let tabs = app.tabBars.firstMatch
        for label in ["Map", "Feed", "Events", "Lists", "Profile"] {
            XCTAssertTrue(tabs.buttons[label].isHittable)
        }
        XCTAssertLessThan(tabs.buttons["Feed"].frame.midX, tabs.buttons["Events"].frame.midX)
        XCTAssertLessThan(tabs.buttons["Events"].frame.midX, tabs.buttons["Lists"].frame.midX)
        capture("Events — native tab bar")
        for label in ["Map", "Feed", "Lists", "Profile", "Map", "Profile", "Feed", "Lists"] {
            tabs.buttons[label].tap()
            XCTAssertTrue(tabs.buttons[label].isSelected)
            tabs.buttons["Events"].tap()
            XCTAssertTrue(tabs.buttons["Events"].isSelected)
            XCTAssertTrue(artwork.waitForExistence(timeout: 2))
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        capture("Events — after switching and foreground return")
    }

    func testTabSwitchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "events"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["events.comingSoon"].firstMatch.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.tabBars.buttons["Profile"].tap()
            app.tabBars.buttons["Events"].tap()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
