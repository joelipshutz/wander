import XCTest

@MainActor
final class YourMapPrototypeUITests: XCTestCase {
    func testAdaptiveMapKeepsEveryPlaceAndExpandsAllDotsAtCloseZoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
                               "-WanderProfileRedesignMockup", "adaptiveMap"]
        app.launch()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin."))
        let dots = pins.matching(NSPredicate(format: "value == %@", "Map dot"))
        let categories = pins.matching(NSPredicate(format: "value == %@", "Category pin"))
        expectation(for: NSPredicate { _, _ in pins.count == 177 && dots.count > categories.count && categories.count > 0 }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        capture("REC-573 adaptive wide - all 177 places")

        let dot = dots.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > 180 && $0.frame.maxY < app.frame.maxY - 180
        }
        XCTAssertNotNil(dot)
        let dotID = dot!.identifier
        let dotPosition = dot!.frame
        dot!.tap()
        let promoted = pins.matching(identifier: dotID).firstMatch
        expectation(for: NSPredicate(format: "value == %@", "Category pin"), evaluatedWith: promoted)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(pins.count, 177, "Selecting a dot must not remove nearby places")
        XCTAssertEqual(promoted.frame.midX, dotPosition.midX, accuracy: 5)
        capture("REC-573 selected dot promotes to category")

        // Ten places occupy this small area, including coincident coordinates.
        // The close-zoom override must show all of them as category pins.
        let center = pins.matching(identifier: "yourMap.prototype.pin.adaptive-0").firstMatch
        for _ in 0..<6 {
            if dots.count == 0 { break }
            center.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        }
        expectation(for: NSPredicate { _, _ in dots.count == 0 && categories.count >= 10 }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        capture("REC-573 adaptive close - all category pins including overlaps")

        // XCTest spreads multi-touch events across the target's whole frame.
        // Use the frontmost selected pin's larger frame so both touches reach
        // the map and aren't obstructed by coincident pins or overlay controls.
        let zoomTarget = try XCTUnwrap(pins.allElementsBoundByIndex.filter {
            $0.isHittable && app.frame.contains($0.frame)
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        for _ in 0..<6 {
            zoomTarget.twoFingerTap()
            if dots.count > 0 { break }
        }
        capture("REC-573 adaptive after zoom-out gesture")
        expectation(for: NSPredicate { _, _ in dots.count > 0 && categories.count > 0 }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        capture("REC-573 adaptive zoomed back out")
    }

    func testYourMapIncludesWannaAndSupportsZoomReselectionDismissalAndDetailReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        for _ in 0..<5 where preview.frame.maxY > app.frame.maxY - 100 || !preview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(preview.label.contains("4 places"), "The fixture has three Check-in places and one Wanna")
        capture("REC-573 profile preview includes Wanna")
        preview.tap()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin."))
        XCTAssertEqual(pins.count, 4, "All saved places must appear before any zoom gesture")
        capture("REC-573 all pins at overview zoom")
        selectProfileFixturePin(in: app)
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        capture("REC-574 selected native pin")

        // Every marker stays rendered at the city overview; nearby markers can
        // overlap. Zoom around the physically selected pin to test gestures.
        let selectedName = String(card.label.split(separator: ",")[0])
        let selectedPin = pins.matching(NSPredicate(format: "label BEGINSWITH %@", selectedName)).firstMatch
        for _ in 0..<2 {
            selectedPin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).doubleTap()
        }
        XCTAssertTrue(card.exists, "Double-tap zoom must retain selection")

        map.pinch(withScale: 1.5, velocity: 1)
        XCTAssertTrue(card.exists, "Pinch zoom must retain the selection")
        capture("REC-574 zoom with selected pin")
        if let second = pins.allElementsBoundByIndex.first(where: {
            !$0.label.hasPrefix(selectedName) && $0.isHittable && app.frame.contains($0.frame)
                && hypot($0.frame.midX - selectedPin.frame.midX, $0.frame.midY - selectedPin.frame.midY) > 60
        }) {
            let previousLabel = card.label
            second.tap()
            let changed = NSPredicate(format: "label != %@", previousLabel)
            expectation(for: changed, evaluatedWith: card)
            waitForExpectations(timeout: 3)
        } else {
            XCTFail("Fixture should retain another visible pin after zoom")
        }

        let finalSelectedName = String(card.label.split(separator: ",")[0])
        let finalSelectedPin = pins.matching(NSPredicate(format: "label BEGINSWITH %@", finalSelectedName)).firstMatch
        let selectedFrame = finalSelectedPin.frame
        card.tap()
        let back = app.buttons["place-profile.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["yourMap.prototype.filters"].exists)
        XCTAssertFalse(app.buttons["yourMap.snapshot"].exists)
        XCTAssertFalse(app.buttons["yourMap.prototype.mode"].exists)
        XCTAssertFalse(app.buttons["Share this lens"].exists)
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "The native Your Map header must yield to the place profile header")
        capture("REC-574 full place detail from Your Map")
        back.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["yourMap.prototype.filters"].exists)
        XCTAssertTrue(app.buttons["yourMap.snapshot"].exists)
        XCTAssertTrue(app.buttons["Share this lens"].exists)
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        XCTAssertEqual(finalSelectedPin.frame.midX, selectedFrame.midX, accuracy: 5)
        XCTAssertEqual(finalSelectedPin.frame.midY, selectedFrame.midY, accuracy: 5)
        app.buttons.matching(identifier: "yourMap.prototype.mode").matching(NSPredicate(format: "label == %@", "Patterns")).firstMatch.tap()
        app.buttons.matching(identifier: "yourMap.prototype.mode").matching(NSPredicate(format: "label == %@", "Map")).firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(finalSelectedPin.frame.midX, selectedFrame.midX, accuracy: 5)
        XCTAssertEqual(finalSelectedPin.frame.midY, selectedFrame.midY, accuracy: 5)
        capture("REC-574 returns to selected map")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.42)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "Tap-away must dismiss the card")
        let next = pins.allElementsBoundByIndex.first { $0.isHittable && app.frame.contains($0.frame) }
        XCTAssertNotNil(next)
        next?.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.43)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        )
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "A map pan must move the viewport and dismiss the card")
        capture("REC-574 pan dismisses selection")
    }

    func testMapShareOpensApprovedLinkedCardPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        for _ in 0..<5 where preview.frame.maxY > app.frame.maxY - 100 || !preview.isHittable {
            app.swipeUp()
        }
        preview.tap()
        app.buttons["Share this lens"].tap()
        XCTAssertTrue(app.segmentedControls["share.format"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["share.card"].exists)
        XCTAssertFalse(app.segmentedControls["yourMap.prototype.shareFormat"].exists)
        capture("Linked map card")
        app.buttons["Close share preview"].tap()
        XCTAssertTrue(app.buttons["Share this lens"].waitForExistence(timeout: 5))
    }

    func testGeographyExpandsAndCollapsesInPlaceWithoutUnknowns() {
        let app = launchGeography()
        let toggle = app.buttons["yourMap.prototype.geography.expand"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let cityRows = geographyRows(in: app, kind: "city")
        let countryRows = geographyRows(in: app, kind: "country")
        XCTAssertEqual(cityRows.count, 5)
        XCTAssertEqual(countryRows.count, 5)
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.cityRow.Unknown city"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.countryRow.Unknown country"].exists)
        let card = app.otherElements["yourMap.prototype.citiesCountries"]
        let month = app.otherElements["yourMap.prototype.monthHeatMap"]
        let collapsedHeight = card.frame.height
        let collapsedGap = month.frame.minY - card.frame.maxY
        capture("REC-417 geography collapsed")

        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["yourMap.prototype.cityRow.Amsterdam"].waitForExistence(timeout: 3))
        XCTAssertEqual(cityRows.count, 10)
        XCTAssertEqual(countryRows.count, 10)
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertGreaterThan(card.frame.height, collapsedHeight + 100)
        XCTAssertEqual(month.frame.minY - card.frame.maxY, collapsedGap, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.cityRow.Berlin"].exists)
        capture("REC-417 geography expanded")

        if !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        let collapsed = NSPredicate(format: "value == %@", "Collapsed")
        expectation(for: collapsed, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(cityRows.count, 5)
        XCTAssertEqual(countryRows.count, 5)
        XCTAssertEqual(card.frame.height, collapsedHeight, accuracy: 2)
        XCTAssertEqual(month.frame.minY - card.frame.maxY, collapsedGap, accuracy: 2)
        capture("REC-417 geography collapsed again")
    }

    func testGeographyOnlyUnknownLocationsShowsEmptyColumnsWithoutToggle() {
        let app = launchGeography(page: "patternsGeographyEmpty")
        XCTAssertTrue(app.staticTexts["No cities yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No countries yet"].exists)
        XCTAssertFalse(app.buttons["yourMap.prototype.geography.expand"].exists)
        XCTAssertEqual(geographyRows(in: app, kind: "city").count, 0)
        XCTAssertEqual(geographyRows(in: app, kind: "country").count, 0)
    }

    private func launchGeography(page: String = "patternsGeography") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderProfileRedesignMockup", page]
        app.launch()
        return app
    }

    private func geographyRows(in app: XCUIApplication, kind: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.\(kind)Row.")
        )
    }

    func testPinSelectionAndSavedLensDeletion() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab", "profile",
        ]
        app.launch()

        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        for _ in 0..<5 where preview.frame.maxY > app.frame.maxY - 100 || !preview.isHittable {
            app.swipeUp()
        }
        preview.tap()

        XCTAssertFalse(app.tabBars.firstMatch.exists)

        selectProfileFixturePin(in: app)

        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 6))
        capture("REC-338 selected personal map pin")

        app.buttons["yourMap.prototype.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["This year"].tap()
        app.buttons["yourMap.prototype.saveLens"].tap()

        let savedLens = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
        ).firstMatch
        XCTAssertTrue(savedLens.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(savedLens.frame.width, app.frame.width * 0.9)

        savedLens.swipeLeft()
        XCTAssertLessThan(savedLens.frame.maxX, app.frame.maxX - 40)
        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.deleteLens.")
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        XCTAssertTrue(deleteButton.isHittable)
        capture("REC-338 saved lens delete reveal")

        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["No saved lenses yet"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
            ).count,
            0
        )
    }

    func testSnapshotCreatesListAndOpensEditorWithoutDuplicatePlaceControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderResetWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        // The combined preview can exist below the tab bar. Bring its actual
        // tap target into view before opening Explore on every phone size.
        for _ in 0..<5 where preview.frame.maxY > app.frame.maxY - 100 || !preview.isHittable {
            app.swipeUp()
        }
        preview.tap()
        let snapshot = app.buttons["yourMap.snapshot"]
        XCTAssertTrue(snapshot.waitForExistence(timeout: 10))
        let pin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin.")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        capture("REC-413 Explore snapshot control")
        snapshot.tap()
        let toast = app.buttons["yourMap.viewSnapshotList"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertEqual(toast.label, "Edit")
        XCTAssertTrue(app.staticTexts["View snapshot list"].exists)
        capture("REC-413 Snapshot saved toast")
        toast.tap()
        XCTAssertTrue(app.staticTexts["edit list"].waitForExistence(timeout: 5))
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let existing = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Snapshot test\n")
        let cover = app.images["Saved map snapshot"]
        for _ in 0..<6 {
            if cover.exists && cover.frame.minY > 100 && cover.frame.maxY < app.frame.maxY - 180 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            )
        }
        XCTAssertTrue(cover.isHittable)
        capture("REC-413 Static snapshot cover")
        XCTAssertFalse(app.buttons["listEditor.addPlaces"].exists)
        XCTAssertFalse(app.staticTexts["Place changes save immediately."].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Remove ", " from list")).count, 0)
        let collaborators = app.staticTexts["collaborators"]
        for _ in 0..<3 where !collaborators.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(collaborators.isHittable)
        XCTAssertTrue(app.buttons["Save changes"].exists)
        XCTAssertTrue(app.buttons["Delete List"].exists)
        capture("REC-480 Snapshot list editor without duplicate places")
    }

    private func selectProfileFixturePin(in app: XCUIApplication) {
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin."))
        XCTAssertTrue(pins.firstMatch.waitForExistence(timeout: 8))
        // The four LA fixture saves overlap at the initial city overview.
        // Tap the center of the overlapping group to exercise physical hit
        // testing instead of asking XCTest to activate a covered marker.
        let frames = pins.allElementsBoundByIndex.map(\.frame).filter { app.frame.contains($0) }
        guard !frames.isEmpty else { return XCTFail("Expected profile fixture pins in the viewport") }
        let center = CGVector(
            dx: frames.map(\.midX).reduce(0, +) / CGFloat(frames.count),
            dy: frames.map(\.midY).reduce(0, +) / CGFloat(frames.count)
        )
        app.coordinate(withNormalizedOffset: .zero).withOffset(center).tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
