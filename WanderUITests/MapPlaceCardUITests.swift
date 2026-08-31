import XCTest

@MainActor
final class MapPlaceCardUITests: XCTestCase {
    func testREC386ShowsMemberPhotoThenDeletesDisposableCheckIn() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderREC386PhotoFixture",
            "-WanderMapPlace", "Dudley Market QA",
            "-WanderMapSheetExpanded",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Dudley Market QA"].firstMatch.waitForExistence(timeout: 8))
        let memberPhoto = app.buttons["Open place photo by Ryan full screen"]
        XCTAssertTrue(memberPhoto.waitForExistence(timeout: 6))
        XCTAssertFalse(memberPhoto.frame.isEmpty)
        XCTAssertTrue(app.descendants(matching: .any)["Photo by Ryan"].waitForExistence(timeout: 3))
        capture("REC-386 member photo visible in gallery")

        let ryanNote = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA proof: Ryan's uploaded check-in photo")
        ).firstMatch
        scrollUp(in: app, until: ryanNote)
        XCTAssertTrue(ryanNote.isHittable)
        let ryanCheckInPhoto = app.buttons["Open check-in photo by Ryan"]
        XCTAssertTrue(ryanCheckInPhoto.waitForExistence(timeout: 3))
        scrollUp(in: app, until: ryanCheckInPhoto)
        XCTAssertTrue(ryanCheckInPhoto.isHittable)
        capture("REC-386 member photo visible in check-in")

        let disposableNote = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA disposable check-in")
        ).firstMatch
        scrollDown(in: app, until: disposableNote)
        XCTAssertTrue(disposableNote.exists)

        let editButton = app.buttons["Edit check-in"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 3))
        editButton.tap()

        let deleteButton = app.buttons["Delete check-in"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 4))
        deleteButton.tap()
        let confirmation = app.alerts["Delete check-in?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Delete check-in"].tap()

        XCTAssertFalse(disposableNote.waitForExistence(timeout: 3))
        XCTAssertTrue(ryanNote.waitForExistence(timeout: 3))
        scrollUp(in: app, until: ryanNote)
        XCTAssertTrue(ryanNote.isHittable)
        capture("REC-386 disposable check-in deleted")
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

    func testRepeatedImageHeavyPlaceProfilePresentationRoundTrips() {
        executionTimeAllowance = 60
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

    func testRepeatedPhotoFallbackPlaceProfilePresentationRoundTrips() {
        executionTimeAllowance = 60
        let app = XCUIApplication()
        app.launchArguments += [
            "-WanderMapCapture",
            "-WanderMapCaptureNoPhotos",
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapCardLocationFixture",
            "-WanderMapPlace",
            "Canyon Lookout Trail"
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

    private func scrollUp(in app: XCUIApplication, until element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func scrollDown(in app: XCUIApplication, until element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeDown()
        }
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
