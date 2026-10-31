import XCTest

/// Runs unchanged against baseline and candidate. Uses the production Live
/// views with fictional, memory-only 300-place / 600-event scale data.
@MainActor
final class LivePerformanceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    func testLargeLiveLaunchToReady() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var readySamples: [Double] = []
        measure(metrics: [XCTApplicationLaunchMetric(), XCTClockMetric()], options: options) {
            app.terminate()
            startMeasuring()
            let start = ProcessInfo.processInfo.systemUptime
            app.launch()
            waitForLoadedScale(in: app)
            readySamples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            stopMeasuring()
        }
        // XCTest discards its first invocation as warm-up; report the same three
        // measured launches, including Live readiness beyond process launch.
        let measured = Array(readySamples.suffix(3))
        XCTAssertEqual(measured.count, 3)
        record("launch_to_live_ready places=300 events=600 samples_ms=\(measured) median_ms=\(measured.sorted()[1])")
        capture("large-live-launch-ready", app: app)
    }

    func testLargeLiveDrawerAndFeedScrollHitches() {
        let app = application()
        app.launch()
        waitForLoadedScale(in: app)
        let start = ProcessInfo.processInfo.systemUptime
        expandDrawer(in: app)
        record("drawer_expand_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1_000)")
        let scroll = app.scrollViews["feed.places.scroll"].firstMatch
        wait(scroll)
        XCTAssertGreaterThanOrEqual(loadedFeedCount(scroll), 20)
        let first = app.descendants(matching: .any)["feed.activity.live-perf-000-0.postcard"].firstMatch
        wait(first)
        let originalY = first.frame.minY
        var moved = false
        measureInteraction(in: app) {
            scroll.swipeUp(velocity: .fast)
            moved = !first.isHittable || first.frame.minY < originalY - 20
            scroll.swipeUp(velocity: .fast)
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(moved, "Measured native swipes must move actual Feed cards.")
        XCTAssertGreaterThanOrEqual(loadedFeedCount(scroll), 20)
        XCTAssertLessThanOrEqual(loadedFeedCount(scroll), 600)
        capture("large-live-feed-after-scrolling", app: app)
        let showMap = app.buttons["live.showMap"]
        wait(showMap)
        showMap.tap()
        waitForDetent("collapsed", in: app)
        XCTAssertGreaterThanOrEqual(uniquePinIDs(in: app).count, 300,
                                    "The Feed viewport must not clip the independently loaded map.")
    }

    func testLargeLiveNativeMapGesturesAndPlaceReturn() throws {
        let app = application()
        app.launch()
        waitForLoadedScale(in: app)
        collapseDrawer(in: app)
        let map = app.maps.firstMatch
        wait(map)
        let ids = uniquePinIDs(in: app).sorted()
        XCTAssertGreaterThanOrEqual(ids.count, 300)
        var focusID = try XCTUnwrap(recenterFixturePin(in: app, preferredID: nil),
            "Expected a visible fixture pin before the native gesture measurement.")
        waitForDetent("collapsed", in: app)
        // Choose separated, currently visible annotations after recentering.
        // Offscreen annotation AX frames can remain stale across camera moves.
        let anchors = try XCTUnwrap(visibleAnchorIDs(in: app),
            "Expected two separated visible annotations for native gesture evidence.")
        settleMapGeometry(in: app, anchorIDs: anchors)
        let evidence = try liveSnapshot(in: app)
        record("native_camera_probe distance_m=\(evidence.cameraDistanceMeters.map { String($0) } ?? "missing") pin_value=\(evidence.firstPinRawValue)")
        _ = try XCTUnwrap(evidence.cameraDistanceMeters,
            "Fixture pin accessibility must export the actual native camera before measuring gestures.")
        var beforePan = CGRect.null
        var afterPan = CGRect.null
        var panStartPoint = CGPoint.zero
        var panEndPoint = CGPoint.zero
        var didPan = false
        var didZoom = false
        var drawerStayedCollapsed = true
        var panDistance: CGFloat = 0
        var beforeZoomDistance: Double = 0
        var afterZoomDistance: Double = 0
        measureInteraction(in: app) {
            // Re-read after XCTest's skipped warmup; pending map layout must not
            // make either the reference frames or gesture coordinates stale.
            guard let snapshot = try? self.liveSnapshot(in: app),
                  let first = snapshot.pins[anchors.0], let second = snapshot.pins[anchors.1],
                  let panStart = self.blankMapCoordinate(in: app, horizontalTravel: 40) else {
                XCTFail("Expected current visible anchors and an uncovered pan path")
                return
            }
            beforePan = first.frame
            let beforeReference = second.frame
            let panEnd = panStart.withOffset(CGVector(dx: 40, dy: 0))
            panStartPoint = panStart.screenPoint
            panEndPoint = panEnd.screenPoint
            panStart.press(forDuration: 0.05, thenDragTo: panEnd,
                withVelocity: .slow, thenHoldForDuration: 0.2)
            didPan = self.observeMapGeometry(in: app, timeout: 5) { current in
                guard let first = current.pins[anchors.0], let second = current.pins[anchors.1] else { return false }
                afterPan = first.frame
                panDistance = self.distance(beforePan, afterPan)
                // Two annotations must move in the drag direction. A density
                // style change or stale individual AX frame cannot satisfy it.
                return panDistance > 8 && first.frame.midX - beforePan.midX > 8
                    && second.frame.midX - beforeReference.midX > 8
            }
            drawerStayedCollapsed = drawerStayedCollapsed
                && self.drawer(in: app).label == "Activity drawer, collapsed"
            panEnd.press(forDuration: 0.05, thenDragTo: panStart,
                withVelocity: .slow, thenHoldForDuration: 0.2)
            guard let zoomSnapshot = try? self.liveSnapshot(in: app),
                  let cameraDistance = zoomSnapshot.cameraDistanceMeters,
                  cameraDistance.isFinite, cameraDistance > 0 else {
                self.capture("large-live-missing-native-camera-metadata", app: app)
                XCTFail("Expected finite positive native camera metadata from fixture pins before zoom")
                return
            }
            guard let zoomPoint = self.blankMapCoordinate(in: app) else {
                self.recordSelectionGeometry(in: app, round: -1, focusID: focusID)
                self.capture("large-live-missing-blank-zoom-point", app: app)
                XCTFail("Expected an uncovered blank native zoom point")
                return
            }
            beforeZoomDistance = cameraDistance
            // Coordinate double-tap stays wholly on the uncovered native map.
            // Element pinch can place its second finger behind the drawer.
            zoomPoint.doubleTap()
            didZoom = self.observeMapGeometry(in: app, timeout: 5) { current in
                guard let cameraDistance = current.cameraDistanceMeters,
                      cameraDistance.isFinite, cameraDistance > 0 else { return false }
                afterZoomDistance = cameraDistance
                return afterZoomDistance < beforeZoomDistance * 0.9
            }
            drawerStayedCollapsed = drawerStayedCollapsed
                && self.drawer(in: app).label == "Activity drawer, collapsed"
        }
        record("native_map_geometry anchor=\(anchors.0) reference=\(anchors.1) pan_start=\(panStartPoint) pan_end=\(panEndPoint) before_pan=\(beforePan) after_pan=\(afterPan) pan_pt=\(panDistance) before_zoom_m=\(beforeZoomDistance) after_zoom_m=\(afterZoomDistance)")
        capture("large-live-after-native-pan-and-zoom", app: app)
        XCTAssertTrue(didPan, "The measured pan must move a real annotation.")
        XCTAssertTrue(didZoom, "The measured native zoom must reduce the actual camera distance by more than 10%.")
        XCTAssertTrue(drawerStayedCollapsed, "Map gestures must leave the drawer collapsed; detent camera changes cannot count as zoom.")
        XCTAssertTrue(drawer(in: app).value as? String != nil)
        XCTAssertTrue((drawer(in: app).value as? String)?.contains("100+") == true)

        // Separate 44pt hit targets using actual zoom gestures before testing a
        // particular venue; dense neighboring dots must not choose the target.
        var separatedPin = isolatedPin(in: app)
        for round in 0..<6 where separatedPin == nil {
            focusID = try XCTUnwrap(recenterFixturePin(in: app, preferredID: focusID),
                "Expected the fixture to remain visible while zooming to a particular pin.")
            recordSelectionGeometry(in: app, round: round, focusID: focusID)
            // Dense annotations can fill every blank tap location. Native
            // pinch works through annotation hit areas; keep it outside the
            // measured double-tap span and require the drawer to stay collapsed.
            waitForDetent("collapsed", in: app)
            map.pinch(withScale: 2, velocity: 1)
            waitForDetent("collapsed", in: app)
            separatedPin = isolatedPin(in: app)
        }
        recordSelectionGeometry(in: app, round: 6, focusID: focusID)
        capture("large-live-separated-pin-selection", app: app)
        let pin = try XCTUnwrap(separatedPin, "Expected a separated native annotation after zooming in.")
        settle(pin)
        let pinID = pin.identifier
        let name = String(pin.label.split(separator: ",", maxSplits: 1)[0])
        pin.tap()
        let open = app.buttons["live.placePreview.open"]
        wait(open)
        XCTAssertEqual(open.label, "Open \(name)")
        let previewEvents = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "live.placePreview.activity.live-perf-"))
        waitFor("Selected scale place retains its original activity", timeout: 20) { previewEvents.count >= 1 }
        open.tap()
        let back = app.buttons["place-profile.back"]
        wait(back, timeout: 30)
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10))
        back.tap()
        wait(open)
        XCTAssertEqual(open.label, "Open \(name)")
        app.buttons["live.placePreview.close"].tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 10))
        wait(app.buttons.matching(identifier: pinID).firstMatch)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
        capture("large-live-original-pin-after-profile-return", app: app)
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest",
            "-WanderLivePerformanceUITest", "-WanderInitialTab", "discover",
            "-astir.live.introduction.v1.perf_user_000.acknowledged", "YES",
            "-astir.live.introduction.v1.user_joe.acknowledged", "YES",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-recme.productUpsell.notification_app_open.perf_user_000.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        return app
    }

    private func waitForLoadedScale(in app: XCUIApplication) {
        wait(app.buttons["live.draw"], timeout: 180)
        let pinQuery = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "live.pin.perf_place_server_"))
        waitFor("Live scale data loaded", timeout: 180) {
            // Count is one AX request. Only inspect the full tree once there
            // are enough nodes; deduplication remains part of measured readiness.
            guard pinQuery.count >= 300, let snapshot = try? self.liveSnapshot(in: app) else { return false }
            return snapshot.liveSelected && snapshot.drawerValue.contains("100+")
                && snapshot.pins.count >= 300
        }
    }

    private func measureInteraction(in app: XCUIApplication, action: @escaping () -> Void) {
        var metrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(application: app)]
        if #available(iOS 19.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        var invocation = 0
        measure(metrics: metrics, options: options) {
            invocation += 1
            startMeasuring()
            if invocation > 1 { action() }
            stopMeasuring()
        }
    }

    private func uniquePinIDs(in app: XCUIApplication) -> Set<String> {
        guard let snapshot = try? liveSnapshot(in: app) else { return [] }
        return Set(snapshot.pins.keys)
    }

    private func isolatedPin(in app: XCUIApplication) -> XCUIElement? {
        guard let snapshot = try? liveSnapshot(in: app), !snapshot.mapFrame.isNull,
              !snapshot.drawFrame.isNull, !snapshot.drawerFrame.isNull else { return nil }
        let pins = Array(snapshot.pins.values)
        let viewport = snapshot.mapFrame.insetBy(dx: 24, dy: 24)
        // Every comparison uses local snapshot values. Resolve one live element
        // only after choosing the target; settle() checks its actual hittability.
        let selected = pins.sorted { $0.identifier < $1.identifier }.first { candidate in
            candidate.enabled && candidate.value == "Category pin"
                && viewport.contains(candidate.frame)
                && candidate.frame.minY > snapshot.drawFrame.maxY + 12
                && candidate.frame.maxY < snapshot.drawerFrame.minY - 12
                && pins.allSatisfy { $0.identifier == candidate.identifier || distance($0.frame, candidate.frame) > 48 }
        }
        guard let selected else { return nil }
        return app.buttons.matching(identifier: selected.identifier).firstMatch
    }

    /// Keep a real annotation in the uncovered viewport as native zoom changes
    /// the camera. This is test preparation, outside the measured gesture span.
    private func recenterFixturePin(in app: XCUIApplication, preferredID: String?) -> String? {
        guard let snapshot = try? liveSnapshot(in: app), let viewport = uncoveredViewport(snapshot) else { return nil }
        let center = CGPoint(x: viewport.midX, y: viewport.midY)
        let visible = snapshot.pins.values.filter {
            $0.enabled && viewport.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        let focus = visible.first { $0.identifier == preferredID } ?? visible.min {
            hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
                < hypot($1.frame.midX - center.x, $1.frame.midY - center.y)
        }
        guard let focus else { return nil }
        let point = CGPoint(x: focus.frame.midX, y: focus.frame.midY)
        if hypot(point.x - center.x, point.y - center.y) > 8 {
            mapCoordinate(point, in: app, mapFrame: snapshot.mapFrame).press(forDuration: 0.05,
                thenDragTo: mapCoordinate(center, in: app, mapFrame: snapshot.mapFrame),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return focus.identifier
    }

    private func blankMapCoordinate(in app: XCUIApplication, horizontalTravel: CGFloat = 0) -> XCUICoordinate? {
        guard let snapshot = try? liveSnapshot(in: app), let viewport = uncoveredViewport(snapshot) else { return nil }
        var points: [CGPoint] = []
        var rows = (1..<8).map { viewport.minY + viewport.height * CGFloat($0) / 8 }
        if horizontalTravel != 0 { rows.insert(viewport.minY + 24, at: 0) }
        for y in rows {
            for column in 1..<8 {
                let point = CGPoint(x: viewport.minX + viewport.width * CGFloat(column) / 8, y: y)
                let end = CGPoint(x: point.x + horizontalTravel, y: point.y)
                // Both drag directions must remain clear of annotation hit
                // targets, not merely begin at a blank point beside the grid.
                let corridor = CGRect(x: min(point.x, end.x), y: point.y,
                    width: max(1, abs(horizontalTravel)), height: 1).insetBy(dx: -12, dy: -12)
                if viewport.contains(corridor),
                   snapshot.pins.values.allSatisfy({ !$0.frame.intersects(corridor) }) {
                    points.append(point)
                }
            }
        }
        guard let point = points.min(by: {
            if horizontalTravel != 0, $0.y != $1.y { return $0.y < $1.y }
            return hypot($0.x - viewport.midX, $0.y - viewport.midY)
                < hypot($1.x - viewport.midX, $1.y - viewport.midY)
        }) else { return nil }
        return mapCoordinate(point, in: app, mapFrame: snapshot.mapFrame)
    }

    private func observeMapGeometry(in app: XCUIApplication, timeout: TimeInterval,
                                    condition: @escaping (LiveSnapshot) -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let snapshot = try? self.liveSnapshot(in: app) else { return false }
            return condition(snapshot)
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func settleMapGeometry(in app: XCUIApplication, anchorIDs: (String, String)) {
        var previous: [CGRect] = []
        var changedAt = ProcessInfo.processInfo.systemUptime
        let settled = observeMapGeometry(in: app, timeout: 10) { snapshot in
            guard let first = snapshot.pins[anchorIDs.0], let second = snapshot.pins[anchorIDs.1] else { return false }
            let frames = [first.frame, second.frame]
            if frames != previous {
                previous = frames
                changedAt = ProcessInfo.processInfo.systemUptime
                return false
            }
            return ProcessInfo.processInfo.systemUptime - changedAt >= 0.5
        }
        XCTAssertTrue(settled, "Native map geometry must settle before measuring gestures")
    }

    private func visibleAnchorIDs(in app: XCUIApplication) -> (String, String)? {
        guard let snapshot = try? liveSnapshot(in: app), let viewport = uncoveredViewport(snapshot) else { return nil }
        let visible = snapshot.pins.values.filter {
            $0.enabled && viewport.contains($0.frame) && viewport.contains($0.frame.offsetBy(dx: 40, dy: 0))
        }.sorted { $0.identifier < $1.identifier }
        var widest: (String, String)?
        var separation: CGFloat = 24
        for (index, first) in visible.enumerated() {
            for second in visible.dropFirst(index + 1) {
                let candidate = distance(first.frame, second.frame)
                if candidate > separation {
                    separation = candidate
                    widest = (first.identifier, second.identifier)
                }
            }
        }
        return widest
    }

    private func uncoveredViewport(_ snapshot: LiveSnapshot) -> CGRect? {
        guard !snapshot.mapFrame.isNull, !snapshot.drawFrame.isNull, !snapshot.drawerFrame.isNull else { return nil }
        let top = max(snapshot.mapFrame.minY + 24, snapshot.drawFrame.maxY + 24)
        let bottom = min(snapshot.mapFrame.maxY - 24, snapshot.drawerFrame.minY - 64)
        guard bottom > top, snapshot.mapFrame.width > 96 else { return nil }
        return CGRect(x: snapshot.mapFrame.minX + 48, y: top,
            width: snapshot.mapFrame.width - 96, height: bottom - top)
    }

    private func mapCoordinate(_ point: CGPoint, in app: XCUIApplication, mapFrame: CGRect) -> XCUICoordinate {
        app.maps.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - mapFrame.minX, dy: point.y - mapFrame.minY))
    }

    private func recordSelectionGeometry(in app: XCUIApplication, round: Int, focusID: String) {
        guard let snapshot = try? liveSnapshot(in: app) else { return }
        let visible = snapshot.pins.values.filter { snapshot.mapFrame.intersects($0.frame) }
        let categories = visible.filter { $0.value == "Category pin" }.count
        let frame = snapshot.pins[focusID]?.frame ?? .null
        record("selection_zoom round=\(round) visible=\(visible.count) category=\(categories) map=\(snapshot.mapFrame) draw=\(snapshot.drawFrame) drawer=\(snapshot.drawerFrame) focus=\(focusID) frame=\(frame)")
    }

    private struct PinSnapshot {
        let identifier: String
        let frame: CGRect
        let label: String
        let value: String
        let enabled: Bool
    }

    private struct LiveSnapshot {
        var pins: [String: PinSnapshot] = [:]
        var mapFrame = CGRect.null
        var cameraDistanceMeters: Double?
        var firstPinRawValue = ""
        var drawFrame = CGRect.null
        var drawerFrame = CGRect.null
        var drawerValue = ""
        var liveSelected = false
    }

    private func liveSnapshot(in app: XCUIApplication) throws -> LiveSnapshot {
        let root = try app.snapshot()
        var result = LiveSnapshot()
        func visit(_ node: XCUIElementSnapshot) {
            if node.elementType == .map, result.mapFrame.isNull, !node.frame.isEmpty {
                result.mapFrame = node.frame
            }
            if node.identifier == "live.draw" { result.drawFrame = node.frame }
            if node.identifier == "live.drawerHandle" {
                result.drawerFrame = node.frame
                if let value = node.value as? String, !value.isEmpty { result.drawerValue = value }
            }
            if node.elementType == .button, node.label == "Live", node.isSelected {
                result.liveSelected = true
            }
            if node.elementType == .button, node.identifier.hasPrefix("live.pin.perf_place_server_"),
               !node.frame.isEmpty, result.pins[node.identifier] == nil {
                let rawValue = node.value as? String ?? ""
                if result.firstPinRawValue.isEmpty { result.firstPinRawValue = rawValue }
                let parts = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let prefix = "live.performance.cameraDistanceMeters="
                if result.cameraDistanceMeters == nil, parts.count == 2, parts[1].hasPrefix(prefix) {
                    result.cameraDistanceMeters = Double(parts[1].dropFirst(prefix.count))
                }
                result.pins[node.identifier] = PinSnapshot(identifier: node.identifier, frame: node.frame,
                    label: node.label, value: parts.first.map(String.init) ?? "", enabled: node.isEnabled)
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        return result
    }

    private func drawer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["live.drawerHandle"].firstMatch
    }

    private func expandDrawer(in app: XCUIApplication) {
        let handle = drawer(in: app)
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.08)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        waitForDetent("expanded", in: app)
    }

    private func collapseDrawer(in app: XCUIApplication) {
        let handle = drawer(in: app)
        guard !handle.label.contains(", collapsed") else { return }
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.15)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.88)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        waitForDetent("collapsed", in: app)
    }

    private func waitForDetent(_ detent: String, in app: XCUIApplication) {
        waitFor("Drawer settles at \(detent)", timeout: 20) {
            self.drawer(in: app).label == "Activity drawer, \(detent)"
        }
    }

    private func loadedFeedCount(_ scroll: XCUIElement) -> Int {
        Int((scroll.value as? String ?? "").split(separator: " ").first ?? "") ?? 0
    }

    private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }

    private func settle(_ element: XCUIElement) {
        var previous = CGRect.null
        var changedAt = Date.now
        waitFor("Pin stops moving before selection", timeout: 20) {
            guard element.exists, element.isHittable else { return false }
            if element.frame != previous { previous = element.frame; changedAt = .now; return false }
            return Date.now.timeIntervalSince(changedAt) >= 0.5
        }
    }

    private func wait(_ element: XCUIElement, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element.identifier)")
    }

    private func waitFor(_ message: String, timeout: TimeInterval, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func record(_ message: String) {
        let report = "REC675_LIVE_UI \(message)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
