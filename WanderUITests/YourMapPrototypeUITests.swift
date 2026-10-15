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

        let dot = try isolatedInitialDot(in: app, pins: pins)
        let dotID = dot.identifier
        let dotPosition = dot.frame
        dot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

        // A full-Map native gesture spreads contacts into header/footer chrome.
        // Reacquire a fully visible native pin canvas before every zoom gesture.
        for _ in 0..<6 {
            let zoomTarget = try freshZoomOutTarget(in: app, pins: pins)
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
        let patterns = app.scrollViews["yourMap.prototype.patterns"]
        let picker = app.descendants(matching: .any).matching(identifier: "yourMap.prototype.mode").firstMatch
        func revealGeographyMetrics() -> Bool {
            func finite(_ frame: CGRect) -> Bool {
                !frame.isNull && !frame.isInfinite && !frame.isEmpty
                    && frame.minY.isFinite && frame.maxY.isFinite && frame.height.isFinite
            }
            // Expansion can move the footer and following card beneath the
            // fixed mode picker on compact phones, even when AX says hittable.
            for attempt in 0...5 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                let bottom = picker.frame.minY - 8
                let cardFrame = card.frame
                let monthFrame = month.frame
                let toggleFrame = toggle.frame
                if finite(cardFrame), finite(monthFrame), finite(toggleFrame),
                   monthFrame.minY < bottom, toggleFrame.minY > top,
                   toggleFrame.maxY < bottom, toggle.isHittable {
                    return true
                }
                guard attempt < 5 else { break }
                let needsDown = finite(toggleFrame) && toggleFrame.minY <= top
                patterns.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: needsDown ? 0.5 : 0.75))
                    .press(forDuration: 0.1, thenDragTo: patterns.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.98, dy: needsDown ? 0.75 : 0.5)))
            }
            XCTFail("Geography metrics and toggle must enter usable scroll content")
            return false
        }
        guard revealGeographyMetrics() else { return }
        let collapsedHeight = card.frame.height
        let collapsedGap = month.frame.minY - card.frame.maxY
        capture("REC-417 geography collapsed")

        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["yourMap.prototype.cityRow.Amsterdam"].waitForExistence(timeout: 3))
        XCTAssertEqual(cityRows.count, 10)
        XCTAssertEqual(countryRows.count, 10)
        XCTAssertEqual(toggle.value as? String, "Expanded")
        guard revealGeographyMetrics() else { return }
        XCTAssertGreaterThan(card.frame.height, collapsedHeight + 100)
        XCTAssertEqual(month.frame.minY - card.frame.maxY, collapsedGap, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.cityRow.Berlin"].exists)
        capture("REC-417 geography expanded")

        guard revealGeographyMetrics() else { return }
        toggle.tap()
        let collapsed = NSPredicate(format: "value == %@", "Collapsed")
        expectation(for: collapsed, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(cityRows.count, 5)
        XCTAssertEqual(countryRows.count, 5)
        guard revealGeographyMetrics() else { return }
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

    private func isolatedInitialDot(in app: XCUIApplication, pins: XCUIElementQuery) throws -> XCUIElement {
        typealias Pin = (element: XCUIElement, id: String, frame: CGRect, isDot: Bool)
        typealias Neighbor = (id: String, distance: CGFloat)
        typealias Candidate = (pin: Pin, nearestID: String, distance: CGFloat)
        func finiteFrame(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && !frame.isEmpty
                && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
        }
        // Keep the original initial-selection bounds. The first selection has
        // no title offset, so every native canvas center is its marker center.
        let viewport = app.frame.insetBy(dx: 12, dy: 180)
        let all: [Pin] = pins.allElementsBoundByIndex.map { element -> Pin in
            (element, element.identifier, element.frame, element.value as? String == "Map dot")
        }
        guard !all.isEmpty, all.allSatisfy({ finiteFrame($0.frame) }) else {
            capture("REC-573 initial dot has unresolved native geometry")
            return try XCTUnwrap(nil as XCUIElement?, "Native pin geometry is unavailable for a safe physical dot tap")
        }
        var candidates: [Candidate] = []
        for pin in all {
            guard pin.isDot, viewport.contains(pin.frame), pin.element.isHittable else { continue }
            let point = CGPoint(x: pin.frame.midX, y: pin.frame.midY)
            let others: [Pin] = all.filter { $0.id != pin.id }
            guard !others.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }) else { continue }
            var nearest: Neighbor?
            for other in others {
                let dx: CGFloat = point.x - other.frame.midX
                let dy: CGFloat = point.y - other.frame.midY
                let distance: CGFloat = hypot(dx, dy)
                if let previous = nearest {
                    if distance < previous.distance || (distance == previous.distance && other.id < previous.id) {
                        nearest = (id: other.id, distance: distance)
                    }
                } else {
                    nearest = (id: other.id, distance: distance)
                }
            }
            // Completed native taps pick the nearest marker within 34pt.
            // >2pt separates the exact center from the source's 0.5pt equal-
            // distance and 1pt colocated tolerances; 34pt nonoverlap would
            // incorrectly reject every ordinary dot on this 13pt fixture grid.
            guard let nearest, nearest.distance > 2 else { continue }
            candidates.append((pin: pin, nearestID: nearest.id, distance: nearest.distance))
        }
        candidates.sort { lhs, rhs in
            lhs.distance == rhs.distance ? lhs.pin.id < rhs.pin.id : lhs.distance > rhs.distance
        }
        if candidates.isEmpty { capture("REC-573 no isolated initial dot center") }
        let chosen: Candidate = try XCTUnwrap(candidates.first, "Expected one bounded dot with a uniquely nearest physical center")
        let diagnostic = XCTAttachment(string: "id=\(chosen.pin.id); frame=\(chosen.pin.frame); viewport=\(viewport); nearestID=\(chosen.nearestID); nearestCenterDistance=\(chosen.distance)")
        diagnostic.name = "REC-573 initial physical dot target"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        return chosen.pin.element
    }

    private func freshZoomOutTarget(in app: XCUIApplication, pins: XCUIElementQuery) throws -> XCUIElement {
        typealias Pin = (element: XCUIElement, id: String, frame: CGRect)
        func finiteFrame(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && !frame.isEmpty
                && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
        }
        let headerFrames = [app.navigationBars.firstMatch.frame,
                            app.buttons["yourMap.snapshot"].frame,
                            app.buttons["yourMap.prototype.filters"].frame]
        let modeFrame = app.buttons.matching(identifier: "yourMap.prototype.mode").firstMatch.frame
        XCTAssertTrue(headerFrames.allSatisfy(finiteFrame) && finiteFrame(modeFrame))
        let top = try XCTUnwrap(headerFrames.map(\.maxY).max()) + 12
        let viewport = CGRect(x: app.frame.minX + 12, y: top,
                              width: app.frame.width - 24, height: modeFrame.minY - 12 - top)
        XCTAssertTrue(finiteFrame(viewport), "Map controls must leave a usable gesture viewport")

        func snapshot() -> [Pin] {
            pins.allElementsBoundByIndex.compactMap { element -> Pin? in
                let frame = element.frame
                return finiteFrame(frame) ? (element: element, id: element.identifier, frame: frame) : nil
            }.sorted {
                if $0.frame.height != $1.frame.height { return $0.frame.height > $1.frame.height }
                return $0.id < $1.id
            }
        }
        func safe(_ pin: Pin) -> Bool {
            pin.frame.width >= 44 && pin.frame.height >= 44
                && viewport.contains(pin.frame.insetBy(dx: -4, dy: -4)) && pin.element.isHittable
        }
        // Do not tap to promote a pin: XCTest may choose an empty part of an
        // annotation canvas and clear the existing selection. Zoom directly on
        // a freshly resolved, finite and fully bounded native pin canvas.
        let current = snapshot()
        let candidate = current.first(where: safe)
        if candidate == nil { capture("REC-573 no full native zoom-out target") }
        let target = try XCTUnwrap(candidate, "Expected a hittable full native pin canvas inside the map controls")
        let diagnostic = XCTAttachment(string: "id=\(target.id); frame=\(target.frame); viewport=\(viewport)")
        diagnostic.name = "REC-573 fresh native zoom-out target"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        return target.element
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
