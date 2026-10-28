import XCTest

/// Exercises production appearance settings against the isolated Live fixture.
@MainActor
final class MapAppearanceUITests: XCTestCase {
    private let colorID = "settings.map.coloredMap"
    private let darkID = "settings.map.darkMode"
    private let pinIDs = ["place_bar_nido", "place_juniper_table"]

    private struct CameraSample {
        let points: [String: CGPoint]
        let geometry: [String: Any]
        subscript(_ id: String) -> CGPoint? { points[id] }
    }

    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    func testLightMapAppearanceSettingsAndInteractions() throws {
        try verifyAppearance(dark: false)
    }

    func testDarkMapAppearanceSettingsAndInteractions() throws {
        try verifyAppearance(dark: true)
    }

    func testColoredMapSettingsPreservesCameraWithoutPriorInteractions() throws {
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        let app = launch()
        defer {
            app.terminate()
            XCUIDevice.shared.appearance = previousAppearance
        }
        let before = try cameraSample(in: app)
        try captureCameraGeometry("focused-before-settings", in: app)
        openSettings(in: app)
        XCTAssertFalse(try switchValue(colorID, in: app))
        try setSwitch(colorID, to: true, in: app)
        try returnToLive(in: app, diagnosticName: "focused")
        try assertCameraPreserved(before, in: app)
    }

