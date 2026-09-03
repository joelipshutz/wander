import XCTest

@MainActor
final class MapPlaceListPickerUITests: XCTestCase {
    func testCollapsedAndFullPlaceCardsOpenTheSameListPicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapPlace", "Hearthline Coffee",
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let collapsedListButton = app.buttons["map.selectedPlaceAddToList"]
        XCTAssertTrue(collapsedListButton.exists)
        capture("REC-342 collapsed place card list icon")
        collapsedListButton.tap()

        XCTAssertTrue(app.otherElements["map-list-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add to lists"].exists)
        XCTAssertTrue(app.buttons["map-list-picker.new-list"].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Only yours")).count,
            0
        )
        XCTAssertTrue(app.buttons["map-list-picker.apply"].label.contains("Done"))
        let existingRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "map-list-picker.list.", "already in list")
        ).firstMatch
        XCTAssertTrue(existingRow.exists)
        XCTAssertFalse(existingRow.isEnabled)
        capture("REC-342 collapsed add-to-list picker")

        let availableRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "map-list-picker.list.", "not selected")
        ).firstMatch
        if availableRow.exists {
            availableRow.tap()
            XCTAssertTrue(availableRow.label.contains("selected"))
        }
        app.buttons["map-list-picker.cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        card.tap()
        let fullListButton = app.buttons["place-profile.add-to-list"]
        let shareButton = app.buttons["place-profile.share"]
        XCTAssertTrue(fullListButton.waitForExistence(timeout: 8))
        XCTAssertTrue(shareButton.exists)
        XCTAssertLessThan(fullListButton.frame.midX, shareButton.frame.midX)
        capture("REC-342 full place profile list position")

        fullListButton.tap()
        XCTAssertTrue(app.otherElements["map-list-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add to lists"].exists)
    }

    func testPerformanceFixtureCoversListsLifecycleWithoutStaleProjections() {
        let app = performanceListsApp()
        app.launch()

        XCTAssertTrue(app.buttons["lists.headerAdd"].waitForExistence(timeout: 12))

        let firstList = app.buttons["Open Realistic list 000, collaborative list"]
        XCTAssertTrue(firstList.waitForExistence(timeout: 5))
        firstList.tap()

        let mapButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "View map for Realistic list 000")
        ).firstMatch
        XCTAssertTrue(mapButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["28 places"].exists)

        app.buttons["Add places to list"].tap()
        XCTAssertTrue(app.staticTexts["add places"].waitForExistence(timeout: 5))

        let addSuggestion = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label ENDSWITH %@ AND label != %@",
                "Add ",
                " to list",
                "Add places to list"
            )
        ).firstMatch
        XCTAssertTrue(addSuggestion.waitForExistence(timeout: 8))
        addSuggestion.tap()

        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["29 places"].waitForExistence(timeout: 8))

        let refreshedMapButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "View map for Realistic list 000")
        ).firstMatch
        XCTAssertTrue(refreshedMapButton.waitForExistence(timeout: 5))
        refreshedMapButton.tap()
        XCTAssertTrue(app.buttons["Close list map"].waitForExistence(timeout: 8))
        app.buttons["Close list map"].tap()
        XCTAssertTrue(app.staticTexts["29 places"].waitForExistence(timeout: 5))

        let laterPlace = app.buttons["Open Museum 0085"]
        reveal(laterPlace, in: app)
        XCTAssertTrue(laterPlace.waitForExistence(timeout: 5))

        let removeLaterPlace = app.buttons["Remove Museum 0085"]
        XCTAssertTrue(removeLaterPlace.exists)
        removeLaterPlace.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            !removeLaterPlace.exists && app.staticTexts["28 places"].exists
        })

        let backButton = app.navigationBars.buttons["Back"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()
        XCTAssertTrue(firstList.waitForExistence(timeout: 8))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.buttons["lists.headerAdd"].waitForExistence(timeout: 12))
        let relaunchedList = app.buttons["Open Realistic list 000, collaborative list"]
        XCTAssertTrue(relaunchedList.waitForExistence(timeout: 5))
        relaunchedList.tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "View map for Realistic list 000")
            ).firstMatch.waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["28 places"].exists)
    }

    func testListCardCountUpdatesAfterRepeatedRemovals() {
        let app = performanceListsApp()
        app.launch()

        let firstList = app.buttons["Open Realistic list 000, collaborative list"]
        XCTAssertTrue(firstList.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["28 places"].exists)
        firstList.tap()
        XCTAssertTrue(app.staticTexts["28 places"].waitForExistence(timeout: 8))

        for expectedCount in stride(from: 27, through: 25, by: -1) {
            let removeButton = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Remove ")
            ).firstMatch
            reveal(removeButton, in: app)
            XCTAssertTrue(removeButton.isHittable)
            removeButton.tap()
            XCTAssertTrue(app.staticTexts["\(expectedCount) places"].waitForExistence(timeout: 8))
        }

        app.navigationBars.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(firstList.waitForExistence(timeout: 8))
        capture("REC-416 list card after three removals")
        XCTAssertTrue(app.staticTexts["25 places"].waitForExistence(timeout: 5))

        firstList.tap()
        XCTAssertTrue(app.staticTexts["25 places"].waitForExistence(timeout: 8))
    }

    func testPerformanceFixtureColdListDetailIsImmediatelyScrollable() {
        let app = performanceListsApp()
        app.launch()

        let firstList = app.buttons["Open Realistic list 000, collaborative list"]
        XCTAssertTrue(firstList.waitForExistence(timeout: 12))
        let openStartedAt = Date()
        firstList.tap()

        let mapButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "View map for Realistic list 000")
        ).firstMatch
        XCTAssertTrue(mapButton.waitForExistence(timeout: 8))
        XCTAssertLessThan(
            Date().timeIntervalSince(openStartedAt),
            8,
            "Cold list detail should not block interaction while suggestions are prepared."
        )

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        let initialMapY = mapButton.frame.minY
        var didMeasureColdSwipe = false

        if #available(iOS 19.0, *) {
            var invocationCount = 0
            let options = XCTMeasureOptions()
            options.iterationCount = 1
            options.invocationOptions = [.manuallyStart, .manuallyStop]

            measure(metrics: [XCTHitchMetric(application: app)], options: options) {
                invocationCount += 1
                startMeasuring()
                defer { stopMeasuring() }
                guard invocationCount > 1 else { return }
                scrollView.swipeUp(velocity: .fast)
                didMeasureColdSwipe = true
            }
        } else {
            scrollView.swipeUp(velocity: .fast)
            didMeasureColdSwipe = true
        }

        XCTAssertTrue(didMeasureColdSwipe)
        XCTAssertTrue(
            !mapButton.isHittable || mapButton.frame.minY < initialMapY - 20,
            "The measured first swipe should move list-detail content."
        )

        let suggestionsHeader = app.staticTexts["suggested places"]
        reveal(suggestionsHeader, in: app)
        XCTAssertTrue(suggestionsHeader.waitForExistence(timeout: 8))

        let addSuggestion = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label ENDSWITH %@ AND label != %@",
                "Add ",
                " to list",
                "Add places to list"
            )
        ).firstMatch
        XCTAssertTrue(
            addSuggestion.waitForExistence(timeout: 8),
            "Lazy suggestion loading should preserve the inline add flow."
        )
    }

    private func performanceListsApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab", "lists",
        ]
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        for _ in 0..<8 where !element.exists || !element.isHittable {
            scrollView.swipeUp(velocity: .fast)
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
