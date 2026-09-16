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
        XCTAssertTrue(addCatalog.isEnabled, "Adding a question stays available while native reorder controls are shown.")
        addCatalog.tap()
        let catalogStealth = app.switches["save.questions.catalogStealth"]
        XCTAssertTrue(catalogStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(catalogStealth.value as? String, "0")
        catalogStealth.tap()
        XCTAssertEqual(catalogStealth.value as? String, "1")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("outlet")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(recurringElement("place_detail_outlets", in: app).value as? String, "Stealth")

        let createCustom = app.buttons["save.questions.createCustom"]
        reveal(createCustom, in: app)
        XCTAssertTrue(createCustom.isEnabled, "Creating a question stays available while native reorder controls are shown.")
        createCustom.tap()
        let customStealth = app.switches["save.questions.customStealth"]
        XCTAssertTrue(customStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(customStealth.value as? String, "1")
        reveal(customStealth, in: app)
        customStealth.tap()
        XCTAssertEqual(customStealth.value as? String, "0")
        let prompt = app.textFields["save.questions.customPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        reveal(prompt, in: app, upwards: false)
        prompt.tap()
        prompt.typeText("Lots of plants indoors?")
        app.buttons["save.questions.customAdd"].tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 3))
        let customID = try XCTUnwrap(recurringIDs(in: app).first { $0.hasPrefix("custom_question_") })
        XCTAssertEqual(recurringElement(customID, in: app).value as? String, "Check-in audience")
        let expectedIDs = recurringIDs(in: app)
        capture("REC-485 customized recurring questions")
        app.buttons["save.questions.done"].tap()

        let customYes = app.buttons["save.question.\(customID).Yes"]
        reveal(customYes, in: app)
        XCTAssertTrue(customYes.isHittable)
        XCTAssertFalse(customYes.isSelected)
        customYes.tap()
        XCTAssertTrue(customYes.isSelected)
        customYes.tap()
        XCTAssertFalse(customYes.isSelected)

        openCustomize(in: app)
        XCTAssertEqual(recurringIDs(in: app), expectedIDs)
        recurringElement(customID, in: app).tap()
        let selectedStealth = app.switches["save.questions.selectedStealth"]
        XCTAssertTrue(selectedStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(selectedStealth.value as? String, "0")
        selectedStealth.tap()
        XCTAssertEqual(selectedStealth.value as? String, "1")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(recurringElement(customID, in: app).value as? String, "Stealth")
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
        reveal(customize, in: app)
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
        reveal(customize, in: app)
        XCTAssertTrue(customize.label.contains("Thai"))
        restoreSuggestions(in: app)
        for id in ["place_detail_dog_access", "place_detail_spice", "place_detail_vegetarian"] {
            XCTAssertTrue(app.descendants(matching: .any)["save.question.row.\(id)"].firstMatch.exists)
        }
        XCTAssertTrue(catalogAnswerButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        XCTAssertFalse(app.buttons["save.placeType.subcategory"].exists)
        capture("REC-485 restaurant food type drives useful questions")
    }

    func testSettingsManagesQuestionsWithoutOpeningAPlace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderOpenSettings"
        ]
        app.launch()
        let entry = app.descendants(matching: .any)["settings.checkInQuestions"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        reveal(entry, in: app)
        entry.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Volleyball court")
        let scope = app.buttons["questions.settings.scope.wellness_fitness:volleyball court"]
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        scope.tap()
        let openedEditor = app.buttons["save.questions.done"].waitForExistence(timeout: 8)
        if !openedEditor { capture("REC-485 Settings subtype presentation failure") }
        XCTAssertTrue(openedEditor, "Question rows: \(recurringIDs(in: app).count); add control: \(app.buttons["save.questions.addCatalog"].exists)")
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()

        let add = app.buttons["save.questions.addCatalog"]
        reveal(add, in: app, upwards: false)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.switches["save.questions.catalogStealth"].waitForExistence(timeout: 3))
        let questionSearch = app.searchFields.firstMatch
        questionSearch.tap()
        questionSearch.typeText("outlet")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        app.buttons["save.questions.done"].tap()
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        scope.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        capture("REC-485 Settings question management")
        reveal(restore, in: app)
        restore.tap()
        app.buttons["save.questions.done"].tap()
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
        XCTAssertTrue(app.scrollViews["save.editorScroll"].waitForExistence(timeout: 10))
    }

    private func openCustomize(in app: XCUIApplication) {
        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app)
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
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let id = exists ? element.identifier : ""
            let composerTarget = id == "save.questions.customize" || id == "save.questions.alsoNoted"
                || id.hasPrefix("save.question.") || id.hasPrefix("save.placeType.")
            let editor = app.scrollViews["save.editorScroll"]
            let surface = composerTarget && editor.isHittable ? editor : app
            let viewport = surface.frame.intersection(app.frame)
            let scrollUp = frame.isEmpty ? upwards : frame.midY >= viewport.midY
            // Start in the form's side gutter. A whole-screen swipe can land
            // on the rating slider and change the score instead of scrolling.
            let top = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25))
            let bottom = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75))
            (scrollUp ? bottom : top).press(forDuration: 0.05, thenDragTo: scrollUp ? top : bottom)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
