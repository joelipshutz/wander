import XCTest

/// Native MapKit comparisons only. Every run uses the same isolated Live fixture.
@MainActor
final class LiveMapStyleLabUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    func testPaperMapStyle() throws { try verifyStyle("paper") }
    func testAtlasMapStyle() throws { try verifyStyle("atlas") }
    func testInkMapStyle() throws { try verifyStyle("ink") }
    func testMidnightMapStyle() throws { try verifyStyle("midnight") }
    func testAerialMapStyle() throws { try verifyStyle("aerial") }

    /// Independent overlay coverage so a gesture assertion cannot prevent the
    /// visual and apply/clear checks from running on all five configurations.
    func testDrawingAcrossAllStyles() throws {
        executionTimeAllowance = 600
        continueAfterFailure = true
        for style in ["paper", "atlas", "ink", "midnight", "aerial"] {
            let app = launch(style: style)
            let introduction = app.buttons["live.introduction.notNow"]
            if introduction.exists && introduction.isHittable { introduction.tap() }
            collapseDrawer(in: app)
            let pin = app.buttons["live.pin.place_bar_nido"]
            waitHittable(pin)
            waitForStableFrames([pin, app.maps.firstMatch], minimumDuration: 3)
            verifyDrawnArea(style: style, in: app)
            app.terminate()
        }
    }

    private func verifyStyle(_ style: String) throws {
        let app = launch(style: style)
        defer { app.terminate() }
        let pin = app.buttons["live.pin.place_bar_nido"]
        let introduction = app.buttons["live.introduction.notNow"]
        if introduction.exists && introduction.isHittable { introduction.tap() }
        collapseDrawer(in: app)
        waitHittable(pin, timeout: 20)
        waitForStableFrames([app.maps.firstMatch, pin, drawer(in: app)], minimumDuration: 3)
        app.maps.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        waitHittable(pin)
        waitForStableFrames([app.maps.firstMatch, pin], minimumDuration: 3)
        XCTAssertFalse(app.buttons["live.placePreview.open"].exists)
        capture(style, "overview")

        try tapPinAtPhysicalCenter(pin, in: app)
        let open = app.buttons["live.placePreview.open"]
        waitHittable(open)
        XCTAssertEqual(open.label, "Open Bar Nido")
        let controls = ["add", "share", "list", "close"].map { app.buttons["live.placePreview.\($0)"] }
        for control in controls {
            waitHittable(control)
            XCTAssertTrue(app.frame.contains(control.frame), "\(control.identifier) must be fully onscreen.")
        }
        waitForStableFrames([open] + controls + [app.maps.firstMatch], minimumDuration: 2)
        capture(style, "selected")

        // Exercise dismissal as well as the selected card's destination.
        app.buttons["live.placePreview.close"].tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
        waitHittable(pin)
        waitForStableFrames([pin], minimumDuration: 1)
        try tapPinAtPhysicalCenter(pin, in: app)
        waitHittable(open)
        open.tap()
        let back = app.buttons["place-profile.back"]
        waitHittable(back)
        XCTAssertTrue(app.staticTexts["Bar Nido"].firstMatch.waitForExistence(timeout: 5))
        waitForStableFrames([back], minimumDuration: 0.5)
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10))
        waitHittable(app.buttons["live.draw"])
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)

        verifyFilterApplyAndCancel(in: app)
        collapseDrawer(in: app)
        waitHittable(pin)
        waitForStableFrames([pin, drawer(in: app)], minimumDuration: 1)
        try verifyNativePan(in: app)
    }

    private func launch(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
            "-WanderLiveMapStyle", style,
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        if app.buttons["productUpsell.secondary"].waitForExistence(timeout: 4) {
            app.buttons["productUpsell.secondary"].tap()
        }
        waitHittable(app.buttons["live.draw"], timeout: 30)
        waitHittable(app.buttons["Filters"])
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15))
        waitHittable(drawer(in: app))
        return app
    }

    private func verifyFilterApplyAndCancel(in app: XCUIApplication) {
        openFilters(in: app)
        selectPeople("Only Friends", in: app)
        app.buttons["live.applyFilters"].tap()
        XCTAssertTrue(app.buttons["live.applyFilters"].waitForNonExistence(timeout: 5))
        waitHittable(app.buttons["live.draw"])
        wait("The applied audience must reach the Live drawer.") {
            (self.drawer(in: app).value as? String)?.contains("Only Friends") == true
        }
        let committed = drawer(in: app).value as? String

        openFilters(in: app)
        XCTAssertEqual(app.buttons["live.filter.people"].value as? String, "Only Friends")
        selectPeople("Everyone", in: app)
        let cancel = app.navigationBars["Filters"].buttons["Cancel"]
        waitHittable(cancel)
        cancel.tap()
        XCTAssertTrue(app.buttons["live.applyFilters"].waitForNonExistence(timeout: 5))
        waitHittable(app.buttons["live.draw"])
        XCTAssertEqual(drawer(in: app).value as? String, committed,
                       "Cancelling the staged audience must retain the committed filter.")

        openFilters(in: app)
        XCTAssertEqual(app.buttons["live.filter.people"].value as? String, "Only Friends")
        selectPeople("Everyone", in: app)
        app.buttons["live.applyFilters"].tap()
        XCTAssertTrue(app.buttons["live.applyFilters"].waitForNonExistence(timeout: 5))
        waitHittable(app.buttons["live.draw"])
        wait("Applying Everyone must remove the committed friends filter.") {
            guard let value = self.drawer(in: app).value as? String else { return false }
            return !value.contains("Only Friends")
        }
    }

    private func openFilters(in app: XCUIApplication) {
        let filters = app.buttons["Filters"]
        waitHittable(filters)
        waitForStableFrames([filters], minimumDuration: 1)
        filters.tap()
        waitHittable(app.buttons["live.filter.people"])
        waitHittable(app.buttons["live.applyFilters"])
    }

    private func selectPeople(_ audience: String, in app: XCUIApplication) {
        let picker = app.buttons["live.filter.people"]
        waitHittable(picker)
        picker.tap()
        let choice = app.collectionViews.buttons.matching(NSPredicate(format: "label == %@", audience)).element
        waitHittable(choice)
        choice.tap()
        wait("The native People picker must commit its staged value.") {
            picker.exists && picker.value as? String == audience && !choice.exists
        }
        waitHittable(app.buttons["live.applyFilters"])
    }

    private func collapseDrawer(in app: XCUIApplication) {
        let handle = drawer(in: app)
        waitHittable(handle)
        if handle.label != "Activity drawer, collapsed" {
            handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        }
        wait("The drawer must collapse before native map gestures.") {
            handle.label == "Activity drawer, collapsed"
        }
        waitHittable(app.buttons["live.draw"])
    }

    private func verifyNativePan(in app: XCUIApplication) throws {
        let anchor = app.buttons["live.pin.place_bar_nido"]
        let viewport = try exposedMapFrame(in: app)
        let before = try anchor.snapshot().frame
        let pins = livePins(in: app)
        let pinFrames = try pins.map { try $0.snapshot().frame }
        let distance: CGFloat = before.midX < viewport.midX ? 28 : -28
        let paths = [0.25, 0.5, 0.75].flatMap { y in
            [0.25, 0.5, 0.75].map { x in
                let start = CGPoint(x: viewport.minX + viewport.width * x, y: viewport.minY + viewport.height * y)
                return (start, CGPoint(x: start.x + distance, y: start.y))
            }
        }
        let path = try XCTUnwrap(paths.first { start, end in
            let bounds = CGRect(x: min(start.x, end.x), y: start.y - 12,
                                width: abs(end.x - start.x), height: 24).insetBy(dx: -12, dy: 0)
            return viewport.contains(bounds) && !pinFrames.contains(where: { $0.intersects(bounds) })
        }, "The native pan needs a clear path inside the exposed map.")
        coordinate(path.0, in: app).press(forDuration: 0.1, thenDragTo: coordinate(path.1, in: app),
                                         withVelocity: XCUIGestureVelocity(rawValue: 60), thenHoldForDuration: 0.1)
        wait("The native pan must visibly displace the fixture pin.") {
            guard anchor.exists else { return false }
            return abs(anchor.frame.midX - before.midX) > 3
        }
        waitForStableFrames([anchor], minimumDuration: 1)
        XCTAssertFalse(app.buttons["live.placePreview.open"].exists, "The pan must not accidentally select a marker.")
    }

    private func verifyDrawnArea(style: String, in app: XCUIApplication) {
        let draw = app.buttons["live.draw"]
        waitHittable(draw)
        draw.tap()
        let apply = app.buttons["live.applyArea"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "An empty drawing must not be applicable.")
        let visibleArea = app.buttons["Use visible area"]
        waitHittable(visibleArea)
        visibleArea.tap()
        waitHittable(apply)
        waitForStableFrames([apply, app.maps.firstMatch], minimumDuration: 1)
        capture(style, "draw-review")
        apply.tap()
        let clear = app.buttons["live.clearArea"]
        waitHittable(clear)
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))
        waitForStableFrames([clear, draw], minimumDuration: 2)
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
        waitHittable(draw)
    }

    private func tapPinAtPhysicalCenter(_ pin: XCUIElement, in app: XCUIApplication) throws {
        waitHittable(pin)
        let frame = try pin.snapshot().frame
        let viewport = try exposedMapFrame(in: app)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(viewport.contains(center), "The marker center must be physically exposed above the drawer.")
        // Use an actual screen coordinate; do not invoke the annotation's AX action.
        coordinate(center, in: app).tap()
    }

    private func exposedMapFrame(in app: XCUIApplication) throws -> CGRect {
        let map = try app.maps.firstMatch.snapshot().frame.intersection(app.frame)
        let controls = [app.buttons["live.draw"], app.buttons["Filters"], app.buttons["Add a place"]]
            .filter { $0.exists && $0.isHittable }
        let top = max(map.minY, controls.map { $0.frame.maxY }.max() ?? map.minY) + 12
        var bottom = min(map.maxY, try drawer(in: app).snapshot().frame.minY) - 12
        let searchArea = app.buttons["live.searchArea"]
        if searchArea.exists && searchArea.isHittable { bottom = min(bottom, searchArea.frame.minY - 12) }
        let viewport = CGRect(x: map.minX + 12, y: top, width: map.width - 24, height: bottom - top)
        XCTAssertTrue(finite(viewport) && viewport.width > 160 && viewport.height > 120)
        return viewport
    }

    private func drawer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["live.drawerHandle"].firstMatch
    }

    private func livePins(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin.")).allElementsBoundByIndex
    }

    private func coordinate(_ point: CGPoint, in app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    private func finite(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isNull && !frame.isInfinite
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite }
    }

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        wait("The expected native control must be enabled and hittable.", timeout: timeout) {
            element.exists && element.isEnabled && element.isHittable
        }
    }

    private func waitForStableFrames(_ elements: [XCUIElement], minimumDuration: TimeInterval) {
        let started = ProcessInfo.processInfo.systemUptime
        var stableSince = started
        var previous: [CGRect] = []
        // MapKit has no tile-loaded AX signal. Wait for settled native camera /
        // control geometry and allow rendering time; inspect the attached pixels.
        wait("Native map and control geometry must settle before capture or input.", timeout: 15) {
            guard elements.allSatisfy({ $0.exists }),
                  let frames = try? elements.map({ try $0.snapshot().frame }),
                  frames.allSatisfy(self.finite) else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            if frames != previous {
                previous = frames
                stableSince = now
            }
            return now - started >= minimumDuration && now - stableSince >= 1
        }
    }

    private func wait(_ message: String, timeout: TimeInterval = 10, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func capture(_ style: String, _ state: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC661-\(style)-\(state)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
