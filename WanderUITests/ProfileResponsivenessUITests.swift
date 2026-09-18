import XCTest

@MainActor
final class ProfileResponsivenessUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testColdAndWarmProfileScrolling() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 20))
            startMeasuring()
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.buttons["Feed"].firstMatch.tap()
            app.buttons["Profile"].firstMatch.tap()
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
            stopMeasuring()
            XCTAssertTrue(app.buttons["Settings"].isHittable)
        }
    }

    func testProfileSharePresentsAndCancelsOnColdAndWarmEntry() {
        let app = application()
        app.launch()
        let share = app.buttons["Share profile"]
        XCTAssertTrue(share.waitForExistence(timeout: 20))
        for attempt in 0..<3 {
            let start = Date()
            share.tap()
            let sheet = app.otherElements["ActivityListView"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 3))
            let elapsed = Date().timeIntervalSince(start)
            print("PROFILE_SHARE attempt=\(attempt) presentation_seconds=\(elapsed)")
            // tap() also waits for XCTest quiescence. Record that end-to-end
            // duration, but enforce readiness with the sheet wait above.
            capture("Profile share attempt \(attempt)")
            sheet.swipeDown()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
            XCTAssertTrue(share.waitForExistence(timeout: 3))
            XCTAssertTrue(share.isHittable)
            if attempt == 1 {
                app.buttons["Feed"].firstMatch.tap()
                app.buttons["Profile"].firstMatch.tap()
            }
        }
    }

    func testSettingsDestinationsAndReturnToScrolledProfile() {
        let app = application()
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        app.swipeUp()
        for round in 0..<2 {
            let started = Date()
            settings.tap()
            let back = app.buttons["settings.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            print("PROFILE_SETTINGS round=\(round) entry_seconds=\(Date().timeIntervalSince(started))")

            let notifications = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Notifications")
            ).firstMatch
            notifications.tap()
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            done.tap()
            XCTAssertTrue(back.waitForExistence(timeout: 3))

            for (row, title) in [
                ("settings.map.defaultFilter", "Default map filter"),
                ("Privacy and trust", "Privacy and trust"),
                ("Blocked and muted accounts", "Blocked and muted"),
                ("settings.importHistory", "Import history"),
                ("settings.resources", "Resources")
            ] {
                let link = app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier == %@ OR label == %@", row, row)
                ).firstMatch
                for _ in 0..<24 where !link.isHittable { app.swipeUp(velocity: .fast) }
                XCTAssertTrue(link.isHittable, "Missing Settings destination: \(row)")
                let start = Date()
                link.tap()
                let bar = app.navigationBars[title]
                XCTAssertTrue(bar.waitForExistence(timeout: 3), "Destination: \(row)")
                print("SETTINGS_DESTINATION name=\(row) seconds=\(Date().timeIntervalSince(start))")
                capture("Settings \(row) round \(round)")
                bar.buttons.firstMatch.tap()
                XCTAssertTrue(back.waitForExistence(timeout: 3))
            }
            back.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            XCTAssertTrue(settings.isHittable)
            app.swipeDown()
            app.swipeUp()
        }
        capture("Profile after repeated Settings navigation")
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUsePerformanceFixtures",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "profile"
        ]
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
