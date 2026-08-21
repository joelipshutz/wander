import XCTest

@MainActor
final class MapPlaceCardUITests: XCTestCase {
    func testMapCardAndSearchDockShareSafeAreaAwareContainerInsets() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapChromeInsetProbe",
            "-WanderMapPlace", "Hearthline Coffee",
        ]
        app.launch()

        let card = app.descendants(matching: .any)["map.selectedPlaceCardSurface"]
        let searchSurface = app.descendants(matching: .any)["map.searchSurface"]
        let addButton = app.buttons["map.headerAdd"]
        let searchField = app.textFields["map.searchField"]
        let window = app.windows.firstMatch

        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(searchSurface.waitForExistence(timeout: 5))
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        assertSharedContainerInsets(
            card: card,
            searchSurface: searchSurface,
            trailingControl: addButton,
            window: window
        )
        capture("REC-316 map chrome collapsed \(Int(window.frame.width))pt")

        searchField.tap()
        let cancelButton = app.buttons["map.searchCancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        assertSharedContainerInsets(
            card: card,
            searchSurface: searchSurface,
            trailingControl: cancelButton,
            window: window
        )
        capture("REC-316 map chrome search-active \(Int(window.frame.width))pt")
    }

    func testSelectedPlaceCardAndVerticalPlacePageRoundTrip() {
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
        let metadataLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Closed"),
            object: card
        )
        XCTAssertEqual(XCTWaiter.wait(for: [metadataLoaded], timeout: 5), .completed)
        XCTAssertTrue(card.label.contains("Coffee shop"))
        XCTAssertTrue(card.label.contains("Rated 4.0"))
        XCTAssertFalse(app.descendants(matching: .any)["map.selectedPlaceRatingProvider"].exists)
        XCTAssertTrue(app.buttons["map.selectedPlaceAction"].exists)
        let shareButton = app.buttons["map.selectedPlaceShare"]
        XCTAssertTrue(shareButton.exists)
        XCTAssertFalse(app.descendants(matching: .any)["map.selectedPlaceAttribution"].exists)
        capture("rec-293-place-card-collapsed")

        shareButton.tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertFalse(activityList.waitForExistence(timeout: 3))

        card.press(forDuration: 0.8)
        XCTAssertTrue(card.exists)

        card.tap()
        XCTAssertTrue(app.staticTexts["Ratings"].waitForExistence(timeout: 8))
        capture("rec-293-place-page-expanded")

        app.buttons["Back"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        capture("rec-293-place-card-returned")
    }

    func testRepeatedImageHeavyPlaceProfilePresentationRoundTrips() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-WanderMapCapture",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapPlace",
            "Hearthline Coffee"
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        for _ in 0..<6 {
            card.tap()
            XCTAssertTrue(app.staticTexts["Ratings"].waitForExistence(timeout: 3))

            app.buttons["Back"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 3))
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSharedContainerInsets(
        card: XCUIElement,
        searchSurface: XCUIElement,
        trailingControl: XCUIElement,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cardFrame = card.frame
        let searchSurfaceFrame = searchSurface.frame
        let trailingControlFrame = trailingControl.frame
        let windowFrame = window.frame

        XCTAssertGreaterThanOrEqual(cardFrame.minX, windowFrame.minX + 11, file: file, line: line)
        XCTAssertLessThanOrEqual(cardFrame.maxX, windowFrame.maxX - 11, file: file, line: line)
        XCTAssertEqual(cardFrame.minX, searchSurfaceFrame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(cardFrame.maxX, trailingControlFrame.maxX, accuracy: 1, file: file, line: line)
    }
}
