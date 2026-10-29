import XCTest

@MainActor
final class ListPlaceSearchUITests: XCTestCase {
    func testListSearchMatchesQuickSearchAndPreservesListAddition() {
        let app = XCUIApplication()
        let commonArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"
        ]
        app.launchArguments = commonArguments + ["-WanderOpenAdd"]
        app.launch()
        let quickSearch = app.textFields["add.searchField"]
        XCTAssertTrue(quickSearch.waitForExistence(timeout: 15))
        quickSearch.tap()
        quickSearch.typeText("Sparrow\n")
        XCTAssertTrue(app.buttons["add.candidate.storefront-place-sparrow-bakery"].waitForExistence(timeout: 8))
        let address = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12 Orchard Walk")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let quickSearchSubtitle = address.label
        capture("REC656 quick search place details")

        app.terminate()
        app.launchArguments = commonArguments + ["-WanderInitialTab", "lists"]
        app.launch()
        let list = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open Saturday plan")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        list.tap()
        let addPlaces = app.buttons["Add places to list"]
        XCTAssertTrue(addPlaces.waitForExistence(timeout: 8))
        addPlaces.tap()
        let search = app.textFields["lists.placeSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let suggestion = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "lists.openPlace."
        )).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        suggestion.tap()
        verifyFullProfileAndReturn(app, name: nil, captureName: "REC656 suggested place full profile")
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        search.tap()
        search.typeText("Sparrow")
        let addResult = app.buttons["Add Sparrow Bakery to list"]
        XCTAssertTrue(addResult.waitForExistence(timeout: 8))
        XCTAssertEqual(address.label, quickSearchSubtitle)
        capture("REC656 list search matching place details")
        app.buttons["lists.openSearchPlace.storefront-place-sparrow-bakery"].tap()
        verifyFullProfileAndReturn(app, name: "Sparrow Bakery", captureName: "REC656 searched place full profile")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Sparrow")
        XCTAssertTrue(addResult.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Add silently"].exists)

        // Clearing restores suggestions; a new coordinate query uses the same
        // nearby provider route as quick search, preserving provider order.
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        XCTAssertTrue(app.staticTexts["Suggested for this list"].waitForExistence(timeout: 5))
        search.typeText("34.0522, -118.2437")
        XCTAssertTrue(addResult.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Clover & Pine to list"].exists)
        capture("REC656 list coordinate search")
        let clover = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "lists.openSearchPlace.", "Clover & Pine"
        )).firstMatch
        clover.tap()
        verifyFullProfileAndReturn(app, name: "Clover & Pine", captureName: "REC656 coordinate result full profile")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "34.0522, -118.2437")
        XCTAssertTrue(addResult.waitForExistence(timeout: 8))

        addResult.tap()
        let addSilently = app.buttons["Add silently"]
        XCTAssertTrue(addSilently.waitForExistence(timeout: 5))
        addSilently.tap()
        XCTAssertTrue(addResult.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["No matching places found. Try a more specific name or nearby area."].exists)
        capture("REC656 list search after addition")
    }

    private func verifyFullProfileAndReturn(_ app: XCUIApplication, name: String?, captureName: String) {
        XCTAssertTrue(app.scrollViews["place-profile.scroll"].waitForExistence(timeout: 8))
        if let name {
            XCTAssertTrue(app.staticTexts[name].firstMatch.exists)
        }
        XCTAssertTrue(app.buttons["place-profile.add-to-list"].exists)
        capture(captureName)
        let back = app.buttons["place-profile.back"]
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
