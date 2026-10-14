import XCTest
import UIKit

@MainActor
final class SenderNotificationFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGalleryCanOpenAndReturnFromNativeScenario() {
        let app = launch("gallery")
        let first = app.buttons["First check-in"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        press(first)
        let close = app.buttons["save.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        press(close)
        let back = app.buttons["sender-review.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        press(back)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }

    func testImportNotifyThreeNowSevenLaterKeepsFirstManifest() {
        let app = launch("importTen")
        for index in 0..<3 { tapImport(index, app: app) }
        capture("import-ten-first-three")
        app.buttons["import.save"].tap()
        let prompt = app.alerts["Silence notifications for this import?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        capture("import-ten-native-choice")
        prompt.buttons["No, notify followers"].tap()
        expectState(app, contains: "visits=3;silentVisits=3;")
        expectState(app, contains: "commits=1;manifest=3;importSilent=false;complete=true")
        let originalManifest = stateField("manifestIDs", app: app)
        XCTAssertEqual(originalManifest.split(separator: ",").count, 3)
        selectRemainingCheckIns(app)
        app.buttons["import.save"].tap()
        expectState(app, contains: "visits=10;silentVisits=10;")
        expectState(app, contains: "commits=1;manifest=3;importSilent=false;complete=true")
        XCTAssertEqual(stateField("manifestIDs", app: app), originalManifest)
        XCTAssertFalse(prompt.exists, "A later save must not ask or expand the first group.")
        capture("import-ten-later-seven")
    }

    func testImportSilentAndCancelPersistNoAccidentalNotificationIntent() {
        let app = launch("importOne")
        tapImport(0, app: app)
        app.buttons["import.save"].tap()
        let prompt = app.alerts["Silence notifications for this import?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        capture("import-one-native-choice")
        prompt.buttons["Cancel"].tap()
        expectState(app, contains: "commits=0;manifest=0;importSilent=unset")
        expectState(app, contains: "visits=0;silentVisits=0;")
        app.buttons["import.save"].tap()
        prompt.buttons["Yes, save silently"].tap()
        expectState(app, contains: "visits=1;silentVisits=1;")
        expectState(app, contains: "commits=1;manifest=1;importSilent=true;complete=true")
    }

    func testWannaOnlyFirstImportAndPreviouslyConsumedImportCannotAnnounceLater() {
        let app = launch("importTen")
        let wanna = app.buttons["import.wanna.sender-review-item-0"]
        reveal(wanna, app: app); wanna.tap()
        app.buttons["import.save"].tap()
        app.alerts.buttons["No, notify followers"].tap()
        expectState(app, contains: "commits=1;manifest=0;importSilent=false;complete=true")
        selectRemainingCheckIns(app)
        app.buttons["import.save"].tap()
        expectState(app, contains: "visits=9;silentVisits=9;")
        expectState(app, contains: "commits=1;manifest=0;importSilent=false;complete=true")
        XCTAssertFalse(app.alerts["Silence notifications for this import?"].exists)
        let consumed = launch("importConsumed")
        tapImport(0, app: consumed)
        consumed.buttons["import.save"].tap()
        expectState(consumed, contains: "commits=1;manifest=0;importSilent=true;complete=true")
        expectState(consumed, contains: "visits=1;silentVisits=1;")
        XCTAssertFalse(consumed.alerts["Silence notifications for this import?"].exists)
        capture("import-consumed-no-new-prompt")
    }

    func testOrdinaryCheckInRetainsNotifyChoiceWhenSilentIsOff() {
        let app = launch("checkIn")
        XCTAssertTrue(app.buttons["save.submit"].waitForExistence(timeout: 10))
        press(app.buttons["save.submit"])
        expectState(app, contains: "submitted=false")
        expectState(app, contains: "visits=1;silentVisits=0;")
    }

    func testNativeFormChoicesReachSavedVisitsAndWannas() {
        for route in ["checkIn", "repeatCheckIn", "historical", "wanna", "repeatWanna", "sourceSave"] {
            let app = launch(route)
            XCTAssertTrue(app.scrollViews["save.editorScroll"].waitForExistence(timeout: 10))
            capture("\(route)-initial")
            let silent = app.switches["save.silent"]
            reveal(silent, app: app)
            XCTAssertEqual(silent.value as? String, route == "historical" ? "1" : "0")
            if route != "historical" { activate(silent) }
            capture("\(route)-silent")
            press(app.buttons["save.submit"])
            expectState(app, contains: "submitted=true")
            if route == "repeatWanna" {
                expectState(app, contains: "wannas=1;")
            } else if ["wanna", "sourceSave"].contains(route) {
                expectState(app, contains: "saves=1;silentSaves=1;")
            } else {
                expectState(app, contains: "visits=1;silentVisits=1;")
            }
        }
    }

    func testStagedListsInheritTheParentSilentChoiceAndEditOnlyHasNoControl() {
        for route in ["checkIn", "editWithLists"] {
            let app = launch(route)
            let lists = app.buttons["save.lists"]
            reveal(lists, app: app); lists.tap()
            XCTAssertTrue(app.buttons["map-list-picker.cancel"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.switches["save.silent"].exists, "Staged lists inherit the form's choice.")
            let list = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND enabled == true", "map-list-picker.list.")).firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2)
            capture("\(route)-staged-list-picker")
            app.buttons["map-list-picker.apply"].tap()
            let silent = app.switches["save.silent"]
            reveal(silent, app: app); activate(silent)
            capture("\(route)-parent-silent")
            press(app.buttons["save.submit"])
            expectState(app, contains: "items=1;silentItems=1;")
        }
        let edit = launch("edit")
        XCTAssertTrue(edit.scrollViews["save.editorScroll"].waitForExistence(timeout: 10))
        edit.scrollViews["save.editorScroll"].swipeUp()
        XCTAssertFalse(edit.switches["save.silent"].exists)
        capture("edit-existing-no-silent-control")
    }

    func testStandaloneListPickerPersistsOneChoiceForEveryPlaceAndList() {
        for route in ["listPicker", "multiListPicker"] {
            let app = launch(route)
            let silent = app.switches["save.silent"]
            XCTAssertTrue(silent.waitForExistence(timeout: 10))
            XCTAssertEqual(silent.value as? String, "0")
            activate(silent)
            let available = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND enabled == true", "map-list-picker.list."))
            for index in 0..<2 {
                let list = available.element(boundBy: index)
                reveal(list, app: app)
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2)
            }
            capture("\(route)-silent")
            app.buttons["map-list-picker.apply"].tap()
            let count = route == "listPicker" ? 2 : 4
            expectState(app, contains: "items=\(count);silentItems=\(count);")
        }
    }

    func testSharedAcceptanceAndExplicitInvitationCopyUseRealComposer() {
        for route in ["sharedVisit", "friends"] {
            let app = launch(route)
            let silent = app.switches["save.silent"]
            reveal(silent, app: app); activate(silent)
            if route == "friends" {
                XCTAssertTrue(app.staticTexts["Skip notifications for this save. Visibility stays the same. People you invite will still receive invitations."].exists)
            }
            capture("\(route)-silent")
            if route == "sharedVisit" {
                press(app.buttons["save.submit"])
                expectState(app, contains: "submitted=true")
            }
        }
    }

    func testInlineImportDetailsHaveNoCompetingSilentToggle() {
        let app = launch("importDetails")
        XCTAssertTrue(app.buttons["import.save"].waitForExistence(timeout: 10))
        let details = app.buttons["save.moreOptions"]
        reveal(details, app: app)
        XCTAssertTrue(details.isHittable, "The inline editor must actually be visible.")
        XCTAssertFalse(app.switches["save.silent"].exists)
        capture("import-inline-details")
    }

    func testLargeTextAndDarkNativeControls() {
        let app = launch("checkIn", extra: ["-WanderSenderDark", "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue])
        let silent = app.switches["save.silent"]
        reveal(silent, app: app)
        XCTAssertTrue(silent.isHittable)
        activate(silent)
        reveal(app.staticTexts["save.silentHelp"], app: app)
        XCTAssertTrue(app.buttons["save.submit"].isHittable)
        capture("checkIn-dark-accessibility-text")
        press(app.buttons["save.submit"])
        expectState(app, contains: "submitted=true")
    }

    func testDiscoverQuickWannaDialogPersistsSilentChoice() {
        let app = launch("discover", extra: ["-WanderDiscoverSearchQuery", "Griffith"])
        let wanna = app.buttons["Wanna go"].firstMatch
        reveal(wanna, app: app); wanna.tap()
        let silent = app.buttons["Add silently"]
        XCTAssertTrue(silent.waitForExistence(timeout: 5))
        capture("discover-quick-wanna-dialog")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap() }
        XCTAssertTrue(silent.waitForNonExistence(timeout: 5))
        expectState(app, contains: "saves=0;silentSaves=0;")
        wanna.tap(); silent.tap()
        expectState(app, contains: "saves=1;silentSaves=1;")
    }

    func testListSuggestionAndSearchDialogsPersistSilentChoice() {
        for mode in ["direct", "addPlaces", "search"] {
            let app = launch("lists")
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open LA laptop mornings")).firstMatch
            reveal(row, app: app); press(row)
            let addPlaces = app.buttons["Add places to list"]
            XCTAssertTrue(addPlaces.waitForExistence(timeout: 8))
            if mode != "direct" { press(addPlaces) }
            let addition: XCUIElement
            if mode == "search" {
                let search = app.textFields["Search places"]
                XCTAssertTrue(search.waitForExistence(timeout: 5))
                search.tap(); search.typeText("Sparrow")
                addition = app.buttons["Add Sparrow Bakery to list"]
            } else {
                addition = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH ' to list' AND label != 'Add places to list'")).firstMatch
            }
            reveal(addition, app: app); press(addition)
            let silent = app.buttons["Add silently"]
            XCTAssertTrue(silent.waitForExistence(timeout: 5))
            capture("list-\(mode)-dialog")
            silent.tap()
            expectState(app, contains: "items=1;silentItems=1;")
        }
    }

    func testNewListInheritsStandalonePickerChoice() {
        let app = launch("listPicker")
        let silent = app.switches["save.silent"]
        XCTAssertTrue(silent.waitForExistence(timeout: 10)); activate(silent)
        let create = app.buttons["map-list-picker.new-list"]
        reveal(create, app: app, down: true); create.tap()
        let title = app.textFields["LA laptop mornings"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Review new list")
        capture("new-list-inherits-silent")
        app.navigationBars.buttons["Done"].tap()
        expectState(app, contains: "items=1;silentItems=1;")
    }

    private func launch(_ route: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderSenderReview", route, "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"] + extra
        app.launch()
        return app
    }
    private func tapImport(_ index: Int, app: XCUIApplication) {
        let button = app.buttons["import.checkin.sender-review-item-\(index)"]
        reveal(button, app: app); press(button)
        XCTAssertEqual(button.value as? String, "Selected")
    }
    private func selectRemainingCheckIns(_ app: XCUIApplication) {
        let button = app.buttons["import.all.checkin"]
        reveal(button, app: app, down: true); press(button)
        XCTAssertEqual(button.value as? String, "Selected")
    }
    private func press(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, down: Bool = false) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<16 {
            let editor = app.scrollViews["save.editorScroll"]
            let usesEditor = editor.exists && editor.isHittable && element.identifier.hasPrefix("save.")
            let surface = usesEditor ? editor : (app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch)
            let surfaceFrame = surface.exists ? surface.frame : .null
            // SwiftUI can expose an empty/infinite scroll-container frame even
            // while its controls are visible. Bound gestures to the screen then.
            let validFrame = !surfaceFrame.isEmpty && !surfaceFrame.isNull
                && surfaceFrame.minX.isFinite && surfaceFrame.minY.isFinite
                && surfaceFrame.width.isFinite && surfaceFrame.height.isFinite
            var viewport = (validFrame ? surfaceFrame : app.frame).intersection(app.frame)
            if !usesEditor { viewport = viewport.intersection(app.frame.insetBy(dx: 0, dy: 100)) }
            for identifier in ["save.submit", "import.save", "map-list-picker.apply"] {
                let submit = app.buttons[identifier]
                if submit.exists && submit.isHittable {
                    viewport.size.height = max(0, min(viewport.maxY, submit.frame.minY) - viewport.minY)
                }
            }
            viewport = viewport.insetBy(dx: 12, dy: 12)
            let frame = element.exists ? element.frame : .zero
            let visible = frame.height <= viewport.height
                ? frame.minY >= viewport.minY && frame.maxY <= viewport.maxY
                : viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
            if element.isHittable && visible { return }
            let up = frame.isEmpty ? !down : frame.midY >= viewport.midY
            if viewport.height > 80 {
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let lower = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.78))
                let upper = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.22))
                (up ? lower : upper).press(forDuration: 0.05, thenDragTo: up ? upper : lower, withVelocity: .slow, thenHoldForDuration: 0.2)
            } else if up { surface.swipeUp(velocity: .slow) } else { surface.swipeDown(velocity: .slow) }
        }
        XCTAssertTrue(element.isHittable, "Control must be reachable: \(element.identifier)")
    }
    private func stateField(_ key: String, app: XCUIApplication) -> String {
        let value = app.staticTexts["sender-review.state"].value as? String ?? ""
        return value.split(separator: ";").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
    }
    private func activate(_ element: XCUIElement) {
        // Historical edits can already be silent. Enabling is idempotent.
        if element.value as? String == "1" { return }
        // The accessibility frame includes the label. Touch the switch's
        // off thumb, a fixed inset from the trailing edge, then slide it on.
        let trailing = element.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
        trailing.withOffset(CGVector(dx: -38, dy: 0))
            .press(forDuration: 0.2, thenDragTo: trailing.withOffset(CGVector(dx: -14, dy: 0)))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: element)
        wait(for: [expected], timeout: 5)
    }
    private func expectState(_ app: XCUIApplication, contains value: String) {
        let state = app.staticTexts["sender-review.state"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: state)
        let result = XCTWaiter.wait(for: [expected], timeout: 10)
        XCTAssertEqual(result, .completed, "Expected \(value); actual \(state.value as? String ?? "missing")")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC589-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
