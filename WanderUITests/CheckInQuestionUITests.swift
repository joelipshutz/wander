import XCTest

@MainActor
final class CheckInQuestionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshCheckInStartsBlankAndTappingSelectedAnswerClearsIt() {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)

        let options = catalogAnswerButtons(in: app)
        XCTAssertGreaterThan(options.count, 0)
        XCTAssertTrue(options.allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        let first = options.firstMatch
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(first.isSelected)
        first.tap()
        XCTAssertFalse(first.isSelected)
        capture("REC-485 blank optional questions and clearable answer")
    }

    func testWannaKeepsIntroductionNoteAndHidesCheckInQuestions() {
        let app = launchPlace()
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 10))
        wanna.tap()

        XCTAssertTrue(app.textFields["save.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What made you save this?"].exists)
        XCTAssertFalse(app.buttons["save.questions.customize"].exists)
        XCTAssertEqual(catalogAnswerButtons(in: app).count, 0)
        capture("REC-485 Wanna introduction note")
    }

    func testCustomizeReordersRemovesAddsAndPersistsWhenReopened() throws {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        openCustomize(in: app)
        let initialIDs = recurringIDs(in: app)
        XCTAssertEqual(initialIDs.count, 3)
        let firstID = try XCTUnwrap(initialIDs.first)
        let lastID = try XCTUnwrap(initialIDs.last)
        let firstCell = recurringCell(firstID, in: app)
        let lastCell = recurringCell(lastID, in: app)
        XCTAssertTrue(firstCell.exists)
        XCTAssertTrue(lastCell.exists)

        // Drag the native reorder handle, then verify the rendered order.
        lastCell.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        XCTAssertLessThan(recurringElement(lastID, in: app).frame.minY, recurringElement(firstID, in: app).frame.minY)

        let remove = recurringCell(lastID, in: app).buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Delete", "Remove")
        ).firstMatch
        XCTAssertTrue(remove.exists)
        remove.tap()
        let confirmDelete = app.buttons["Delete"].firstMatch
        if confirmDelete.waitForExistence(timeout: 2) { confirmDelete.tap() }
        XCTAssertTrue(recurringElement(lastID, in: app).waitForNonExistence(timeout: 3))

        let addCatalog = app.buttons["save.questions.addCatalog"]
        reveal(addCatalog, in: app)
        addCatalog.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Could you plug in?")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))

        let createCustom = app.buttons["save.questions.createCustom"]
        reveal(createCustom, in: app)
        createCustom.tap()
        let prompt = app.textFields["save.questions.customPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Lots of plants indoors?")
        app.buttons["save.questions.customAdd"].tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 3))
        let customID = try XCTUnwrap(recurringIDs(in: app).first { $0.hasPrefix("custom_question_") })
        let expectedIDs = recurringIDs(in: app)
        capture("REC-485 customized recurring questions")
        app.buttons["save.questions.done"].tap()

        let privateYes = app.buttons["save.question.\(customID).Yes"]
        reveal(privateYes, in: app)
        XCTAssertTrue(privateYes.isHittable)
        XCTAssertFalse(privateYes.isSelected)
        XCTAssertTrue(app.staticTexts["Only you · On this device"].firstMatch.exists)
        privateYes.tap()
        XCTAssertTrue(privateYes.isSelected)
        privateYes.tap()
        XCTAssertFalse(privateYes.isSelected)

        openCustomize(in: app)
        XCTAssertEqual(recurringIDs(in: app), expectedIDs)
        app.buttons["save.questions.done"].tap()
        restoreSuggestions(in: app)
    }

    func testChangingSubtypeChangesPromptsWithoutInventingAnswers() throws {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        let first = catalogAnswerButtons(in: app).firstMatch
        reveal(first, in: app)
        let previousID = first.identifier
        first.tap()

        let subtype = app.buttons["save.placeType.subcategory"]
        reveal(subtype, in: app)
        XCTAssertTrue(subtype.isHittable)
        subtype.tap()
        let search = app.textFields["Search types"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Beach")
        let beach = app.buttons.matching(NSPredicate(format: "label == %@", "Beach")).firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 3))
        beach.tap()
        app.buttons["Done"].firstMatch.tap()

        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app, upwards: false)
        XCTAssertTrue(customize.label.contains("Beach"))
        restoreSuggestions(in: app)
        XCTAssertTrue(catalogAnswerButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        let alsoNoted = app.descendants(matching: .any)["save.questions.alsoNoted"].firstMatch
        reveal(alsoNoted, in: app)
        XCTAssertTrue(alsoNoted.exists)
        alsoNoted.tap()
        let previousAnswer = app.buttons[previousID]
        reveal(previousAnswer, in: app)
        XCTAssertTrue(previousAnswer.isSelected, "Changing type must keep an earlier answer reviewable in Also noted.")
        previousAnswer.tap()
        XCTAssertTrue(previousAnswer.waitForNonExistence(timeout: 3), "Clearing a nonpreferred answer removes it from Also noted.")
        capture("REC-485 subtype change keeps earlier answers reviewable")
    }

    func testAccessibilityTextKeepsAnswerControlsReadableAndTappable() {
        let app = launchPlace(accessibilityText: true)
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        let options = catalogAnswerButtons(in: app)
        let first = options.firstMatch
        reveal(first, in: app)
        XCTAssertTrue(first.isHittable)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertGreaterThanOrEqual(first.frame.width, 44)
        XCTAssertGreaterThanOrEqual(first.frame.minX, 0)
        XCTAssertLessThanOrEqual(first.frame.maxX, app.frame.width)
        first.tap()
        XCTAssertTrue(first.isSelected)
        capture("REC-485 accessibility text editor")
        first.tap()
        openCustomize(in: app)
        capture("REC-485 accessibility text customization")
        app.buttons["save.questions.done"].tap()
    }

    func testRestaurantFoodTypeChangesQuestionsWithoutADuplicateTypePicker() {
        let app = launchPlace(placeName: "Larchmont Noodles")
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        XCTAssertFalse(app.buttons["save.placeType.subcategory"].exists)

        let foodType = app.buttons["save.placeType.cuisine"]
        reveal(foodType, in: app)
        XCTAssertTrue(foodType.isHittable)
        foodType.tap()
        let foodTypeSearch = app.textFields["Search food types"]
        XCTAssertTrue(foodTypeSearch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["Search types"].exists)
        foodTypeSearch.tap()
        foodTypeSearch.typeText("Thai")
        let thai = app.buttons.matching(NSPredicate(format: "label == %@", "Thai")).firstMatch
        reveal(thai, in: app)
        XCTAssertTrue(thai.isHittable)
        thai.tap()
        app.buttons["Done"].firstMatch.tap()

        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app, upwards: false)
        XCTAssertTrue(customize.label.contains("Thai"))
        restoreSuggestions(in: app)
        for id in ["place_detail_spice", "place_detail_vegetarian", "place_detail_sharing"] {
            XCTAssertTrue(app.descendants(matching: .any)["save.question.row.\(id)"].firstMatch.exists)
        }
        XCTAssertTrue(catalogAnswerButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        XCTAssertFalse(app.buttons["save.placeType.subcategory"].exists)
        capture("REC-485 restaurant food type drives useful questions")
    }

    private func launchPlace(placeName: String = "Griffith Observatory Trail", accessibilityText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderMapPlace", placeName,
            "-WanderMapSheetExpanded", "-WanderPlaceProfileSaveTrayV1"
        ]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"]
        }
        app.launch()
        return app
    }

    private func openCheckIn(in app: XCUIApplication) {
        let action = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertTrue(app.buttons["save.questions.customize"].waitForExistence(timeout: 5))
    }

    private func openCustomize(in app: XCUIApplication) {
        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app, upwards: false)
        XCTAssertTrue(customize.isHittable)
        customize.tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 4))
    }

    private func restoreSuggestions(in app: XCUIApplication) {
        openCustomize(in: app)
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()
        app.buttons["save.questions.done"].tap()
    }

    private func catalogAnswerButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save.question.place_detail_"))
    }

    private func recurringIDs(in app: XCUIApplication) -> [String] {
        let prefix = "save.questions.recurring."
        var seen = Set<String>()
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
            .compactMap { element in
                let id = String(element.identifier.dropFirst(prefix.count))
                return seen.insert(id).inserted ? id : nil
            }
    }

    private func recurringElement(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["save.questions.recurring.\(id)"].firstMatch
    }

    private func recurringCell(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.any, identifier: "save.questions.recurring.\(id)").firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<9 where !element.isHittable {
            if upwards { app.swipeUp(velocity: .slow) }
            else { app.swipeDown(velocity: .slow) }
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
