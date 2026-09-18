import XCTest

@MainActor
final class ImportFormRefinementUITests: XCTestCase {
    func testShareExtensionAutomaticallyCapturesExactlyOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationShare"]
        app.launch()
        XCTAssertTrue(app.buttons["Clear test captures"].waitForExistence(timeout: 15))
        app.buttons["Clear test captures"].tap()
        defer { if app.buttons["Clear test captures"].isHittable { app.buttons["Clear test captures"].tap() } }
        app.buttons["Share test link"].tap()
        let activity = app.cells.matching(NSPredicate(format: "label == %@", "Astir")).firstMatch
        if !activity.waitForExistence(timeout: 5) {
            let more = app.buttons["More"].firstMatch
            if more.exists { more.tap() }
        }
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        let countdownAvailable = app.buttons["share-extension-start-import"].waitForExistence(timeout: 5)
        keepScreenshot("Share extension — countdown begins")
        let sharedInboxUnavailable = app.staticTexts["Astir could not access its shared inbox. Check the app and extension App Group signing."]
        if sharedInboxUnavailable.waitForExistence(timeout: 6) {
            keepScreenshot("Share extension — appearance without Simulator App Group signing")
            throw XCTSkip("This Simulator build has no App Group container; durable extension capture requires a signed App Group build.")
        }
        XCTAssertTrue(countdownAvailable)
        let captured = app.staticTexts["Captured: 1"]
        XCTAssertTrue(captured.waitForExistence(timeout: 20), "The real extension should durably capture once after its timer")
        XCTAssertFalse(app.staticTexts["Captured: 2"].exists)
        keepScreenshot("Share extension — automatic capture returned to host")
    }

    func testMapImportNoticeTracksFiltersAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderMapCapture", "-WanderImportNoticeUITest", "-WanderDisableWalkthroughs"]
        app.launch()
        let dismiss = app.buttons["import.notice.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 15))
        let filters = app.buttons["map.filter.more"]
        XCTAssertTrue(filters.exists)
        let review = app.buttons["import.notice.review"]
        let filterRow = app.otherElements["map.filters"]
        // Liquid Glass accessibility bounds differ from SwiftUI's layout
        // anchor by a few points; the rendered gap should remain about 10pt.
        // The primary button's accessibility frame excludes its 12pt vertical
        // content padding. The X glyph is centered on the actual card edge,
        // while its full 44pt hit target remains inside the card and window.
        let cardTop = review.frame.minY - 12
        XCTAssertEqual(cardTop - filterRow.frame.maxY, 10, accuracy: 3)
        XCTAssertEqual(dismiss.frame.minY, cardTop, accuracy: 1)
        XCTAssertEqual(dismiss.frame.maxX, review.frame.maxX + 64, accuracy: 1)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 64)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 64)
        XCTAssertLessThanOrEqual(dismiss.frame.maxX, app.frame.maxX)
        keepScreenshot("Import notice — anchored below filters")
        dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)).tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        XCTAssertTrue(filters.isHittable)
    }

    func testFailedSourceRemainsRecoverableInCanonicalReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationRecovery"]
        app.launch()
        XCTAssertTrue(app.buttons["import.retry"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Oops that link didn't work"].exists)
        XCTAssertFalse(app.staticTexts["No places matched"].exists)
        keepScreenshot("Import report — source retry")
    }

    func testPartialImportReportShowsSavedAndRemainingPlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Saved (1)"].waitForExistence(timeout: 15))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["9 places matched and ready"].exists)
        XCTAssertFalse(app.buttons["Review and add places"].exists)
        XCTAssertTrue(app.buttons["import.list.report-place-1"].exists)
        XCTAssertTrue(app.navigationBars["Import report"].exists)
        keepScreenshot("Import report — inline review")
    }

    func testSuccessfulReportDoesNotShowSourceRetryFooter() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Saved (1)"].waitForExistence(timeout: 15))
        for _ in 0..<12 { app.swipeUp() }
        XCTAssertFalse(app.buttons["import.retry"].exists)
        XCTAssertFalse(app.staticTexts["Oops that link didn't work"].exists)
        XCTAssertFalse(app.buttons["import.try-again"].exists)
        keepScreenshot("Import report — successful partial scan has no failure footer")
    }

    func testLowCoverageReturnsToImportEntryWithCopiedLink() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationPartial"]
        app.launch()
        let tryAgain = app.buttons["import.try-again"]
        for _ in 0..<5 where !tryAgain.isHittable { app.swipeUp() }
        XCTAssertTrue(tryAgain.isHittable)
        XCTAssertTrue(app.staticTexts["We weren't able to resolve all places"].exists)
        XCTAssertFalse(app.buttons["import.retry"].exists)
        keepScreenshot("Import report — low coverage warning")
        tryAgain.tap()
        XCTAssertTrue(app.textFields["import.input"].waitForExistence(timeout: 5))
        app.buttons["Paste from clipboard"].tap()
        XCTAssertEqual(app.textFields["import.input"].value as? String, "https://example.com/recme-import-ui-fixture")
        keepScreenshot("Import report — try again returns to entry with source copied")
    }

    func testImportActionsShareCompactBottomRow() {
        let app = XCUIApplication()
        // This assertion covers the standard-text horizontal layout. At
        // accessibility sizes, ViewThatFits intentionally stacks the actions.
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReview",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let wanna = app.buttons["import.wanna.capture-instagram-0"]
        for _ in 0..<5 where !wanna.isHittable || wanna.frame.maxY > app.frame.height - 120 { app.swipeUp() }
        let details = app.buttons["import.details.capture-instagram-0"]
        XCTAssertTrue(wanna.isHittable)
        XCTAssertTrue(details.isHittable)
        // Text/chevron accessibility bounds differ from the circular action's
        // layout bounds by 3pt on iOS 26.5. Screenshots confirm one centered row.
        XCTAssertEqual(wanna.frame.midY, details.frame.midY, accuracy: 4)
        XCTAssertGreaterThanOrEqual(wanna.frame.height, 44)
        XCTAssertLessThan(details.frame.maxX, wanna.frame.minX)
        keepScreenshot("Import report — compact bottom actions")
    }

    func testPlinthProgressStagesInLightAndDark() {
        let app = XCUIApplication()
        for appearance in ["Dark", "Light"] {
            app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationProgress"]
            if appearance == "Dark" { app.launchArguments.append("-WanderImportDarkAppearance") }
            app.launch()
            XCTAssertTrue(app.staticTexts["Resolved 17 out of 17 places"].waitForExistence(timeout: 15))
            keepScreenshot("Import plinth — \(appearance) — zero, partial, and complete")
            app.terminate()
        }
    }

    func testSingleInlineSaveLeavesOtherMatchesAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        let action = app.buttons["import.checkin.report-place-1"]
        scrollToImportControl(action, in: app)
        keepScreenshot("Import report — single save before physical tap")
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(action.value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Saved (2)"].exists)
        XCTAssertTrue(app.buttons["import.wanna.report-place-2"].isEnabled)
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(app.staticTexts["Saved (2)"], in: app)
        XCTAssertTrue(app.staticTexts["Saved (2)"].exists)
        XCTAssertTrue(app.staticTexts["8 places matched and ready"].exists)
    }

    func testBulkStatusOnlyHighlightsUntilSave() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        let all = app.buttons["import.all.wanna"]
        for _ in 0..<5 where !all.isHittable || all.frame.maxY > app.frame.height - 120 { app.swipeUp() }
        all.tap()
        XCTAssertEqual(all.value as? String, "Selected")
        XCTAssertEqual(app.buttons["import.wanna.report-place-1"].value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Saved (10)"].exists)
        let checkIn = app.buttons["import.checkin.report-place-1"]
        scrollToImportControl(checkIn, in: app)
        checkIn.tap()
        XCTAssertEqual(checkIn.value as? String, "Selected")
        XCTAssertTrue(app.buttons["import.save"].isEnabled)
        keepScreenshot("Import report — staged choices")
        saveAndReopenImport(app, expectedBadge: "0")
        scrollToImportControl(app.staticTexts["Saved (10)"], in: app)
        XCTAssertTrue(app.staticTexts["Saved (10)"].exists)
        XCTAssertFalse(app.buttons["import.save"].exists)
        XCTAssertFalse(app.buttons["import.all.wanna"].exists)
        keepScreenshot("Import report — all saved, no bulk controls")
    }

    func testHistoryArtworkCannotStealAdjacentTileTaps() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationHistory"]
        app.launch()
        let left = app.buttons["import.history.capture-instagram"]
        XCTAssertTrue(left.waitForExistence(timeout: 15))
        // The neighboring Google Maps image has oversized aspect-fill content.
        // Its clipped pixels must not own the right edge of the left tile.
        left.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.3)).tap()
        XCTAssertTrue(app.navigationBars["Import report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["@coffeeguide"].exists)
        keepScreenshot("History — left edge opens the selected post")
    }

    func testSavedImportKeepsCardLayoutAndSelectionsUntilResaved() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport", "-WanderImportCompactReport"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Import report"].waitForExistence(timeout: 15))

        let itemID = "report-place-1"
        let checkIn = app.buttons["import.checkin.\(itemID)"]
        scrollToImportControl(checkIn, in: app)
        let readyCard = app.otherElements["import.ready-card.\(itemID)"]
        let readyHeight = readyCard.frame.height
        XCTAssertGreaterThan(readyHeight, 100)
        XCTAssertLessThan(app.staticTexts["Ready to add"].frame.minY, app.staticTexts["Saved (1)"].frame.minY)

        checkIn.tap()
        let list = app.buttons["import.list.\(itemID)"]
        list.tap()
        let listRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-list-picker.list.")).firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(checkIn.value as? String, "Selected")
        XCTAssertEqual(list.value as? String, "Selected")
        saveAndReopenImport(app)

        let savedCard = app.otherElements["import.saved-card.\(itemID)"]
        let savedCheckIn = app.buttons["import.saved-checkin.\(itemID)"]
        scrollToImportControl(savedCheckIn, in: app)
        XCTAssertEqual(savedCard.value as? String, "Saved")
        XCTAssertEqual(savedCard.frame.height, readyHeight, accuracy: 1)
        XCTAssertEqual(savedCheckIn.value as? String, "Selected")
        XCTAssertEqual(app.buttons["import.saved-list.\(itemID)"].value as? String, "Selected")
        keepScreenshot("Import report — green saved edge and preserved selections")

        let savedWanna = app.buttons["import.saved-wanna.\(itemID)"]
        savedWanna.tap()
        XCTAssertTrue(app.alerts["Change to Wanna?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Change to Wanna"].tap()
        XCTAssertEqual(savedCard.value as? String, "Unsaved changes")
        XCTAssertEqual(savedWanna.value as? String, "Selected")
        XCTAssertTrue(app.buttons["import.save"].isEnabled)
        keepScreenshot("Import report — changed selection removes saved edge")
        saveAndReopenImport(app)
        scrollToImportControl(savedWanna, in: app)
        XCTAssertTrue(savedCard.waitForExistence(timeout: 5))
        XCTAssertEqual(savedCard.value as? String, "Saved")
        XCTAssertEqual(savedWanna.value as? String, "Selected")
        XCTAssertEqual(app.buttons["import.saved-list.\(itemID)"].value as? String, "Selected")
        keepScreenshot("Import report — resaved Wanna restores green edge")
    }

    func testListOnlyEditRemovesSavedEdgeUntilSaveAndEmptyReadySectionDisappears() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport", "-WanderImportCompactReport", "-WanderImportDarkAppearance"]
        app.launch()
        let all = app.buttons["import.all.wanna"]
        scrollToImportControl(all, in: app)
        all.tap()
        saveAndReopenImport(app)
        XCTAssertTrue(app.staticTexts["Saved (3)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ready to add"].exists)
        XCTAssertFalse(app.buttons["import.all.wanna"].exists)
        XCTAssertFalse(app.buttons["import.save"].exists)

        let itemID = "report-place-0"
        let list = app.buttons["import.saved-list.\(itemID)"]
        scrollToImportControl(list, in: app)
        let card = app.otherElements["import.saved-card.\(itemID)"]
        XCTAssertEqual(card.value as? String, "Saved")
        list.tap()
        let listRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-list-picker.list.")).firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(card.value as? String, "Unsaved changes")
        XCTAssertEqual(list.value as? String, "Selected")
        saveAndReopenImport(app)
        scrollToImportControl(list, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Saved")
        XCTAssertEqual(list.value as? String, "Selected")
        XCTAssertFalse(app.buttons["import.save"].exists)
        keepScreenshot("Import report — dark saved list-only edit complete")
    }

    func testSavedWannaCanBeCancelledThenRemovedAndReselectedAfterReopening() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport", "-WanderImportCompactReport"]
        app.launch()
        let wanna = app.buttons["import.saved-wanna.report-place-0"]
        scrollToImportControl(wanna, in: app)
        let card = app.otherElements["import.saved-card.report-place-0"]
        wanna.tap()
        XCTAssertTrue(app.alerts["Remove Wanna?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(wanna.value as? String, "Selected")
        XCTAssertEqual(card.value as? String, "Saved")
        wanna.tap()
        app.alerts.buttons["Remove Wanna"].tap()
        XCTAssertEqual(wanna.value as? String, "Not selected")
        XCTAssertEqual(card.value as? String, "Unsaved changes")
        keepScreenshot("Import report — confirmed Wanna removal is staged")
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(wanna, in: app)
        XCTAssertEqual(wanna.value as? String, "Not selected")
        XCTAssertEqual(card.value as? String, "Saved")
        wanna.tap()
        XCTAssertEqual(wanna.value as? String, "Selected")
        XCTAssertEqual(card.value as? String, "Unsaved changes")
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(wanna, in: app)
        XCTAssertEqual(wanna.value as? String, "Selected")
        XCTAssertEqual(card.value as? String, "Saved")
    }

    func testSavedCheckInAndListsCanBeRemovedWithConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport", "-WanderImportCompactReport"]
        app.launch()
        let checkIn = app.buttons["import.checkin.report-place-1"]
        scrollToImportControl(checkIn, in: app)
        checkIn.tap()
        app.buttons["import.list.report-place-1"].tap()
        let listRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-list-picker.list.")).firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.tap()
        app.buttons["Done"].tap()
        saveAndReopenImport(app, expectedBadge: "1")

        let savedCheckIn = app.buttons["import.saved-checkin.report-place-1"]
        let savedList = app.buttons["import.saved-list.report-place-1"]
        scrollToImportControl(savedCheckIn, in: app)
        savedCheckIn.tap()
        XCTAssertTrue(app.alerts["Remove Check In?"].waitForExistence(timeout: 5))
        keepScreenshot("Import report — check-in metadata warning")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(savedCheckIn.value as? String, "Selected")
        savedCheckIn.tap()
        app.alerts.buttons["Remove Check In"].tap()
        XCTAssertEqual(savedCheckIn.value as? String, "Not selected")
        XCTAssertEqual(savedList.value as? String, "Selected")
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(savedList, in: app)
        XCTAssertEqual(savedCheckIn.value as? String, "Not selected")
        savedList.tap()
        XCTAssertTrue(app.alerts["Remove from lists?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(savedList.value as? String, "Selected")
        savedList.tap()
        app.alerts.buttons["Remove from lists"].tap()
        XCTAssertEqual(savedList.value as? String, "Not selected")
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(savedList, in: app)
        XCTAssertEqual(savedCheckIn.value as? String, "Not selected")
        XCTAssertEqual(savedList.value as? String, "Not selected")
    }

    private func saveAndReopenImport(_ app: XCUIApplication, expectedBadge: String? = nil) {
        app.buttons["import.save"].tap()
        let reopen = app.buttons["import.open-report"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5), "Save closes the report")
        if let expectedBadge { XCTAssertEqual(app.staticTexts["import.capture-badge"].label, expectedBadge) }
        reopen.tap()
        XCTAssertTrue(app.navigationBars["Import report"].waitForExistence(timeout: 5))
    }

    private func scrollToImportControl(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable || element.frame.maxY > app.frame.height - 120 {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    func testSavedImportPlaceOpensItsProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        let saved = app.buttons["import.saved.report-place-0"]
        for _ in 0..<5 where !saved.isHittable { app.swipeUp() }
        XCTAssertTrue(saved.isHittable)
        saved.tap()
        XCTAssertTrue(app.staticTexts["Maru Coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["import.save"].exists)
        keepScreenshot("Saved import — place profile")
    }

    func testListChoiceWaitsForSaveAlongsideCheckIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        let lists = app.buttons["import.list.report-place-1"]
        for _ in 0..<5 where !lists.isHittable || lists.frame.maxY > app.frame.height - 120 { app.swipeUp() }
        lists.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-list-picker.list.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Saved (2)"].exists)
        XCTAssertEqual(lists.value as? String, "Selected")
        keepScreenshot("Import list — selected sky-blue outline")
        app.buttons["import.checkin.report-place-1"].tap()
        XCTAssertEqual(lists.value as? String, "Selected")
        XCTAssertEqual(app.buttons["import.checkin.report-place-1"].value as? String, "Selected")
        saveAndReopenImport(app, expectedBadge: "1")
        scrollToImportControl(app.staticTexts["Saved (2)"], in: app)
        XCTAssertTrue(app.staticTexts["Saved (2)"].exists)
    }

    func testAuthorAppearsInReportButNotHistoryTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationHistory"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Neighborhood coffee stops"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["@coffeeguide"].exists)
        app.terminate()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationReport"]
        app.launch()
        XCTAssertTrue(app.staticTexts["@coffeeguide"].waitForExistence(timeout: 15))
        keepScreenshot("Import report — source author")
    }

    func testInlineImportDetailsUseTheCardSurface() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationDetails"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Import report"].waitForExistence(timeout: 15))
        let more = app.buttons["Hide more options"].firstMatch
        // The center of this long form contains an interactive rating slider.
        // Scroll from the page margin so the gesture cannot adjust the rating
        // instead of revealing the fields below it.
        for _ in 0..<8 where !more.isHittable || more.frame.maxY > app.frame.height - 120 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30)
                ))
        }
        XCTAssertTrue(more.isHittable)
        keepScreenshot("Import report — inline details")
    }

    func testHistoryCanDeleteMultipleImports() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderImportImplementationHistory"]
        app.launch()
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 15))
        app.buttons["Select"].tap()
        app.buttons["Select all"].tap()
        app.buttons["Delete (5)"].tap()
        XCTAssertTrue(app.buttons["Delete imports"].waitForExistence(timeout: 5))
        app.buttons["Delete imports"].tap()
        XCTAssertTrue(app.staticTexts["No import history yet"].waitForExistence(timeout: 5))
    }

    func testHistoryBadgeOverlapsTheGlassButtonAfterStartingAnImport() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderMapCapture", "-WanderOpenImportHub", "-WanderDisableWalkthroughs"]
        app.launch()
        let input = app.textFields["import.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        let history = app.buttons["import.history"]
        let originalCount = Int((history.value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
        input.tap()
        input.typeText("REC409 badge layout fixture")
        app.buttons["import.start"].tap()
        let add = app.buttons["map.headerAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let shortcut = app.buttons["Import your places and lists from Google Maps, Instagram, TikTok, and more here"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        shortcut.tap()
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertEqual(history.value as? String, "\(originalCount + 1) imports matching or awaiting review")
        keepScreenshot("Recents — badge overlaps glass border")
        history.tap()
        XCTAssertTrue(app.navigationBars["Import history"].waitForExistence(timeout: 5))
    }

    func testImportFormReturnsToCompactHeightAfterKeyboardAndDragging() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderMapCapture",
            "-WanderOpenImportHub", "-WanderDisableWalkthroughs"
        ]
        app.launch()
        let input = app.textFields["import.input"]
        let clipboard = app.buttons["Paste from clipboard"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertTrue(clipboard.isHittable)
        // Wait for the measured detent to replace the initial presentation
        // height before recording the baseline or testing later openings.
        let firstPresentationSettles = NSPredicate { _, _ in
            app.frame.maxY - clipboard.frame.maxY < 65
        }
        expectation(for: firstPresentationSettles, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        let firstTop = app.buttons["Close import"].frame.minY
        XCTAssertLessThan(app.frame.maxY - clipboard.frame.maxY, 65)
        keepScreenshot("Import entry — first open")

        let inputContainer = app.otherElements["import.input-container"]
        XCTAssertTrue(inputContainer.exists)
        let inputContainerHeight = inputContainer.frame.height
        inputContainer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 10) else {
            keepScreenshot("Import entry — field did not focus")
            XCTFail("Tapping the full-height input container should open the keyboard")
            return
        }
        input.typeText("https://www.instagram.com/p/very-long-single-line-import-link-that-must-never-wrap/")
        // Accessibility bounds shift slightly when placeholder metrics are
        // replaced by URL text even though the rendered control stays one line.
        XCTAssertEqual(inputContainer.frame.height, inputContainerHeight, accuracy: 3)
        XCTAssertLessThanOrEqual(inputContainer.frame.height, 65)
        XCTAssertLessThan(input.frame.height, 30)
        app.buttons["Close import"].tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))

        for opening in 2...3 {
            XCTAssertTrue(app.buttons["map.headerAdd"].waitForExistence(timeout: 5))
            app.buttons["map.headerAdd"].tap()
            let shortcut = app.buttons["Import your places and lists from Google Maps, Instagram, TikTok, and more here"]
            XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
            shortcut.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            let settlesAtCompactHeight = NSPredicate { _, _ in
                // Liquid Glass accessibility bounds can shift by a few points
                // between otherwise identical sheet presentations.
                abs(app.buttons["Close import"].frame.minY - firstTop) <= 3
            }
            expectation(for: settlesAtCompactHeight, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(clipboard.isHittable)
            XCTAssertLessThan(app.frame.maxY - clipboard.frame.maxY, 65)
            keepScreenshot("Import entry — open \(opening)")
            let handle = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.midX, dy: firstTop - 10))
            handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -220)))
            app.buttons["Close import"].tap()
            XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        }
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class OnboardingUITests: XCTestCase {
    func testNotificationUpsellUsesTheCentralCampaignInOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "notifications",
            "-WanderNotificationAuthorizationNotDeterminedFixture",
            "-WanderBypassProductUpsellFrequencyCap"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["See when your friends check in"].waitForExistence(timeout: 8))
        let notificationContinue = app.buttons["productUpsell.primary"]
        XCTAssertTrue(notificationContinue.waitForExistence(timeout: 8))
        XCTAssertTrue(notificationContinue.isHittable)
        XCTAssertFalse(app.buttons["productUpsell.secondary"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["Onboarding step 5 of 5"].exists
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-425 notification upsell in onboarding"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testContextualNotificationUpsellsUseConfiguredSaveAndFollowCopy() {
        let app = XCUIApplication()
        let baseArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderNotificationAuthorizationNotDeterminedFixture"
        ]

        app.launchArguments = baseArguments + [
            "-WanderProductUpsellTrigger",
            "place_saved"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["See when your friends check in"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["productUpsell.primary"].isHittable)
        XCTAssertFalse(app.buttons["productUpsell.secondary"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Onboarding step 5 of 5"].exists)

        let saveScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        saveScreenshot.name = "REC-425 notification upsell after first save"
        saveScreenshot.lifetime = .keepAlways
        add(saveScreenshot)

        app.terminate()
        app.launchArguments = baseArguments + [
            "-WanderProductUpsellTrigger",
            "follow_created"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Keep up with people you follow"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["productUpsell.primary"].isHittable)
        XCTAssertFalse(app.buttons["productUpsell.secondary"].exists)

        let followScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        followScreenshot.name = "REC-425 notification upsell after first follow"
        followScreenshot.lifetime = .keepAlways
        add(followScreenshot)
    }

    func testActualOnboardingPermissionScreensUseSingleNeutralAction() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        addTeardownBlock {
            app.terminate()
            app.resetAuthorizationStatus(for: .location)
            app.resetAuthorizationStatus(for: .contacts)
        }
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "location"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Find the good stuff nearby"].waitForExistence(timeout: 8))
        let locationContinue = app.buttons["Continue"].firstMatch
        XCTAssertTrue(locationContinue.waitForExistence(timeout: 8))
        XCTAssertEqual(locationContinue.label, "Continue")
        XCTAssertFalse(app.buttons["Not now"].exists)

        let locationScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        locationScreenshot.name = "REC-396 actual onboarding location permission"
        locationScreenshot.lifetime = .keepAlways
        add(locationScreenshot)

        locationContinue.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let locationAlert = springboard.alerts.firstMatch
        XCTAssertTrue(locationAlert.waitForExistence(timeout: 5))
        let denyLocation = locationAlert.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])
        ).firstMatch
        XCTAssertTrue(denyLocation.exists)
        denyLocation.tap()
        XCTAssertTrue(locationAlert.waitForNonExistence(timeout: 5))

        app.terminate()
        app.resetAuthorizationStatus(for: .location)
        app.resetAuthorizationStatus(for: .contacts)
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "contacts"
        ]
        app.launch()

        let contactsContinue = app.buttons["Continue"].firstMatch
        XCTAssertTrue(contactsContinue.waitForExistence(timeout: 8))
        XCTAssertTrue(contactsContinue.isHittable)
        XCTAssertFalse(app.buttons["Not now"].exists)

        let contactsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        contactsScreenshot.name = "REC-396 actual onboarding contacts permission"
        contactsScreenshot.lifetime = .keepAlways
        add(contactsScreenshot)
    }

    func testActualOnboardingNotificationPrimerMatchesAuthorizationState() {
        let app = XCUIApplication()
        addTeardownBlock { app.terminate() }
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "notifications",
            "-WanderBypassProductUpsellFrequencyCap"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["See when your friends check in"].waitForExistence(timeout: 8))
        let notificationContinue = app.buttons["productUpsell.primary"]
        XCTAssertTrue(notificationContinue.waitForExistence(timeout: 8))
        XCTAssertTrue(notificationContinue.isHittable)
        let secondary = app.buttons["productUpsell.secondary"]
        if secondary.exists {
            XCTAssertTrue(
                ["Continue", "Open Settings"].contains(notificationContinue.label)
            )
            XCTAssertEqual(secondary.label, "Not now")
        } else {
            XCTAssertEqual(notificationContinue.label, "Continue")
            notificationContinue.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let deny = alert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
            }
        }
    }

    func testActualFeedContactInvitePrimerUsesSingleNeutralAction() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .contacts)
        addTeardownBlock {
            app.terminate()
            app.resetAuthorizationStatus(for: .contacts)
        }
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderMapCapture",
            "-WanderUseEphemeralEmptyFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderFeedSurface",
            "people"
        ]
        app.launch()

        let inviteEntry = app.buttons["invite people to Astir"]
        XCTAssertTrue(inviteEntry.waitForExistence(timeout: 8))
        inviteEntry.tap()

        let permissionContinue = app.buttons["invite.permissionContinue"]
        XCTAssertTrue(permissionContinue.waitForExistence(timeout: 5))
        XCTAssertEqual(permissionContinue.label, "Continue")
        XCTAssertFalse(app.buttons["invite.close"].exists)
        XCTAssertFalse(app.buttons["not now"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-396 actual Feed contact invite permission"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        permissionContinue.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "Astir uses your contacts to help you connect with people you know."
            )
        ).firstMatch.exists)

        let systemPrompt = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        systemPrompt.name = "REC-469 Contacts system permission"
        systemPrompt.lifetime = .keepAlways
        add(systemPrompt)

        let deny = alert.buttons.matching(
            NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])
        ).firstMatch
        XCTAssertTrue(deny.exists)
        deny.tap()
        XCTAssertTrue(app.staticTexts["contacts are off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share an invite link"].exists)
    }

    func testAuthenticatedSimulatorFixtureSurvivesArgumentFreeRelaunch() {
        let app = XCUIApplication()
        defer {
            app.terminate()
            app.launchArguments = [
                "-WanderResetAuthenticatedUITest",
                "-WanderOnboardingUITestSignedOut",
            ]
            app.launch()
            app.terminate()
        }

        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Continue offline"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Profile"].exists)
        XCTAssertFalse(app.buttons["Continue offline"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)
    }

    func testSimulatorBuildExposesDebugSettingsWithoutServerEntitlement() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
            "-WanderOpenSettings",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let continueOffline = app.buttons["Continue offline"]
        if continueOffline.waitForExistence(timeout: 8) {
            continueOffline.tap()
        }

        let nuxToggle = app.descendants(matching: .any)["settings.flags.first_visit_nux"]
        let placeStylePicker = app.descendants(matching: .any)["settings.flags.place_profile_action_variant"]
        for _ in 0..<6 where !nuxToggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(nuxToggle.waitForExistence(timeout: 8))
        for _ in 0..<6 where !placeStylePicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(placeStylePicker.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Simulator @joe Debug Settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testInstagramPostExplainsFullPhotoAccessBeforeDirectShare() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderActivityShareMockup",
            "-WanderActivityShareInstagramPostMockup",
            "-activityShare.instagramPostFullPhotoAccessAcknowledged",
            "NO",
        ]
        app.launch()

        let instagramPost = app.buttons["Instagram Post"]
        XCTAssertTrue(instagramPost.waitForExistence(timeout: 5))
        XCTAssertTrue(instagramPost.isHittable)
        instagramPost.tap()

        XCTAssertTrue(
            app.staticTexts["Instagram needs Full Photo Access"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["Settings → Apps → Instagram → Photos → Full Access"].exists
        )
        XCTAssertTrue(app.buttons["I've enabled Full Access"].isHittable)
        XCTAssertTrue(app.buttons["Use compatible sharing"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-271 Instagram Full Photo Access guidance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNativeMapOverviewUsesRealControlsAndEndsWithoutSaving() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep", "-WanderNUXFeedFixture"]
        app.launch()
        for target in ["mapFeatured", "mapFriends", "mapMoreFilters", "mapSearch", "mapAdd", "mapPinLegend"] {
            let coach = app.descendants(matching: .any)["walkthrough.map.\(target)"]
            XCTAssertTrue(coach.waitForExistence(timeout: 18), "Missing native \(target)")
            XCTAssertFalse(app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"].exists)
            if target == "mapMoreFilters" {
                XCTAssertTrue(app.descendants(matching: .any)["map.moreFilters.popover"].exists)
            }
            if target == "mapSearch" {
                XCTAssertFalse(app.descendants(matching: .any)["map.moreFilters.popover"].exists)
                XCTAssertEqual(app.keyboards.count, 0)
            }
            if target == "mapPinLegend" {
                XCTAssertTrue(app.descendants(matching: .any)["map.walkthrough.pinLegend"].exists)
            }
            captureNUX("\(target)")
            app.buttons["walkthrough.next.map.\(target)"].tap()
        }
        let people = app.staticTexts["walkthrough.feed.feedActivity.circle"]
        XCTAssertTrue(people.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Feed"].isSelected)
        XCTAssertFalse(app.buttons["walkthrough.next.sendoff.mapSendoff"].exists)
        app.buttons["walkthrough.next.feed.feedActivity"].tap()
        XCTAssertTrue(app.staticTexts["walkthrough.feed.feedActivity.recent"].waitForExistence(timeout: 6))
        app.buttons["walkthrough.next.feed.feedActivity"].tap()
        XCTAssertTrue(app.staticTexts["walkthrough.feed.feedActivity.recent"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["people.recommendation.user_ryan.profile"].isHittable)
    }

    func testMapRingsAutomaticallyContinueIntoFeedAndFinishAtTop() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderNUXFeedFixture", "-WanderWalkthroughTarget", "mapPinLegend"]
        app.launch()
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 20))
        let selected = expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: app.buttons["Feed"])
        wait(for: [selected], timeout: 12)
        XCTAssertTrue(app.staticTexts["walkthrough.feed.feedActivity.recent"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["walkthrough.next.sendoff.mapSendoff"].exists)
        XCTAssertFalse(app.buttons["Close add place"].exists)
    }

    func testRealMapFilterActionCanExitOverviewImmediately() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep"]
        app.launch()
        let coach = app.descendants(matching: .any)["walkthrough.map.mapFeatured"]
        XCTAssertTrue(coach.waitForExistence(timeout: 18))
        let you = app.buttons["map.filter.you"]
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: you)
        wait(for: [ready], timeout: 4)
        XCTAssertTrue(you.isHittable)
        you.tap()
        XCTAssertTrue(coach.waitForNonExistence(timeout: 3))
        XCTAssertTrue(you.value as? String == "Selected" || you.isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"].exists)
    }

    func testMorePanelScrollReachesExplanationAndNextClosesIt() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep", "-WanderWalkthroughTarget", "mapMoreFilters"]
        app.launch()
        let popover = app.descendants(matching: .any)["map.moreFilters.popover"]
        XCTAssertTrue(popover.waitForExistence(timeout: 18))
        let explanation = app.staticTexts["map.more.explanation"]
        // XCTest waits for animation idleness after launch and can miss the
        // short automatic scroll entirely. Hold the beat to exercise the real
        // panel and Next deterministically; recordings cover automatic timing.
        // This is reading copy, not a tappable control. UIKit can report it as
        // non-hittable behind the decorative coach even when fully visible.
        for _ in 0..<3 where !popover.frame.contains(explanation.frame) {
            let start = popover.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.85))
            let end = popover.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(popover.frame.contains(explanation.frame), "The complete explanation must be visible inside the dropdown.")
        captureNUX("M03-scrolled")
        app.buttons["walkthrough.next.map.mapMoreFilters"].tap()
        XCTAssertTrue(app.buttons["walkthrough.next.map.mapSearch"].waitForExistence(timeout: 8))
        XCTAssertFalse(popover.exists)
        XCTAssertEqual(app.keyboards.count, 0)
    }

    func testMoreFilterInteractionExitsDemoAndKeepsTheChoice() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep", "-WanderWalkthroughTarget", "mapMoreFilters"]
        app.launch()
        let coach = app.buttons["walkthrough.next.map.mapMoreFilters"]
        XCTAssertTrue(coach.waitForExistence(timeout: 18))
        let category = app.buttons["Coffee, Tea, & Sweets"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        // Verify a real touch and its resulting selection, since the native
        // glass popover's accessibility hit point can be absent during NUX.
        category.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(coach.waitForNonExistence(timeout: 3))
        let more = app.buttons["map.filter.more"]
        XCTAssertTrue((more.value as? String)?.contains("1 selected filter") == true)
        more.tap()
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.isSelected, "The native category choice must survive leaving the demonstration.")
        XCTAssertFalse(app.buttons["walkthrough.next.sendoff.mapSendoff"].exists)
    }

    func testPlusRemainsVoluntaryAndDoesNotStartForcedSave() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep", "-WanderWalkthroughTarget", "mapAdd"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["walkthrough.map.mapAdd"].waitForExistence(timeout: 18))
        app.buttons["map.headerAdd"].tap()
        let coach = app.descendants(matching: .any)["walkthrough.add.addNearby"]
        XCTAssertTrue(coach.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.add.addSearch"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"].exists)
        captureNUX("C01")
        app.buttons["walkthrough.next.add.addNearby"].tap()
        XCTAssertTrue(coach.waitForNonExistence(timeout: 3))
        let imports = app.staticTexts["walkthrough.add.addImport"]
        XCTAssertTrue(imports.waitForExistence(timeout: 5))
        XCTAssertTrue(imports.label.contains("Instagram, TikTok"))
        captureNUX("C01-import")
        app.buttons["walkthrough.next.add.addImport"].tap()
        XCTAssertTrue(imports.waitForNonExistence(timeout: 3))
        app.buttons["Close add place"].tap()
        app.buttons["map.headerAdd"].tap()
        XCTAssertTrue(app.buttons["Close add place"].waitForExistence(timeout: 5))
        XCTAssertFalse(coach.exists)
        XCTAssertFalse(imports.exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"].exists)
    }

    func testAddIntroductionWaitsForWholeNearbySectionThenShowsImport() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderUseStorefrontFixtures", "-WanderOpenAdd",
            "-WanderHoldWalkthroughStep", "-WanderWalkthroughTarget", "addNearby"]
        app.launch()
        let annotation = app.staticTexts["walkthrough.add.addNearby"]
        XCTAssertTrue(annotation.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Nearby places"].isHittable)
        XCTAssertTrue(app.buttons["Add Sparrow Bakery"].isHittable)
        XCTAssertTrue(app.buttons["add.nearbySeeMore"].isHittable)
        XCTAssertFalse(app.staticTexts["Finding places near you…"].exists)
        captureNUX("C01-full-nearby")
        app.buttons["walkthrough.next.add.addNearby"].tap()
        XCTAssertTrue(app.staticTexts["walkthrough.add.addImport"].waitForExistence(timeout: 5))
        captureNUX("C01-unblurred-import")
        app.buttons["walkthrough.next.add.addImport"].tap()
        XCTAssertFalse(annotation.exists)
        XCTAssertFalse(app.staticTexts["walkthrough.add.addImport"].exists)
    }

    func testFeedHintEndsOnFeedWithoutOpeningDiscoverOrInvites() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderNUXFeedFixture", "-WanderWalkthroughTarget", "feedActivity"]
        app.launch()
        let annotation = app.staticTexts["walkthrough.feed.feedActivity.circle"]
        XCTAssertTrue(app.buttons["Feed"].waitForExistence(timeout: 20))
        // A cold launch may finish its first short beat before XCTest attaches.
        // The sequence test below checks both beats; this checks the usable end state.
        XCTAssertTrue(annotation.waitForNonExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["walkthrough.feed.feedActivity.recent"].waitForNonExistence(timeout: 6))
        XCTAssertFalse(app.buttons["walkthrough.next.feed.feedActivity"].exists)
        XCTAssertTrue(app.buttons["people.recommendation.user_ryan.profile"].isHittable)
        app.buttons["Map"].tap()
        app.buttons["Feed"].tap()
        XCTAssertFalse(annotation.exists)
        XCTAssertFalse(app.staticTexts["walkthrough.feed.feedActivity.recent"].exists)
        XCTAssertTrue(app.buttons["Feed"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchField"].exists)
        XCTAssertFalse(app.buttons["invite.primaryAction"].exists)
    }

    func testFeedIntroductionCentersWholeLatestTileThenReturnsToTopWithoutRepeating() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderNUXFeedFixture", "-WanderWalkthroughTarget", "feedActivity"]
        app.launch()
        let circle = app.staticTexts["walkthrough.feed.feedActivity.circle"]
        let recent = app.staticTexts["walkthrough.feed.feedActivity.recent"]
        XCTAssertTrue(circle.waitForExistence(timeout: 20))
        let headingY = app.staticTexts["Recent"].frame.minY
        XCTAssertTrue(recent.waitForExistence(timeout: 6))
        XCTAssertFalse(circle.exists)
        captureNUX("C02-recent")
        XCTAssertLessThan(app.staticTexts["Recent"].frame.minY, headingY - 50,
                          "Only the latest card should be brought into view.")
        XCTAssertEqual(recent.label, "Keep up with their moments")
        XCTAssertTrue(app.buttons["walkthrough.next.feed.feedActivity"].exists)
        XCTAssertTrue(recent.waitForNonExistence(timeout: 6))
        let returned = expectation(for: NSPredicate(format: "hittable == true"),
                                   evaluatedWith: app.buttons["people.recommendation.user_ryan.profile"])
        wait(for: [returned], timeout: 4)
        XCTAssertFalse(app.buttons["walkthrough.next.feed.feedActivity"].exists)
        app.buttons["Map"].tap()
        app.buttons["Feed"].tap()
        XCTAssertFalse(circle.exists)
        XCTAssertFalse(recent.exists)
    }

    func testListsHasNoNUXAfterThePrimaryTour() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderWalkthroughTarget", "feedActivity"]
        app.launch()
        XCTAssertTrue(app.buttons["Lists"].waitForExistence(timeout: 20))
        app.buttons["Lists"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.lists.listsScope"].exists)
    }

    func testRetiredImportLaunchArgumentDoesNotPresentN26() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderHoldWalkthroughStep", "-WanderShowImportWalkthrough"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["walkthrough.map.mapFeatured"].waitForExistence(timeout: 18))
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.importLesson"].exists)
        XCTAssertFalse(app.buttons["Open import form"].exists)
    }

    private func captureNUX(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "NUX-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeCheckInWannaAnnotationLeavesActionsUsable() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderNUXReview", "-WanderHoldWalkthroughStep",
            "-WanderPlaceProfileSaveTrayV1", "-WanderWalkthroughTarget", "placeSaveActions"]
        app.launch()
        let annotation = app.staticTexts["walkthrough.placeDetail.placeSaveActions"]
        XCTAssertTrue(annotation.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["walkthrough.next.placeDetail.placeSaveActions"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)
        captureNUX("C04")
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertTrue(app.buttons["place-profile.floating-action.wanna"].isHittable)
        checkIn.tap()
        XCTAssertTrue(annotation.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["save.close"].waitForExistence(timeout: 5),
                      "The annotation must allow the real Check In editor to open.")
    }

    func testPlaceIntroductionAutomaticallyFinishesAndDoesNotReturnAfterEditor() {
        let app = XCUIApplication()
        app.launchArguments = nativeOverviewArguments + ["-WanderNUXReview",
            "-WanderPlaceProfileSaveTrayV1", "-WanderWalkthroughTarget", "placeSaveActions"]
        app.launch()
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 20))
        let annotation = app.staticTexts["walkthrough.placeDetail.placeSaveActions"]
        XCTAssertTrue(annotation.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.buttons["walkthrough.next.placeDetail.placeSaveActions"].exists)
        XCTAssertTrue(checkIn.isHittable)
        XCTAssertTrue(app.buttons["place-profile.floating-action.wanna"].isHittable)
        checkIn.tap()
        let close = app.buttons["save.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        // The Map-hosted editor returns to the selected compact place card.
        // Reopen that real profile to verify the lesson was consumed.
        let place = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertFalse(annotation.exists)
    }

    private var nativeOverviewArguments: [String] {
        ["-WanderAuthenticatedUITest", "-WanderMapCapture", "-WanderUseDemoFixtures",
         "-WanderEnableWalkthroughs", "-WanderResetWalkthroughs"]
    }

    func testMapMoreSectionsAndResetFollowTheActiveSource() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapMoreFiltersOpen"
        ]
        app.launch()

        let popover = app.scrollViews.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))

        let expectedPeople = [
            (id: "user_demo", name: "Demo"),
            (id: "user_maya", name: "Maya"),
            (id: "user_ryan", name: "Ryan")
        ]
        let demo = app.buttons["map.more.person.user_demo"]
        for _ in 0..<5 where !demo.exists {
            popover.swipeUp()
        }

        XCTAssertFalse(app.buttons["map.more.person.user_joe"].exists)
        for person in expectedPeople {
            let button = app.buttons["map.more.person.\(person.id)"]
            XCTAssertTrue(button.exists, "Expected More → People to include \(person.name)")
            XCTAssertTrue(button.label.contains(person.name))
        }

        demo.tap()
        XCTAssertEqual(demo.value as? String, "Selected")

        let done = app.buttons["Done"]
        for _ in 0..<5 where !done.isHittable {
            popover.swipeDown()
        }
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 2))

        let more = app.buttons["map.filter.more"]
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "1 selected filter"),
            evaluatedWith: more
        )
        waitForExpectations(timeout: 2)

        let you = app.buttons["map.filter.you"]
        you.tap()
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "Selected"),
            evaluatedWith: you
        )
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "No additional filters"),
            evaluatedWith: more
        )
        waitForExpectations(timeout: 2)
        more.tap()
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Categories"].exists)
        XCTAssertTrue(app.staticTexts["People"].exists)
        XCTAssertTrue(app.staticTexts["Status"].exists)
        XCTAssertTrue(app.buttons["map.more.person.user_demo"].exists)

        app.buttons["Done"].tap()
        app.buttons["map.filter.featured"].tap()
        more.tap()
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Categories"].exists)
        XCTAssertTrue(app.staticTexts["People"].exists)
        XCTAssertFalse(app.staticTexts["Status"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Map More follows the active source"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWalkthroughInviteUsesAddButtonsAndKeepsNextAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderInviteMockup", "walkthroughContacts"]
        app.launch()

        let primaryAction = app.buttons["invite.primaryAction"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let firstContact = app.buttons["invite.contactAdd.maya"]
        XCTAssertTrue(firstContact.waitForExistence(timeout: 3))
        XCTAssertEqual(firstContact.value as? String, "Not sent")
        XCTAssertEqual(firstContact.label, "Invite Maya Chen")
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 per-contact walkthrough Add actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testThirdLaunchDeviceLessonIncludesExtensionsGuide() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderShowDeviceFeaturesWalkthrough"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.extensionsGuide"]
                .isHittable
        )
        let card = app.descendants(matching: .any)["walkthrough.deviceFeatures.card"]
        let complete = app.descendants(matching: .any)["walkthrough.deviceFeatures.complete"]
        XCTAssertTrue(card.exists)
        XCTAssertTrue(complete.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.actionButton"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.widgets"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.shareExtension"].exists
        )

        XCTAssertFalse(app.buttons["walkthrough.dismiss.deviceFeatures"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(card.frame.minY, windowFrame.minY)
        XCTAssertLessThanOrEqual(card.frame.maxY, windowFrame.maxY)

        let cardFrameBeforeSwipe = card.frame
        app.swipeUp()
        XCTAssertEqual(card.frame.minY, cardFrameBeforeSwipe.minY, accuracy: 1)
        XCTAssertEqual(card.frame.maxY, cardFrameBeforeSwipe.maxY, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 third-launch device extensions lesson"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        complete.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures"]
                .waitForNonExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)
    }

    func testPrimaryTabTapNavigatesToFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let mapTab = app.buttons["Map"]
        let feedTab = app.buttons["Feed"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 4))
        XCTAssertTrue(feedTab.waitForExistence(timeout: 2))
        XCTAssertTrue(mapTab.isSelected)

        // Navigation is a touch-up contract. Immediate touch-down icon feedback
        // is covered deterministically by NavigationContractTests.
        feedTab.tap()

        XCTAssertTrue(feedTab.isSelected)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 4))
    }

    func testFeedHeaderHidesOnDownScrollAndReturnsOnUpScrollAcrossSurfaces() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let placeSearch = app.buttons["feed.searchLauncher"]
        let addButton = app.buttons["feed.headerAdd"]
        let placesButton = app.buttons["Places"]
        let peopleButton = app.buttons["People"]

        XCTAssertTrue(placeSearch.waitForExistence(timeout: 6))
        XCTAssertTrue(addButton.isHittable)
        XCTAssertTrue(placesButton.waitForExistence(timeout: 4))
        XCTAssertTrue(peopleButton.exists)
        XCTAssertTrue(placesButton.isSelected)
        XCTAssertLessThan(placeSearch.frame.maxY, placesButton.frame.minY)
        XCTAssertEqual(placesButton.frame.midY, addButton.frame.midY, accuracy: 2)

        let initialSearchY = placeSearch.frame.minY
        let initialControlsY = placesButton.frame.minY
        app.swipeUp()

        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"),
            object: placeSearch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        XCTAssertFalse(addButton.isHittable)

        app.swipeDown()

        let revealed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: placeSearch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 3), .completed)
        XCTAssertTrue(addButton.isHittable)
        XCTAssertEqual(placeSearch.frame.minY, initialSearchY, accuracy: 2)
        XCTAssertEqual(placesButton.frame.minY, initialControlsY, accuracy: 2)

        peopleButton.tap()
        let peopleSearch = app.textFields["Search people"]
        XCTAssertTrue(peopleSearch.waitForExistence(timeout: 4))
        XCTAssertTrue(peopleButton.isSelected)
        XCTAssertLessThan(peopleSearch.frame.maxY, peopleButton.frame.minY)
        XCTAssertTrue(addButton.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-383 adaptive Feed header restored on People"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCommentsEdgeSwipeReturnsToPreviousFeedPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let feedSearch = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(feedSearch.waitForExistence(timeout: 4))

        let openComments = app.buttons.matching(
            NSPredicate(format: "label == %@", "Open comments")
        ).firstMatch
        XCTAssertTrue(openComments.waitForExistence(timeout: 4))
        if !openComments.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(openComments.isHittable)
        openComments.tap()

        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 4))

        let commentsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        commentsScreenshot.name = "Comments native navigation destination"
        commentsScreenshot.lifetime = .keepAlways
        add(commentsScreenshot)

        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightSide)

        XCTAssertTrue(feedSearch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["activity.comment.send"].exists)

        let returnedFeedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        returnedFeedScreenshot.name = "Feed restored after comments back-swipe"
        returnedFeedScreenshot.lifetime = .keepAlways
        add(returnedFeedScreenshot)
    }

    func testFocusedMapSearchStaysWithinTheUsableViewport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderMapSearchQuery",
            "coffee"
        ]
        app.launch()

        let searchField = app.textFields["map.searchField"]
        let cancelButton = app.buttons["map.searchCancel"]
        let typeaheadPanel = app.otherElements["map.typeaheadPanel"]
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        if !cancelButton.waitForExistence(timeout: 2) {
            searchField.tap()
        }
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        XCTAssertTrue(typeaheadPanel.waitForExistence(timeout: 4))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }

        XCTAssertGreaterThan(searchField.frame.minY, 44)
        XCTAssertLessThan(typeaheadPanel.frame.maxY, searchField.frame.minY)
        XCTAssertLessThan(searchField.frame.maxY, keyboard.frame.minY)
        XCTAssertFalse(app.buttons["map.headerAdd"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-191 focused Map search post-fix"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRatingSliderRespondsThroughoutContinuousDrag() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace",
            "Woodcat Coffee",
            "-WanderMapSheetExpanded"
        ]
        app.launch()

        let checkInAgain = app.buttons["Check in"].firstMatch
        XCTAssertTrue(checkInAgain.waitForExistence(timeout: 3))
        checkInAgain.tap()

        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))

        for _ in 0..<3 where !slider.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(slider.isHittable)

        let startingValue = slider.value as? String
        let lowCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)
        )
        let highCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)
        )

        lowCoordinate.press(forDuration: 0.05, thenDragTo: highCoordinate)

        let highValue = slider.value as? String
        XCTAssertNotEqual(highValue, startingValue)
        XCTAssertTrue(highValue?.contains("4.5 out of 5") == true)

        highCoordinate.press(forDuration: 0.05, thenDragTo: lowCoordinate)

        let lowValue = slider.value as? String
        XCTAssertNotEqual(lowValue, highValue)
        XCTAssertTrue(lowValue?.contains("1.5 out of 5") == true)
    }

    func testMapPlaceProfileBackButtonCollapsesToSelectedCompactCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace",
            "Woodcat Coffee"
        ]
        app.launch()

        let compactCard = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(compactCard.waitForExistence(timeout: 8))
        XCTAssertTrue(compactCard.label.contains("Woodcat Coffee"))
        compactCard.tap()

        let ratings = app.staticTexts["Ratings"]
        XCTAssertTrue(ratings.waitForExistence(timeout: 5))
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        let expandedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedScreenshot.name = "Place profile expanded after compact card tap"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)

        backButton.tap()
        XCTAssertTrue(ratings.waitForNonExistence(timeout: 3))
        let restoredCompactCard = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(restoredCompactCard.waitForExistence(timeout: 3))
        XCTAssertTrue(restoredCompactCard.label.contains("Woodcat Coffee"))
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)

        let collapsedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsedScreenshot.name = "Place profile collapsed after back button"
        collapsedScreenshot.lifetime = .keepAlways
        add(collapsedScreenshot)
    }

    func testSettingsUsesFullPageProfileOverlayAndInteractiveEdgeSwipe() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
        ]
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        let settingsScreen = app.descendants(matching: .any)["settings.screen"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Settings"].exists)
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(backButton.frame.midX, app.frame.midX)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Profile"].isHittable)

        let fullPageScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fullPageScreenshot.name = "Settings full-page Profile overlay"
        fullPageScreenshot.lifetime = .keepAlways
        add(fullPageScreenshot)

        let resources = app.descendants(matching: .any)["settings.resources"]
        for _ in 0..<8 where !resources.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(resources.isHittable)

        let resourcesScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resourcesScreenshot.name = "Settings Resources unobstructed"
        resourcesScreenshot.lifetime = .keepAlways
        add(resourcesScreenshot)

        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        leftEdge.press(
            forDuration: 0.1,
            thenDragTo: rightSide,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )

        XCTAssertTrue(settingsScreen.waitForNonExistence(timeout: 3))
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Profile"].isHittable)
    }

    func testFloatingPlaceActionsStayVisibleAndOpenThePreselectedLegacyEditor() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Woodcat Coffee",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkInAgain = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkInAgain.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        XCTAssertTrue(checkInAgain.isHittable)
        XCTAssertTrue(wanna.isHittable)

        let topScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        topScreenshot.name = "Floating place actions at profile top"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(checkInAgain.isHittable)
        XCTAssertTrue(wanna.isHittable)

        let deepScrollScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        deepScrollScreenshot.name = "Floating place actions after deep scroll"
        deepScrollScreenshot.lifetime = .keepAlways
        add(deepScrollScreenshot)

        checkInAgain.tap()
        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
    }

    func testFirstMapCheckInUsesAttachedEditorAndRestoresItsDraft() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        checkIn.tap()

        let attachedTray = app.otherElements["place-profile.attached-check-in"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertTrue(app.buttons["save.checkInDateDisclosure"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        XCTAssertTrue(app.staticTexts["Griffith Observatory Trail"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        note.tap()
        note.typeText("Sunset draft")

        app.buttons["Close"].tap()
        XCTAssertFalse(attachedTray.waitForExistence(timeout: 2))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let restoredNote = app.textFields["save.note"]
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 3))
        let restoredNoteHeading = app.staticTexts["a note for future you"]
        XCTAssertTrue(restoredNoteHeading.isHittable)
        XCTAssertTrue(restoredNote.isHittable)
        XCTAssertEqual(
            restoredNote.value as? String,
            "Sunset draft"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "First Map check-in attached editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFirstMapWannaOpensAFreshDraftEachTime() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        wanna.tap()

        let attachedTray = app.otherElements["place-profile.attached-wanna"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Add to Wanna"].exists)
        XCTAssertTrue(app.buttons["Add a Wanna go date"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        XCTAssertTrue(app.staticTexts["Griffith Observatory Trail"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        note.tap()
        note.typeText("Wanna sunset draft")

        app.buttons["save.close"].tap()
        XCTAssertFalse(attachedTray.waitForExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
        wanna.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let restoredNote = app.textFields["save.note"]
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 3))
        let restoredNoteHeading = app.staticTexts["a note for future you"]
        XCTAssertTrue(restoredNoteHeading.isHittable)
        XCTAssertTrue(restoredNote.isHittable)
        XCTAssertEqual(
            restoredNote.value as? String,
            "what you'll want to remember, who told you..."
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "First Map Wanna attached editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["save.close"].tap()
        XCTAssertTrue(checkIn.isHittable)
        checkIn.tap()

        let switchedTray = app.descendants(matching: .any)["place-profile.attached-check-in"]
        XCTAssertTrue(switchedTray.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        let preservedNote = app.textFields["save.note"]
        XCTAssertTrue(preservedNote.waitForExistence(timeout: 3))
        XCTAssertEqual(
            preservedNote.value as? String,
            "what you'll want to remember, who told you..."
        )
    }

    func testMapWannaAndSaveRespondToSinglePhysicalTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.isHittable)
        wanna.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let attachedTray = app.otherElements["place-profile.attached-wanna"].firstMatch
        XCTAssertTrue(
            attachedTray.waitForExistence(timeout: 4),
            "One physical tap should open the Wanna editor."
        )

        let save = attachedTray.buttons["Add to Wanna"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            attachedTray.waitForNonExistence(timeout: 4),
            "One physical tap should submit and dismiss the Wanna editor."
        )
        XCTAssertFalse(app.buttons["place-profile.floating-action.wanna"].isSelected)
    }

    func testMapCheckInRespondsToSinglePhysicalTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["place-profile.attached-check-in"]
                .waitForExistence(timeout: 4),
            "One physical tap should open the Check in editor."
        )
    }

    func testMapCheckInSaveWorksWithFocusedNoteAndVisibleKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let attachedTray = app.descendants(matching: .any)["place-profile.attached-check-in"]
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        note.tap()
        note.typeText("Keyboard-visible check-in")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }

        let save = attachedTray.buttons["Check in"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            keyboard.waitForNonExistence(timeout: 4),
            "The same Save tap should intentionally dismiss the keyboard."
        )
        XCTAssertTrue(
            attachedTray.waitForNonExistence(timeout: 4),
            "One physical Save tap should commit and dismiss the Check-in editor."
        )
        XCTAssertTrue(
            app.buttons["Check in"].firstMatch.waitForExistence(timeout: 4),
            "The completed Check-in should update the place action exactly once."
        )
    }

    func testEachWannaSubmissionFromPlaceProfileCreatesVisibleHistory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs", "-WanderMapPlace", "Griffith Observatory Trail",
            "-WanderMapSheetExpanded", "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()
        for marker in ["Wanna record alpha", "Wanna record beta", "Wanna record gamma"] {
            let wanna = app.buttons["place-profile.floating-action.wanna"]
            XCTAssertTrue(wanna.waitForExistence(timeout: 6))
            wanna.tap()
            let note = app.textFields["save.note"]
            XCTAssertTrue(note.waitForExistence(timeout: 4))
            XCTAssertFalse((note.value as? String ?? "").contains("Wanna record"))
            note.tap()
            note.typeText(marker)
            let save = app.buttons["Add to Wanna"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 3))
            save.tap()
            XCTAssertTrue(note.waitForNonExistence(timeout: 6), "Every submission should finish")
        }
        let history = app.scrollViews["place-profile.scroll"].firstMatch
        for _ in 0..<5 { history.swipeUp() }
        for marker in ["Wanna record alpha", "Wanna record beta", "Wanna record gamma"] {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.exists,
                          "Each Wanna must remain in ALL history: \(marker)")
        }
        let pencils = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "place-activity.edit."))
        let pencil = pencils.allElementsBoundByIndex.first { $0.isHittable && $0.label == "Edit want" }
        XCTAssertNotNil(pencil, "Every owned Wanna tile should offer its edit pencil")
        guard let pencil else { return }
        pencil.tap()
        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 4))
        let original = note.value as? String ?? ""
        XCTAssertTrue(original.contains("Wanna record"), "Editing must load this event's own details")
        note.tap()
        note.typeText(" edited")
        let updated = (note.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        app.buttons["Update Wanna"].firstMatch.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 6))
        for _ in 0..<3 { history.swipeUp() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", updated)).firstMatch.exists)
        for marker in ["Wanna record alpha", "Wanna record beta", "Wanna record gamma"] where marker != original {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.exists,
                          "Editing one Wanna must preserve its siblings")
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Independent Wanna history after editing one record"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCompactWannaFormScrollsWithoutPullingTheSheet() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs", "-WanderMapPlace", "Woodcat Coffee",
            "-WanderMapSheetExpanded", "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 6))
        wanna.tap()
        let scroll = app.scrollViews["save.editorScroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 4))
        let compactTop = scroll.frame.minY
        let heading = app.staticTexts["a note for future you"].firstMatch
        let headingTop = heading.frame.minY
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.65))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end)
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            heading.frame.minY < headingTop - 60 && abs(scroll.frame.minY - compactTop) < 30
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 3), .completed,
                       "An ordinary upward content gesture must scroll the compact form without sheet snapback")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Wanna form after compact content scroll"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAttachedWannaSheetCanExpandAndDismissFromItsNativeGrabber() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        wanna.tap()

        let attachedTray = app.descendants(matching: .any)["place-profile.attached-wanna"]
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))

        let compactScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compactScreenshot.name = "Attached Wanna native sheet compact"
        compactScreenshot.lifetime = .keepAlways
        add(compactScreenshot)

        func grabberCoordinate(for sheet: XCUIElement) -> XCUICoordinate {
            let nativeGrabber = app.descendants(matching: .any)["Sheet Grabber"]
            if nativeGrabber.exists {
                return nativeGrabber.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                )
            }
            let normalizedY = max(
                0.02,
                min(0.98, (sheet.frame.minY - 10) / app.frame.height)
            )
            return app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedY)
            )
        }

        let compactMinY = attachedTray.frame.minY
        let expandTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        grabberCoordinate(for: attachedTray)
            .press(forDuration: 0.05, thenDragTo: expandTarget)

        let expanded = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.frame.minY < compactMinY - 150
            },
            object: attachedTray
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 3), .completed)
        let expandedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedScreenshot.name = "Attached Wanna sheet expanded by native grabber"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)

        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        for _ in 0..<2 where attachedTray.exists {
            grabberCoordinate(for: attachedTray)
                .press(forDuration: 0.08, thenDragTo: dismissTarget)
            if attachedTray.waitForNonExistence(timeout: 2) { break }
        }

        XCTAssertTrue(attachedTray.waitForNonExistence(timeout: 3))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
    }

    func testExistingMapWannaStartsFreshAndCheckInRestoresTheCurrentDraft() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Elysian Picnic Steps",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        wanna.tap()

        let attachedTray = app.descendants(matching: .any)["place-profile.attached-wanna"]
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(attachedTray.buttons["Add to Wanna"].exists)
        XCTAssertFalse(attachedTray.buttons["Update Wanna"].exists)
        XCTAssertFalse(attachedTray.buttons["Remove from Wanna"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        // The main Wanna action creates a new event, even for a saved place.
        XCTAssertEqual(note.value as? String, note.placeholderValue)
        note.tap()
        note.typeText("First unsaved Wanna")
        XCTAssertEqual(note.value as? String, "First unsaved Wanna")

        app.buttons["save.close"].tap()
        XCTAssertTrue(attachedTray.waitForNonExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
        wanna.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let freshNote = app.textFields["save.note"]
        XCTAssertTrue(freshNote.waitForExistence(timeout: 3))
        XCTAssertEqual(freshNote.value as? String, freshNote.placeholderValue,
                       "A repeated Wanna starts fresh instead of editing a saved or abandoned event")
        freshNote.tap()
        freshNote.typeText("Current Wanna draft")
        XCTAssertEqual(freshNote.value as? String, "Current Wanna draft")

        app.buttons["save.close"].tap()
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 2))
        checkIn.tap()

        let conversionTray = app.descendants(matching: .any)["place-profile.attached-check-in"]
        XCTAssertTrue(conversionTray.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Elysian Picnic Steps"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertTrue(app.buttons["save.checkInDateDisclosure"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        let conversionNote = app.textFields["save.note"]
        XCTAssertTrue(conversionNote.waitForExistence(timeout: 3))
        XCTAssertEqual(conversionNote.value as? String, "Current Wanna draft")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Fresh Wanna draft converts to attached Check in"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEditWannaDeleteActionPreservesItsConfirmationBehavior() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Elysian Picnic Steps",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        // Wanna creates a new event; edit an existing event from its history pencil.
        let history = app.scrollViews["place-profile.scroll"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let edit = app.buttons["place-activity.edit.up_joe_elysian_picnic_current_want"]
        for _ in 0..<5 where !edit.isHittable { history.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()

        let editorScrollView = app.scrollViews["save.editorScroll"]
        XCTAssertTrue(editorScrollView.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Update Wanna"].exists)

        let deleteButton = editorScrollView.buttons["Remove from Wanna"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))

        XCTAssertTrue(editorScrollView.exists)
        let saveButton = app.buttons["Update Wanna"]
        for _ in 0..<8 {
            if deleteButton.isHittable && deleteButton.frame.maxY < saveButton.frame.minY { break }
            editorScrollView.swipeUp()
        }
        XCTAssertTrue(deleteButton.isHittable)
        XCTAssertLessThan(deleteButton.frame.maxY, saveButton.frame.minY)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-361 lightweight Edit Wanna delete action"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        deleteButton.tap()
        let confirmation = app.alerts["Remove from Wanna?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.buttons["Remove from Wanna"].exists)
        XCTAssertTrue(confirmation.buttons["Cancel"].exists)
        confirmation.buttons["Cancel"].tap()

        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 2))
        XCTAssertTrue(editorScrollView.exists)
        XCTAssertTrue(app.buttons["Update Wanna"].exists)
    }

    func testFeedInlineSearchCoversEntryEmptyResultsNavigationAndBack() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 4))
        launcher.tap()

        let searchField = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        let backButton = app.buttons["discover.searchBack"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        XCTAssertEqual(backButton.label, "Back to Feed")
        XCTAssertFalse(launcher.isHittable)
        XCTAssertFalse(app.staticTexts["Discover"].exists)
        XCTAssertTrue(app.staticTexts["Try a search"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let focusedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        focusedScreenshot.name = "Feed search focused"
        focusedScreenshot.lifetime = .keepAlways
        add(focusedScreenshot)

        searchField.tap()
        searchField.typeText("coffee")
        XCTAssertEqual(searchField.value as? String, "coffee")
        searchField.typeText("\n")
        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 4))

        let firstPlaceResult = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Astir rating")
        ).firstMatch
        XCTAssertTrue(firstPlaceResult.waitForExistence(timeout: 4))
        XCTAssertTrue(firstPlaceResult.isHittable)
        firstPlaceResult.tap()

        let placeBackButton = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBackButton.waitForExistence(timeout: 4))
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightSide)
        XCTAssertTrue(placeBackButton.waitForNonExistence(timeout: 3))
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertEqual(searchField.value as? String, "coffee")

        app.swipeUp()
        XCTAssertTrue(backButton.exists)
        XCTAssertTrue(backButton.isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let resultsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultsScreenshot.name = "Feed search results with pinned toolbar"
        resultsScreenshot.lifetime = .keepAlways
        add(resultsScreenshot)

        let clearButton = app.buttons["Clear search"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
        clearButton.tap()
        XCTAssertTrue(app.staticTexts["Try a search"].exists)
        XCTAssertTrue(backButton.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Feed dedicated search state"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        backButton.tap()
        XCTAssertTrue(launcher.waitForExistence(timeout: 3))
    }

    func testFeedPeopleAddDismissesKeyboardBeforePresentingAdd() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let peopleTab = app.buttons["People"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 6))
        peopleTab.tap()

        let peopleSearch = app.textFields["Search name or @handle"]
        XCTAssertTrue(peopleSearch.waitForExistence(timeout: 4))
        peopleSearch.tap()
        peopleSearch.typeText("ryan")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let addButton = app.buttons["feed.headerAdd"]
        XCTAssertTrue(addButton.isHittable)
        addButton.tap()

        XCTAssertTrue(app.staticTexts["add a place"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-434 Add presented with keyboard dismissed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAppleIdentityNeedsOnlyUsernameAndContinuesWithoutName() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderAppleOnboardingUITest",
                               "-WanderOnboardingUITestStep", "identity"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Choose your username"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["How friends know you"].exists)
        let username = app.textFields["your_username"]
        XCTAssertTrue(username.exists)
        let next = app.buttons["onboarding.identity.continue"]
        XCTAssertFalse(next.isEnabled)
        username.tap()
        username.typeText("apple_review")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: next)
        waitForExpectations(timeout: 10)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-530 Apple username only"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        next.tap()
        XCTAssertTrue(app.staticTexts["Choose your username"].waitForNonExistence(timeout: 10))
    }

    func testNonAppleIdentityStillShowsNameAndUsername() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestStep", "identity"]
        app.launch()
        XCTAssertTrue(app.textFields["How friends know you"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["your_username"].exists)
        XCTAssertFalse(app.staticTexts["Choose your username"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-530 non-Apple profile unchanged"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLoggedOutCarouselPagesKeepActionsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestSignedOut"]
        app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "600"
        app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
        app.launch()

        let page = app.descendants(matching: .any)["onboarding.carouselPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        for index in 1...3 {
            expectation(for: NSPredicate(format: "value == %@", String(index)), evaluatedWith: page)
            waitForExpectations(timeout: 3)
            XCTAssertTrue(app.buttons["onboarding.next"].isHittable)
            XCTAssertTrue(app.buttons["onboarding.logIn"].isHittable)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "REC-447 splash page \(index)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if index < 3 {
                app.swipeLeft()
            }
        }
        // Manual paging must remain available in both directions.
        for index in [2, 1] {
            app.swipeRight()
            expectation(for: NSPredicate(format: "value == %@", String(index)), evaluatedWith: page)
            waitForExpectations(timeout: 3)
        }
    }

    func testLoggedOutCarouselAutoAdvancesAndKeepsActionsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestSignedOut"]
        // The opening takes 17.1 seconds, then both real benefit
        // pages receive their reading time before the finite flow opens signup.
        app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "6"
        app.launchEnvironment["WANDER_ONBOARDING_FORCE_AUTO_ADVANCE"] = "1"
        // Start the timed observation with the real Play control. Simulator
        // automation setup can take longer than the opening's reading interval.
        app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
        app.launch()

        let carouselPage = app.descendants(matching: .any)["onboarding.carouselPage"]
        XCTAssertTrue(carouselPage.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["onboarding.next"].exists)
        XCTAssertTrue(app.buttons["onboarding.logIn"].exists)
        app.buttons["onboarding.pause"].tap()
        let signupDeadline = Date().addingTimeInterval(39)
        expectation(
            for: NSPredicate(format: "value == %@", "2"),
            evaluatedWith: carouselPage
        )
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.buttons["onboarding.next"].isHittable)
        XCTAssertTrue(app.buttons["onboarding.logIn"].isHittable)
        expectation(
            for: NSPredicate(format: "value == %@", "3"),
            evaluatedWith: carouselPage
        )
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["onboarding.next"].isHittable)
        XCTAssertTrue(app.buttons["onboarding.logIn"].isHittable)
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(
            timeout: max(0.1, signupDeadline.timeIntervalSinceNow)
        ))
        XCTAssertTrue(app.staticTexts["Create your account"].exists)
        XCTAssertTrue(app.buttons["auth.continueWithApple"].exists)
        XCTAssertFalse(carouselPage.exists)
    }

    func testWelcomeLoginVerificationSurvivesBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestSignedOut"]
        app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
        app.launch()
        let login = app.buttons["onboarding.logIn"]
        XCTAssertTrue(login.waitForExistence(timeout: 8))
        login.tap()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        email.tap()
        email.typeText("opening@example.test")
        let send = app.buttons["auth.continueWithEmail"]
        if !send.isHittable { app.swipeUp() }
        send.tap()
        let code = app.textFields["auth.emailCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        code.tap()
        code.typeText("123")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        XCTAssertEqual(code.value as? String, "123")
        XCTAssertTrue(app.staticTexts["Enter the verification code sent to opening@example.test."].exists)
        app.buttons["auth.close"].tap()
        XCTAssertTrue(login.waitForExistence(timeout: 8))
        login.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        XCTAssertFalse(code.exists)
    }

    func testWelcomeNextAndLoginOpenActualAuthFlows() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestSignedOut"]
        app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "600"
        app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        next.tap()
        next.tap()
        next.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["auth.continueWithApple"].exists)
        XCTAssertTrue(app.staticTexts["Create your account"].exists)
        XCTAssertFalse(app.buttons["auth.close"].exists)
        let login = app.buttons["auth.logIn"]
        XCTAssertTrue(login.exists)
        if !login.isHittable { app.swipeUp() }
        login.tap()
        XCTAssertTrue(app.buttons["auth.usePassword"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome back"].exists)
        XCTAssertTrue(app.buttons["auth.close"].exists)
        app.buttons["auth.close"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
    }

    func testFilmExplorationsKeepSignupAndLoginInteractive() {
        func keepScreenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for treatment in ["film", "film-type"] {
            let app = XCUIApplication()
            app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestSignedOut"]
            app.launchEnvironment["WANDER_ONBOARDING_TREATMENT"] = treatment
            app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
            app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "600"
            app.launch()
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            keepScreenshot("\(treatment) — opening")
            app.buttons["onboarding.logIn"].tap()
            XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 8))
            app.buttons["auth.close"].tap()
            XCTAssertTrue(next.waitForExistence(timeout: 8))
            next.tap(); next.tap(); next.tap()
            let email = app.textFields["auth.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Create your account"].exists)
            XCTAssertFalse(app.buttons["auth.close"].exists)
            XCTAssertTrue(app.buttons["auth.continueWithApple"].exists)
            keepScreenshot("\(treatment) — signup")
            email.tap()
            email.typeText("film@example.test")
            let send = app.buttons["auth.continueWithEmail"]
            if !send.isHittable { app.swipeUp() }
            send.tap()
            let code = app.textFields["auth.emailCode"]
            XCTAssertTrue(code.waitForExistence(timeout: 8))
            code.tap(); code.typeText("123")
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(code.waitForExistence(timeout: 8))
            XCTAssertEqual(code.value as? String, "123")
            keepScreenshot("\(treatment) — live verification after foreground")
            app.terminate()
        }
    }

    func testLoggedOutLoginExposesAppleGoogleEmailAndPasswordWithoutClerkSheet() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-WanderAuthUITest", "-WanderAuthenticatedUITest"]
        app.launch()

        let apple = app.buttons["auth.continueWithApple"]
        let google = app.buttons["auth.continueWithGoogle"]
        let email = app.textFields["auth.email"]
        let emailContinue = app.buttons["auth.continueWithEmail"]
        let usePassword = app.buttons["auth.usePassword"]
        XCTAssertTrue(apple.waitForExistence(timeout: 4))
        XCTAssertTrue(google.exists)
        XCTAssertTrue(email.exists)
        XCTAssertTrue(emailContinue.exists)
        XCTAssertTrue(usePassword.exists)
        XCTAssertTrue(apple.isHittable)
        XCTAssertTrue(google.isHittable)
        XCTAssertLessThan(apple.frame.minY, google.frame.minY)
        XCTAssertLessThan(google.frame.minY, email.frame.minY)
        XCTAssertFalse(app.buttons["auth.useOtherMethod"].exists)

        let appleScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        appleScreenshot.name = "REC-440 Apple logo visible in authentication"
        appleScreenshot.lifetime = .keepAlways
        add(appleScreenshot)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springboard.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 2) {
            let deny = systemAlert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }

        if !usePassword.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(usePassword.isHittable)
        usePassword.tap()

        let passwordEmail = app.textFields["auth.passwordEmail"]
        let password = app.secureTextFields["auth.password"]
        let passwordSubmit = app.buttons["auth.signInWithPassword"]
        let leavePassword = app.buttons["auth.leavePassword"]
        XCTAssertTrue(passwordEmail.waitForExistence(timeout: 2))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(passwordSubmit.exists)
        XCTAssertTrue(leavePassword.exists)
        XCTAssertTrue(passwordEmail.isHittable)
        XCTAssertTrue(password.isHittable)

        let passwordScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        passwordScreenshot.name = "REC-180 App Review password sign-in"
        passwordScreenshot.lifetime = .keepAlways
        add(passwordScreenshot)

        leavePassword.tap()
        XCTAssertTrue(apple.waitForExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-259 native Welcome back auth"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCheckInCalendarTrayPresentationLatency() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let addButton = app.buttons["map.headerAdd"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let searchField = app.textFields["add.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertTrue(searchField.isHittable)
        searchField.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            searchField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        searchField.typeText("Maru Coffee\n")

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 6))
        saveButton.tap()

        let checkInChoice = app.scrollViews["save.editorScroll"].buttons["Check in"]
        XCTAssertTrue(checkInChoice.waitForExistence(timeout: 3))
        let statusSelector = app.staticTexts["save.statusSelector"]
        XCTAssertTrue(statusSelector.exists)
        XCTAssertTrue(checkInChoice.isSelected)
        let finalCheckIn = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Check in", "save.statusSelector"
        )).element
        XCTAssertTrue(finalCheckIn.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["continue to details"].exists)
        XCTAssertFalse(app.buttons["back"].exists)
        XCTAssertTrue(app.buttons["Hide more options"].exists)

        let disclosure = app.buttons["save.checkInDateDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(statusSelector.exists)
        let rating = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(rating.exists)
        let note = app.textFields["save.note"]
        XCTAssertTrue(note.exists)
        XCTAssertLessThan(statusSelector.frame.minY, rating.frame.minY)
        XCTAssertLessThan(rating.frame.minY, note.frame.minY)
        XCTAssertLessThan(note.frame.minY, disclosure.frame.minY)
        XCTAssertTrue(disclosure.isHittable)

        note.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            note.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        note.typeText("Discard this draft")
        app.buttons["save.close"].tap()
        XCTAssertTrue(statusSelector.waitForNonExistence(timeout: 3))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(statusSelector.waitForExistence(timeout: 3))
        XCTAssertNotEqual(app.textFields["save.note"].value as? String, "Discard this draft")

        app.textFields["save.note"].tap()
        app.textFields["save.note"].typeText("Check-in mode draft")
        let wannaChoice = app.scrollViews["save.editorScroll"].buttons["Wanna go"]
        XCTAssertTrue(wannaChoice.waitForExistence(timeout: 2))
        XCTAssertTrue(wannaChoice.isHittable)
        wannaChoice.tap()
        XCTAssertTrue(app.buttons["Add a Wanna go date"].waitForExistence(timeout: 2))
        XCTAssertTrue(wannaChoice.isSelected)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        let wannaNote = app.textFields["save.note"]
        XCTAssertNotEqual(wannaNote.value as? String, "Check-in mode draft")
        wannaNote.tap()
        wannaNote.typeText("Wanna mode draft")
        XCTAssertTrue(checkInChoice.isHittable)
        checkInChoice.tap()
        XCTAssertEqual(app.textFields["save.note"].value as? String, "Check-in mode draft")
        wannaChoice.tap()
        XCTAssertEqual(app.textFields["save.note"].value as? String, "Wanna mode draft")
        checkInChoice.tap()

        let start = ProcessInfo.processInfo.systemUptime
        disclosure.tap()
        XCTAssertTrue((disclosure.value as? String)?.contains("Expanded") == true)
        let picker = app.descendants(matching: .any)["save.checkInDatePicker"]
        XCTAssertTrue(picker.exists)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTContext.runActivity(named: String(format: "Calendar tray presented in %.3f seconds", elapsed)) { _ in }
        print(String(format: "REC241_CALENDAR_TRAY_LATENCY_SECONDS=%.3f", elapsed))
        XCTAssertLessThan(elapsed, 1.0)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-241 responsive check-in calendar tray"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        disclosure.tap()
        XCTAssertTrue((disclosure.value as? String)?.contains("Collapsed") == true)
        finalCheckIn.tap()
        XCTAssertTrue(statusSelector.waitForNonExistence(timeout: 5))
    }


}