    private func verifyAppearance(dark: Bool) throws {
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        let app = launch()
        defer {
            // Demo fixtures have no persistent store; terminating also discards
            // appearance changes if an assertion stops the normal cleanup path.
            app.terminate()
            XCUIDevice.shared.appearance = previousAppearance
        }
        openSettings(in: app)
        let originalColor = try switchValue(colorID, in: app)
        let originalDark = try switchValue(darkID, in: app)
        XCTAssertFalse(originalColor, "A fresh fixture must default to grayscale.")
        XCTAssertFalse(originalDark, "Dark map must remain opt-in when the system is light.")
        try setSwitch(darkID, to: dark, in: app)
        capture("\(dark ? "dark" : "light")-settings-grayscale")
        try returnToLive(in: app, diagnosticName: "initial-settings")

        for colored in [false, true] {
            let name = "\(dark ? "dark" : "light")-\(colored ? "colored" : "grayscale")"
            if colored {
                let before = try cameraSample(in: app)
                try captureCameraGeometry("\(name)-before-settings", in: app)
                openSettings(in: app)
                XCTAssertEqual(try switchValue(darkID, in: app), dark)
                try setSwitch(colorID, to: true, in: app)
                capture("\(name)-settings")
                try returnToLive(in: app, diagnosticName: name)
                try assertCameraPreserved(before, in: app)
            }

            // Establish the review framing in grayscale. Exercise color gestures
            // after its captures so the two appearances use comparable framing.
            if !colored {
                try verifyPan(in: app)
                try verifyZoom(in: app)
            }
            waitForStableFrames([map(in: app)] + pinIDs.map { pin($0, in: app) }, minimumDuration: 3)
            capture("\(name)-overview")
            try verifySelectedPlace(name: name, openProfile: !colored, in: app)
            if colored {
                try verifyPan(in: app)
                try verifyZoom(in: app)
            }
        }

        // Restore both switches using Settings, then check the return camera.
        let beforeCleanup = try cameraSample(in: app)
        try captureCameraGeometry("cleanup-before-settings", in: app)
        openSettings(in: app)
        try setSwitch(colorID, to: originalColor, in: app)
        try setSwitch(darkID, to: originalDark, in: app)
        try returnToLive(in: app, diagnosticName: "cleanup")
        try assertCameraPreserved(beforeCleanup, in: app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        if app.buttons["productUpsell.secondary"].waitForExistence(timeout: 4) {
            app.buttons["productUpsell.secondary"].tap()
        }
        waitHittable(app.buttons["live.draw"], timeout: 30)
        let introduction = app.buttons["live.introduction.notNow"]
        if introduction.exists && introduction.isHittable { introduction.tap() }
        XCTAssertTrue(map(in: app).waitForExistence(timeout: 15))
        collapseDrawer(in: app)
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let profile = app.tabBars.buttons["Profile"]
        waitHittable(profile)
        profile.tap()
        let settings = app.buttons["Settings"]
        waitHittable(settings)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitHittable(app.buttons["settings.back"])
        let screen = app.descendants(matching: .any)["settings.screen"].firstMatch
        let colored = app.switches[colorID]
        for _ in 0..<6 {
            if colored.exists && colored.isHittable && app.frame.contains(colored.frame) { break }
            screen.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)))
        }
        waitHittable(colored)
        waitHittable(app.switches[darkID])
    }

    private func switchValue(_ id: String, in app: XCUIApplication) throws -> Bool {
        let value = try XCTUnwrap(app.switches[id].value as? String)
        XCTAssertTrue(value == "0" || value == "1", "Expected the native switch's Boolean value for \(id).")
        return value == "1"
    }

    private func setSwitch(_ id: String, to enabled: Bool, in app: XCUIApplication) throws {
        let toggle = app.switches[id]
        waitHittable(toggle)
        if try switchValue(id, in: app) != enabled {
            waitForStableFrames([toggle], minimumDuration: 1)
            let frame = try toggle.snapshot().frame
            XCTAssertTrue(finite(frame) && app.frame.contains(frame))
            // SwiftUI exposes the entire labeled row as the switch. Its
            // midpoint is the label; the native switch is at the trailing edge.
            let thumb = CGPoint(x: frame.maxX - min(26, frame.width / 2), y: frame.midY)
            XCTAssertTrue(frame.contains(thumb))
            coordinate(thumb, in: app).tap()
        }
        wait("The actual Settings switch must reflect the requested appearance.") {
            toggle.value as? String == (enabled ? "1" : "0")
        }
    }

    private func returnToLive(in app: XCUIApplication, diagnosticName: String) throws {
        let back = app.buttons["settings.back"]
        waitHittable(back)
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        let live = app.tabBars.buttons["Live"]
        waitHittable(live)
        live.tap()
        waitHittable(app.buttons["live.draw"])
        try captureCameraGeometry("\(diagnosticName)-returned-before-collapse", in: app)
        collapseDrawer(in: app)
        waitForStableFrames([map(in: app)] + pinIDs.map { pin($0, in: app) }, minimumDuration: 2)
        try captureCameraGeometry("\(diagnosticName)-returned-settled", in: app)
    }

    private func verifySelectedPlace(name: String, openProfile: Bool, in app: XCUIApplication) throws {
        let selected = pin("place_bar_nido", in: app)
        waitHittable(selected)
        let target = try XCTUnwrap(physicalPinTarget(selected, in: app),
                                  "The physical pin tap must be inside its own target and outside neighboring targets.")
        coordinate(target, in: app).tap()
        let open = app.buttons["live.placePreview.open"]
        waitHittable(open)
        XCTAssertEqual(open.label, "Open Bar Nido")
        let controls = ["add", "share", "list", "close"].map { app.buttons["live.placePreview.\($0)"] }
        for control in controls {
            waitHittable(control)
            XCTAssertTrue(app.frame.contains(control.frame))
        }
        waitForStableFrames([open] + controls, minimumDuration: 2)
        capture("\(name)-selected")

        if openProfile {
            open.tap()
            let back = app.buttons["place-profile.back"]
            waitHittable(back)
            XCTAssertTrue(app.staticTexts["Bar Nido"].firstMatch.waitForExistence(timeout: 5))
            waitForStableFrames([back], minimumDuration: 1)
            back.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 10))
            waitHittable(open)
            XCTAssertEqual(open.label, "Open Bar Nido", "Returning from the profile must retain the selected place.")
        }
        let close = app.buttons["live.placePreview.close"]
        waitHittable(close)
        close.tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
        waitHittable(app.buttons["live.draw"])
        collapseDrawer(in: app)
        waitForStableFrames(pinIDs.map { pin($0, in: app) }, minimumDuration: 1)
    }

    private func physicalPinTarget(_ selected: XCUIElement, in app: XCUIApplication) throws -> CGPoint? {
        guard selected.exists else { return nil }
        let frame = selected.frame
        let otherFrames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex.filter { $0.identifier != selected.identifier }.map(\.frame)
        // Native annotations keep a real 44-point hit region even when their
        // visible dot is compact. All candidates stay inside that region.
        let offsets: [CGFloat] = [0.5, 0.8, 0.2, 0.95, 0.05]
        let candidates = offsets.flatMap { y in offsets.map { x in
            CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
        } }
        let viewport = try exposedMapFrame(in: app)
        return candidates.first { candidate in
            frame.contains(candidate) && viewport.contains(candidate)
                && !otherFrames.contains(where: { $0.contains(candidate) })
        }
    }

    private func verifyPan(in app: XCUIApplication) throws {
        let anchor = pin("place_bar_nido", in: app)
        waitHittable(anchor)
        let before = point(anchor.frame)
        let viewport = try exposedMapFrame(in: app)
        let distance: CGFloat = before.x < viewport.midX ? 28 : -28
        let frames = livePinFrames(in: app)
        let positions: [CGFloat] = [0.25, 0.5, 0.75]
        let paths = positions.flatMap { y in positions.map { x in
            let start = CGPoint(x: viewport.minX + viewport.width * x, y: viewport.minY + viewport.height * y)
            return (start, CGPoint(x: start.x + distance, y: start.y))
        } }
        let path = try XCTUnwrap(paths.first { start, end in
            let bounds = CGRect(x: min(start.x, end.x) - 12, y: start.y - 12,
                                width: abs(distance) + 24, height: 24)
            return viewport.contains(bounds) && !frames.contains(where: { $0.intersects(bounds) })
        }, "The map pan needs an uncovered path outside marker controls.")
        coordinate(path.0, in: app).press(forDuration: 0.1, thenDragTo: coordinate(path.1, in: app),
                                         withVelocity: XCUIGestureVelocity(rawValue: 60), thenHoldForDuration: 0.1)
        wait("Panning must visibly displace the same geographic pin.") {
            anchor.exists && abs(anchor.frame.midX - before.x) > 3
        }
        waitForStableFrames(pinIDs.map { pin($0, in: app) }, minimumDuration: 1)
        XCTAssertFalse(app.buttons["live.placePreview.open"].exists)
    }

    private func verifyZoom(in app: XCUIApplication) throws {
        for _ in 0..<4 {
            try verifyOneZoomStep(in: app)
            if try physicalPinTarget(pin("place_bar_nido", in: app), in: app) != nil { return }
        }
        XCTFail("Four verified zoom steps must reveal an unambiguous physical Bar Nido tap target.")
    }

    private func verifyOneZoomStep(in app: XCUIApplication) throws {
        let before = try cameraSample(in: app)
        let first = try XCTUnwrap(before[pinIDs[0]])
        let second = try XCTUnwrap(before[pinIDs[1]])
        let separation = distance(first, second)
        XCTAssertGreaterThan(separation, 2)
        let viewport = try exposedMapFrame(in: app)
        let markerFrames = livePinFrames(in: app).map { $0.insetBy(dx: -12, dy: -12) }
        let midpoint = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        let offsets: [CGFloat] = [0, -60, 60, -100, 100]
        let candidates = offsets.flatMap { y in offsets.map { x in
            CGPoint(x: midpoint.x + x, y: midpoint.y + y)
        } }.sorted { distance($0, midpoint) < distance($1, midpoint) }
        let target = try XCTUnwrap(candidates.first { candidate in
            viewport.insetBy(dx: 24, dy: 24).contains(candidate)
                && !markerFrames.contains(where: { $0.contains(candidate) })
        }, "Double-tap zoom must target blank map, outside every marker hit region.")
        coordinate(target, in: app).doubleTap()
        wait("Zoom must increase separation between the same identified geographic pins.") {
            let a = self.pin(self.pinIDs[0], in: app)
            let b = self.pin(self.pinIDs[1], in: app)
            return a.exists && b.exists && self.distance(self.point(a.frame), self.point(b.frame)) > separation * 1.15
        }
        waitForStableFrames(pinIDs.map { pin($0, in: app) }, minimumDuration: 1)
        XCTAssertFalse(app.buttons["live.placePreview.open"].exists)
    }

    private func cameraSample(in app: XCUIApplication) throws -> CameraSample {
        waitForStableFrames(pinIDs.map { pin($0, in: app) }, minimumDuration: 1)
        let points = try Dictionary(uniqueKeysWithValues: pinIDs.map { id in
            let frame = try pin(id, in: app).snapshot().frame
            XCTAssertTrue(finite(frame))
            return (id, point(frame))
        })
        return CameraSample(points: points, geometry: try cameraGeometry(in: app))
    }

    private func assertCameraPreserved(_ before: CameraSample, in app: XCUIApplication) throws {
        let after = try cameraSample(in: app)
        capture("camera-preservation-before-assertion")
        try attachGeometry(["before": before.geometry, "after": after.geometry], name: "camera-preservation-comparison")
        for id in pinIDs {
            let original = try XCTUnwrap(before[id])
            let restored = try XCTUnwrap(after[id])
            XCTAssertEqual(restored.x, original.x, accuracy: 5, "Settings must retain the map camera for \(id).")
            XCTAssertEqual(restored.y, original.y, accuracy: 5, "Settings must retain the map camera for \(id).")
        }
    }

    private func cameraGeometry(in app: XCUIApplication) throws -> [String: Any] {
        let mapFrame = try map(in: app).snapshot().frame
        let annotations = try app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex.map { element -> [String: Any] in
                let frame = try element.snapshot().frame
                let center = point(frame)
                var entry: [String: Any] = ["identifier": element.identifier, "frame": frameJSON(frame),
                                            "center": ["x": Double(center.x), "y": Double(center.y)]]
                if finite(mapFrame) {
                    entry["normalizedCenterInMap"] = ["x": Double((center.x - mapFrame.minX) / mapFrame.width),
                                                       "y": Double((center.y - mapFrame.minY) / mapFrame.height)]
                }
                return entry
            }
        let controls = [drawer(in: app), app.buttons["live.draw"], app.buttons["Filters"],
                        app.buttons["Add a place"], app.buttons["live.searchArea"], app.tabBars.firstMatch]
        let controlFrames = try controls.filter(\.exists).map { element -> [String: Any] in
            ["identifier": element.identifier, "label": element.label, "frame": frameJSON(try element.snapshot().frame)]
        }
        return ["mapFrame": frameJSON(mapFrame), "appFrame": frameJSON(app.frame),
                "pins": annotations, "controls": controlFrames]
    }

    private func frameJSON(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY),
         "width": Double(frame.width), "height": Double(frame.height)]
    }

    private func captureCameraGeometry(_ name: String, in app: XCUIApplication) throws {
        capture("camera-\(name)")
        try attachGeometry(cameraGeometry(in: app), name: "camera-\(name)")
    }

    private func attachGeometry(_ geometry: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "REC661-production-\(name).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func collapseDrawer(in app: XCUIApplication) {
        let handle = drawer(in: app)
        waitHittable(handle)
        if handle.label != "Activity drawer, collapsed" {
            handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        }
        wait("The drawer must collapse before measuring the visible map.") {
            handle.label == "Activity drawer, collapsed"
        }
        waitHittable(app.buttons["live.draw"])
    }

    private func exposedMapFrame(in app: XCUIApplication) throws -> CGRect {
        let frame = try map(in: app).snapshot().frame.intersection(app.frame)
        let controls = [app.buttons["live.draw"], app.buttons["Filters"], app.buttons["Add a place"]]
            .filter { $0.exists && $0.isHittable }
        let top = max(frame.minY, controls.map { $0.frame.maxY }.max() ?? frame.minY) + 12
        var bottom = min(frame.maxY, drawer(in: app).frame.minY) - 12
        let search = app.buttons["live.searchArea"]
        if search.exists && search.isHittable { bottom = min(bottom, search.frame.minY - 12) }
        let exposed = CGRect(x: frame.minX + 12, y: top, width: frame.width - 24, height: bottom - top)
        XCTAssertTrue(finite(exposed) && exposed.width > 160 && exposed.height > 120)
        return exposed
    }

    // MKMapView exposes live.map on an Other container and its native Map as a
    // child without an identifier. Annotations appear twice in that AX tree.
    private func map(in app: XCUIApplication) -> XCUIElement { app.maps.firstMatch }
    private func pin(_ id: String, in app: XCUIApplication) -> XCUIElement { app.buttons["live.pin.\(id)"].firstMatch }
    private func drawer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["live.drawerHandle"].firstMatch
    }
    private func livePinFrames(in app: XCUIApplication) -> [CGRect] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex.map(\.frame).filter(finite)
    }
    private func point(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
    private func coordinate(_ point: CGPoint, in app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }
    private func finite(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isNull && !frame.isInfinite
            && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
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
        wait("Map and control geometry must settle before capture or input.", timeout: 15) {
            guard elements.allSatisfy({ $0.exists }),
                  let frames = try? elements.map({ try $0.snapshot().frame }), frames.allSatisfy(self.finite) else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            if frames != previous { previous = frames; stableSince = now }
            return now - started >= minimumDuration && now - stableSince >= 1
        }
    }
    private func wait(_ message: String, timeout: TimeInterval = 10, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed { capture("interaction-failure") }
        XCTAssertEqual(result, .completed, message)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC661-production-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
