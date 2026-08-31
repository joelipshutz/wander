import XCTest

@MainActor
final class MapPlaceCardUITests: XCTestCase {
    func testREC352LarchmontCorpusEvidence() {
        let app = launchREC352SearchFixture()
        let searchField = app.textFields["map.searchField"]

        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("larchmont noodles")

        let typeaheadPanel = app.descendants(matching: .any)["map.typeaheadPanel"]
        XCTAssertTrue(typeaheadPanel.waitForExistence(timeout: 5))
        let savedResult = typeaheadPanel.staticTexts["Larchmont Noodles"].firstMatch
        let externalResult = typeaheadPanel.staticTexts["Larchmont Noodles & Ramen"].firstMatch
        XCTAssertTrue(savedResult.waitForExistence(timeout: 5))
        XCTAssertTrue(externalResult.waitForExistence(timeout: 5))
        XCTAssertLessThan(savedResult.frame.minY, externalResult.frame.minY)
        capture("REC-352 Larchmont typeahead")

        searchField.typeText("\n")

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Larchmont Noodles"))
        XCTAssertFalse(card.label.contains("Larchmont Noodles & Ramen"))
        capture("REC-352 Larchmont submitted")
    }

    func testREC352ContextualRankingEvidence() {
        let app = launchREC352SearchFixture()
        let searchField = app.textFields["map.searchField"]

        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("long tables")

        let typeaheadPanel = app.descendants(matching: .any)["map.typeaheadPanel"]
        XCTAssertTrue(typeaheadPanel.waitForExistence(timeout: 5))
        let externalResult = typeaheadPanel.staticTexts["Long Tables Cafe"].firstMatch
        let contextualSavedResult = typeaheadPanel.staticTexts["Fern Desk Coffee"].firstMatch
        XCTAssertTrue(externalResult.waitForExistence(timeout: 5))
        XCTAssertTrue(contextualSavedResult.waitForExistence(timeout: 5))
        XCTAssertLessThan(externalResult.frame.minY, contextualSavedResult.frame.minY)
        capture("REC-352 contextual typeahead")

        searchField.typeText("\n")

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Long Tables Cafe"))
        XCTAssertFalse(card.label.contains("Fern Desk Coffee"))
        capture("REC-352 contextual submitted")
    }

    func testSubmittingMapSearchSelectsTheHighestRankedTrustedPlaceImmediately() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderResetWalkthroughs",
        ]
        app.launch()

        let searchField = app.textFields["map.searchField"]
        let card = app.buttons["map.selectedPlaceCard"]

        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("Circuit Coffee\n")

        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("Circuit Coffee"))
        XCTAssertFalse(app.staticTexts["map.searchMessage"].exists)
    }

    func testCancelingMapSearchDoesNotRevealAnUnrelatedPlaceCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderResetWalkthroughs",
        ]
        app.launch()

        let searchField = app.textFields["map.searchField"]
        let card = app.buttons["map.selectedPlaceCard"]

        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertFalse(card.exists)

        searchField.tap()
        searchField.typeText("coffee")

        let cancelButton = app.buttons["map.searchCancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        XCTAssertFalse(card.waitForExistence(timeout: 2))
    }

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
        XCTAssertTrue(app.buttons["map.selectedPlaceAddToList"].exists)
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchREC352SearchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapSearchFixtures", "rec352",
        ]
        app.launch()
        return app
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
