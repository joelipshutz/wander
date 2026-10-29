import XCTest
import UIKit

/// Real app/MapKit interaction captures with fictional, memory-only content.
@MainActor
final class LiveTotemUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCountryAliasHasOneSavedMarkerThroughSelectionAndZoom() {
        let app = launch()
        collapseDrawer(app)
        let pin = app.buttons["live.pin.totem_tacos"]
        wait(pin)
        settle(pin)
        func assertOneSavedMarker() {
            let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin.totem_tacos"))
            XCTAssertEqual(matches.count, 1, "One venue must never render both a pin and a dense dot.")
            XCTAssertTrue(pin.label.contains("You, Wanna"))
            XCTAssertFalse(pin.label.contains("Featured"))
        }
        assertOneSavedMarker()
        pin.tap()
        wait(app.buttons["live.placePreview.close"])
        settle(pin)
        assertOneSavedMarker()
        capture("REC666-one-saved-marker-selected")
        app.buttons["live.placePreview.close"].tap()
        wait(pin)
        settle(pin)
        let map = app.descendants(matching: .any).matching(identifier: "live.map").firstMatch
        map.pinch(withScale: 0.6, velocity: -1)
        wait(pin)
        settle(pin)
        assertOneSavedMarker()
        capture("REC666-one-saved-marker-dense")
        map.pinch(withScale: 1.8, velocity: 1)
        wait(pin)
        settle(pin)
        assertOneSavedMarker()
        capture("REC666-one-saved-marker-expanded")
    }

    func testTotemStatesFiltersAndPlaceNavigation() {
        let app = launch()
        capturePinStates(app)

        app.buttons["Filters"].tap()
        wait(app.buttons["live.filter.people"])
        app.buttons["live.filter.people"].tap()
        wait(app.buttons["live.filter.option.People.Only Friends"])
        capture("11-colored-people-options")
        app.buttons["live.filter.option.People.Only Friends"].tap()
        XCTAssertTrue(app.buttons["live.filter.option.People.Only Friends"].waitForNonExistence(timeout: 5))
        app.buttons["live.filter.scope"].tap()
        wait(app.buttons["live.filter.option.Scope.Featured"])
        capture("12-green-scope-option")
        app.buttons["live.filter.option.Scope.Featured"].tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        wait(app.buttons["live.pin.totem_noodles"])
        assertUniquePins(app)
        capture("12a-only-friends-map")
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Only Me"].tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        wait(app.buttons["live.pin.totem_coffee"])
        capture("12b-only-me-map")
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Everyone"].tap()
        app.buttons["live.filter.activity"].tap()
        let listsOption = visibleButton("Lists", in: app)
        capture("13-lists-activity-option")
        listsOption.tap()
        app.buttons["live.applyFilters"].tap()
        wait(app.buttons["live.pin.totem_list"])
        collapseDrawer(app)
        assertUniquePins(app)
        XCTAssertFalse(app.buttons["live.pin.totem_featured"].exists)
        capture("14-lists-filter-map")
        settle(app.buttons["live.pin.totem_list"])
        app.buttons["live.pin.totem_list"].tap()
        wait(app.buttons["live.placePreview.close"])
        capture("15-list-addition-preview")
        app.buttons["live.placePreview.close"].tap()

        app.buttons["Filters"].tap()
        app.buttons["live.filter.activity"].tap()
        visibleButton("All", in: app).tap()
        app.buttons["live.filter.time"].tap()
        visibleButton("Past 24 hours", in: app).tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        let coffee = app.buttons["live.pin.totem_coffee"]
        wait(coffee)
        settle(coffee)
        XCTAssertTrue(coffee.label.contains("On a list"))
        coffee.tap()
        wait(app.buttons["live.placePreview.close"])
        capture("16-old-membership-recent-filter")
        app.buttons["live.placePreview.open"].tap()
        wait(app.buttons["place-profile.back"])
        capture("17-place-profile-navigation")
        app.buttons["place-profile.back"].tap()
        wait(app.buttons["live.draw"])
        assertUniquePins(app)
        capture("18-live-return")

        app.buttons["Filters"].tap()
        app.buttons["live.filter.time"].tap()
        visibleButton("All time", in: app).tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        let featured = app.buttons["live.pin.totem_featured"]
        wait(featured)
        settle(featured)
        XCTAssertTrue(featured.label.contains("Featured"))
        featured.tap()
        wait(app.buttons["live.placePreview.add"])
        app.buttons["live.placePreview.add"].tap()
        wait(app.buttons["save.submit"])
        app.scrollViews["save.editorScroll"].buttons["Wanna go"].tap()
        capture("19-save-featured-as-wanna")
        app.buttons["save.submit"].tap()
        XCTAssertTrue(app.buttons["save.submit"].waitForNonExistence(timeout: 15))
        let celebration = app.buttons["Got it"]
        if celebration.waitForExistence(timeout: 3) {
            wait(celebration)
            celebration.tap()
            XCTAssertTrue(celebration.waitForNonExistence(timeout: 5))
        }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            featured.exists && featured.label.contains("You, Wanna") && !featured.label.contains("Featured")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        wait(featured)
        settle(featured)
        assertUniquePins(app)
        capture("20-featured-becomes-wanna")
    }

    /// Focused native mockup pass for pin-only geometry refinements.
    func testRefinedTotemPinMockups() {
        capturePinStates(launch())
    }

    func testMixedSocialRailAndDenseBadgeMockups() {
        let app = launch()
        collapseDrawer(app)
        let featured = app.buttons["live.pin.totem_featured"]
        wait(featured)
        settle(featured)
        assertUniquePins(app)
        capture("21-dense-dots-without-badges")
        let mixed = app.buttons["live.pin.totem_mixed"]
        wait(mixed)
        settle(mixed)
        mixed.tap()
        wait(app.buttons["live.placePreview.close"])
        settle(mixed)
        capture("22-social-been-three-wanna-dots")
        assertUniquePins(app)
    }

    func testNativeZoomPreservesColorsInFullPinsAndDenseDots() throws {
        executionTimeAllowance = 300
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.appearance = previousAppearance }
        // The UIKit adapter exposes live.map on its container; MapKit's
        // native Map child is the gesture target and has no identifier.
        let map = app.maps.firstMatch
        wait(map)
        // Production map interaction collapses the drawer. A short pan keeps
        // this zoom regression independent of the drawer's own drag gesture.
        panMap(in: app, by: CGVector(dx: 40, dy: 0))
        let handle = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            handle.label.contains(", collapsed")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 10), .completed)
        let mixed = app.buttons["live.pin.totem_mixed"]
        let reference = app.buttons["live.pin.totem_bar"]
        XCTAssertTrue(mixed.waitForExistence(timeout: 10))
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        let label = mixed.label
        XCTAssertTrue(label.contains("You, Been"))
        XCTAssertTrue(label.contains("Social, Been and Wanna"))
        XCTAssertTrue(label.contains("On a list"))
        // No selection, filter commit, camera injection, or fixture density
        // override: only real native MapKit pans and pinches change the camera.
        for (stage, density, scale) in [
            ("01-full", "Category pin", CGFloat(1.6)),
            ("02-dense", "Map dot", CGFloat(0.8))
        ] {
            centerPin(mixed, reference: reference, in: app)
            zoom(map, in: app, target: mixed, reference: reference, to: density, scale: scale)
            centerPin(mixed, reference: reference, in: app)
            XCTAssertEqual(mixed.label, label, "Zoom must preserve the same pin's semantic evidence")
            XCTAssertEqual(mixed.value as? String, density)
            XCTAssertFalse(app.buttons["live.placePreview.close"].exists)
            assertUniquePins(app)
            let measured = try assertNativePinColors(stage, in: app, requiredPin: mixed)
            if stage == "01-full" {
                XCTAssertTrue(measured, "The full capture must directly verify both mixed-pin colors")
            }
        }
    }

    private func panMap(in app: XCUIApplication, by offset: CGVector, from point: CGPoint? = nil) {
        let viewport = zoomViewport(in: app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let point = point ?? CGPoint(x: viewport.midX - offset.dx / 2, y: viewport.midY - offset.dy / 2)
        let start = origin.withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset))
    }

    private func centerPin(_ pin: XCUIElement, reference: XCUIElement, in app: XCUIApplication) {
        // XCTest pinches can shift the camera as well as scale it. Recenter
        // with a native pan instead of injecting a camera position.
        for _ in 0..<3 {
            settleZoom(pin, reference: reference)
            let viewport = zoomViewport(in: app)
            let dx = viewport.midX - pin.frame.midX, dy = viewport.midY - pin.frame.midY
            if abs(dx) < 12 && abs(dy) < 12 { return }
            panMap(in: app, by: CGVector(dx: max(-viewport.width * 0.6, min(viewport.width * 0.6, dx)),
                                        dy: max(-viewport.height * 0.6, min(viewport.height * 0.6, dy))))
        }
        settleZoom(pin, reference: reference)
        XCTAssertTrue(zoomViewport(in: app).contains(pin.frame), "A native pan must bring the tracked pin into view")
    }

    private func zoom(_ map: XCUIElement, in app: XCUIApplication, target: XCUIElement,
                      reference: XCUIElement, to density: String, scale: CGFloat) {
        func separation() -> CGFloat {
            hypot(target.frame.midX - reference.frame.midX, target.frame.midY - reference.frame.midY)
        }
        var gestures = 0
        var observedScaleChange = false
        var samples: [String] = []
        defer {
            let diagnostic = XCTAttachment(string: samples.joined(separator: "\n"))
            diagnostic.name = "REC-669-native-zoom-to-\(density)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        for _ in 0..<10 {
            settleZoom(target, reference: reference)
            if target.value as? String == density {
                XCTAssertTrue(gestures == 0 || observedScaleChange,
                              "The native zoom must change annotation separation as well as density")
                return
            }
            let before = separation()
            XCTAssertGreaterThan(before, 1)
            let viewport = zoomViewport(in: app)
            XCTAssertTrue(viewport.contains(CGPoint(x: map.frame.midX, y: map.frame.midY)),
                          "The native pinch center must be in uncovered map content")
            map.pinch(withScale: scale, velocity: scale < 1 ? -1 : 1)
            gestures += 1
            settleZoom(target, reference: reference)
            let after = separation()
            observedScaleChange = observedScaleChange || (scale < 1 ? after < before * 0.95 : after > before * 1.05)
            samples.append("gesture=\(gestures); requestedScale=\(scale); separationBefore=\(before); separationAfter=\(after); density=\(target.value as? String ?? "missing")")
        }
        settleZoom(target, reference: reference)
        XCTAssertEqual(target.value as? String, density, "Ten native pinches must reach the requested density")
        XCTAssertTrue(observedScaleChange, "Native pinches must produce a measurable scale change")
    }

    private func settleZoom(_ target: XCUIElement, reference: XCUIElement) {
        var previous: [CGRect] = []
        var stableSince = Date.now
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard target.exists, reference.exists else { return false }
            let frames = [target.frame, reference.frame]
            guard frames.allSatisfy({ !$0.isEmpty && !$0.isInfinite && !$0.isNull }) else { return false }
            if frames != previous { previous = frames; stableSince = .now; return false }
            return Date.now.timeIntervalSince(stableSince) >= 0.8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed)
    }

    private func zoomViewport(in app: XCUIApplication) -> CGRect {
        let map = app.maps.firstMatch.frame.intersection(app.frame)
        let handle = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
        let top = max(map.minY, app.buttons["live.draw"].frame.maxY + 8)
        let bottom = min(map.maxY, handle.frame.minY - 8)
        return CGRect(x: map.minX, y: top, width: map.width, height: max(0, bottom - top))
    }

    private func assertNativePinColors(_ stage: String, in app: XCUIApplication,
                                       requiredPin: XCUIElement) throws -> Bool {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "REC-669-\(stage)-native-pinch"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let scaleX = CGFloat(image.width) / app.frame.width
        let scaleY = CGFloat(image.height) / app.frame.height
        let viewport = zoomViewport(in: app)
        XCTAssertTrue(viewport.contains(requiredPin.frame), "The tracked pin must be fully visible for pixel verification")
        let palette: [String: (Int, Int, Int)] = [
            "coral": (240, 90, 60), "blue": (105, 184, 215), "green": (111, 185, 133)
        ]
        let expected: [(String, [String])] = [
            ("mixed", ["coral", "blue"]), ("coffee", ["coral"]), ("tacos", ["coral"]),
            ("bar", ["blue"]), ("noodles", ["blue"]), ("featured", ["green"])
        ]
        var observations: [String] = []
        var verifiedColors = Set<String>()
        var verifiedMixedColors = false
        var failures: [String] = []
        let fullPins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex.filter { $0.value as? String == "Category pin" }
        let fullIDs = Set(fullPins.map(\.identifier))
        let fullColors = Set(expected.filter { fullIDs.contains("live.pin.totem_\($0.0)") }.flatMap { $0.1 })
        var directlyVerifiedDensePalette = false
        for (id, colors) in expected {
            let pin = app.buttons["live.pin.totem_\(id)"]
            guard pin.exists, viewport.contains(pin.frame) else { continue }
            let frame = pin.frame
            let density = pin.value as? String ?? "missing"
            let glyphFrame = density == "Map dot"
                ? CGRect(x: frame.midX - 6, y: frame.midY - 6, width: 12, height: 12) : frame
            // Only rendered footprints can obscure this sample. The 44pt
            // accessibility/tap bounds are deliberately not occlusion bounds.
            var possibleOccluders: [String] = []
            if density == "Map dot" {
                for other in fullPins where other.identifier != pin.identifier {
                    let otherFrame = other.frame
                    guard !otherFrame.isEmpty, !otherFrame.isNull, !otherFrame.isInfinite else { continue }
                    let tile = CGRect(x: otherFrame.midX - 14.5, y: otherFrame.midY - 20,
                                      width: 29, height: 40)
                    if glyphFrame.intersects(tile) {
                        possibleOccluders.append("\(other.identifier) tile=\(tile)")
                    }
                    if other.label.contains("On a list") {
                        let badge = CGRect(x: otherFrame.midX + 13.5 - 5.5,
                                           y: otherFrame.midY - 18 - 5.5, width: 11, height: 11)
                        if glyphFrame.intersects(badge) {
                            possibleOccluders.append("\(other.identifier) listBadge=\(badge)")
                        }
                    }
                }
            }
            let rect = CGRect(x: (glyphFrame.minX - app.frame.minX) * scaleX,
                              y: (glyphFrame.minY - app.frame.minY) * scaleY,
                              width: glyphFrame.width * scaleX, height: glyphFrame.height * scaleY).integral
            let crop = try XCTUnwrap(image.cropping(to: rect))
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                    width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            var allColorsObserved = true
            for name in colors {
                let rgb = try XCTUnwrap(palette[name])
                var count = 0
                for offset in stride(from: 0, to: bytes.count, by: 4) {
                    let redMatches = abs(Int(bytes[offset]) - rgb.0) <= 22
                    let greenMatches = abs(Int(bytes[offset + 1]) - rgb.1) <= 22
                    let blueMatches = abs(Int(bytes[offset + 2]) - rgb.2) <= 22
                    if redMatches && greenMatches && blueMatches && bytes[offset + 3] >= 240 {
                        count += 1
                    }
                }
                let squarePoints = CGFloat(count) / (scaleX * scaleY)
                observations.append("pin=\(id); density=\(density); frame=\(frame); color=\(name); pixels=\(count); squarePoints=\(squarePoints)")
                if squarePoints >= 3 {
                    verifiedColors.insert(name)
                } else {
                    allColorsObserved = false
                    if possibleOccluders.isEmpty {
                        failures.append("\(id) lost \(name) in \(stage): \(count) matching pixels")
                    } else {
                        observations.append("unobservable color=\(name); pin=\(id); glyph=\(glyphFrame); overlappingDrawnFootprints=\(possibleOccluders.joined(separator: "; "))")
                    }
                }
            }
            if id == "mixed", allColorsObserved { verifiedMixedColors = true }
            // At least one complete dense palette must be proven by pixels
            // whose colors cannot have come from an overlapping full tile.
            if density == "Map dot", allColorsObserved,
               colors.allSatisfy({ !fullColors.contains($0) }) {
                directlyVerifiedDensePalette = true
            }
        }
        let diagnostic = XCTAttachment(string: observations.joined(separator: "\n"))
        diagnostic.name = "REC-669-\(stage)-native-pixel-counts"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertTrue(verifiedColors.isSuperset(of: ["coral", "blue", "green"]),
                      "Each zoom capture must include visible own, social, and Featured color evidence")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        if stage == "02-dense" {
            XCTAssertTrue(directlyVerifiedDensePalette, "Dense color evidence must come from a dot, not a full tile")
        }
        return verifiedMixedColors
    }

    private func capturePinStates(_ app: XCUIApplication) {
        capture("01-live-with-feed")
        // Use the map's normal interaction to reveal it. Drawer-header dragging
        // is a separate interaction; this flow exercises physical pin navigation.
        let handle = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
        settle(handle)
        let viewport = zoomViewport(in: app)
        let start = CGPoint(x: viewport.minX + 24, y: viewport.minY + 24)
        let gesturePath = CGRect(x: start.x, y: start.y - 8, width: 40, height: 16)
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
        XCTAssertFalse(pins.allElementsBoundByIndex.contains { $0.frame.intersects(gesturePath) },
                       "Navigation setup must pan empty map rather than drag an annotation")
        panMap(in: app, by: CGVector(dx: 40, dy: 0), from: start)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.descendants(matching: .any).matching(identifier: "live.drawerHandle")
                .firstMatch.label.contains(", collapsed")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 10), .completed)
        let mixed = app.buttons["live.pin.totem_mixed"]
        let reference = app.buttons["live.pin.totem_bar"]
        wait(mixed); wait(reference)
        // Start navigation at a readable zoom, using real gestures, so a
        // neighboring annotation's 44pt target cannot intercept a dense dot.
        centerPin(mixed, reference: reference, in: app)
        zoom(app.maps.firstMatch, in: app, target: mixed, reference: reference,
             to: "Category pin", scale: 1.6)
        centerPin(mixed, reference: reference, in: app)
        wait(app.buttons["live.pin.totem_featured"])
        settle(app.buttons["live.pin.totem_featured"])
        capture("02-all-states-map")
        assertUniquePins(app)

        for (id, placeName, name) in [("coffee", "Woodcat Coffee", "03-you-been-persistent-list"),
                           ("tacos", "Mariposa Tacos", "04-you-wanna-list"),
                           ("bar", "Bar Nido", "05-social-been"),
                           ("noodles", "Larchmont Noodles", "06-social-wanna"),
                           ("mixed", "Circuit Coffee", "07-mixed-one-place"),
                           ("list", "Echo Park Bookshop", "08-list-only"),
                           ("featured_list", "Silver Lake Garden", "09-list-over-featured"),
                           ("featured", "Sunday Studio", "10-featured-only")] {
            let pin = app.buttons["live.pin.totem_\(id)"]
            wait(pin)
            settle(pin)
            let originalFrame = pin.frame
            let originalReference = reference.frame
            pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            wait(app.buttons["live.placePreview.close"])
            XCTAssertEqual(app.buttons["live.placePreview.open"].label, "Open \(placeName)")
            capture(name)
            app.buttons["live.placePreview.close"].tap()
            XCTAssertTrue(app.buttons["live.placePreview.close"].waitForNonExistence(timeout: 5))
            collapseDrawer(app)
            settleZoom(pin, reference: reference)
            XCTAssertEqual(pin.frame.midX, originalFrame.midX, accuracy: 2,
                           "Closing a preview must restore the rotated map's original camera")
            XCTAssertEqual(pin.frame.midY, originalFrame.midY, accuracy: 2)
            XCTAssertEqual(reference.frame.midX, originalReference.midX, accuracy: 2)
            XCTAssertEqual(reference.frame.midY, originalReference.midY, accuracy: 2)
            assertUniquePins(app)
        }
    }

    func testWarmReturnsKeepSelectedPinAndFeedPosition() {
        let app = launch()
        collapseDrawer(app)
        let pin = app.buttons["live.pin.totem_coffee"]
        wait(pin); settle(pin)
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(app.buttons["live.placePreview.close"])
        capture("rec667-before-five-second-return")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        reactivate(app)
        wait(app.buttons["live.placePreview.close"], timeout: 5)
        XCTAssertTrue(app.buttons["live.placePreview.close"].exists, "A warm return must preserve the selected pin")
        capture("rec667-after-five-second-return")
        app.buttons["live.placePreview.close"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.15)))
        let scroll = app.scrollViews["feed.places.scroll"]
        wait(scroll)
        scroll.swipeUp()
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed.activity.' AND identifier ENDSWITH '.postcard'"))
        for seconds in [30.0, 120.0] {
            let anchor = cards.allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(anchor, "Expected a visible Feed card before backgrounding")
            guard let anchor else { return }
            let identifier = anchor.identifier, before = anchor.frame.minY
            capture("rec667-before-\(Int(seconds))-second-return")
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: seconds)
            reactivate(app)
            let restored = app.descendants(matching: .any)[identifier].firstMatch
            wait(restored, timeout: 5)
            capture("rec667-after-\(Int(seconds))-second-return")
            if !restored.exists {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "REC667 warm-return hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(restored.exists, "Warm return must retain the reader's card")
            XCTAssertEqual(restored.frame.minY, before, accuracy: 8, "Warm refresh must preserve Feed position")
        }
    }

    func testColdLaunchRestoresFilterAndDrawerBookmark() {
        let app = launch(restoration: true)
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Only Friends"].tap()
        app.buttons["live.applyFilters"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        wait(handle)
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.15)))
        let savedLabel = handle.label
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        let restoredHandle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        wait(restoredHandle, timeout: 30)
        XCTAssertEqual(restoredHandle.label, savedLabel)
        collapseDrawer(app)
        app.buttons["Filters"].tap()
        wait(app.buttons["live.filter.people"])
        XCTAssertEqual(app.buttons["live.filter.people"].value as? String, "Only Friends")
        capture("rec667-cold-restored-filters")
    }

    private func launch(restoration: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest",
            "-WanderLiveTotemUITest", "-WanderInitialTab", "discover",
            "-astir.live.viewedPins.user_joe", "",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if restoration { app.launchArguments.append("-WanderLiveRestorationUITest") }
        app.launch()
        if restoration {
            wait(app.descendants(matching: .any)["live.drawerHandle"].firstMatch, timeout: 30)
            collapseDrawer(app)
        }
        wait(app.buttons["live.draw"], timeout: 30)
        if app.buttons["live.introduction.notNow"].exists {
            app.buttons["live.introduction.notNow"].tap()
        }
        return app
    }

    private func reactivate(_ app: XCUIApplication) {
        app.activate()
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningForeground
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 5), .completed,
                       "Warm-return assertions require the app to actually be foregrounded")
    }

    private func wait(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists { capture("diagnostic-missing-element") }
        XCTAssertTrue(exists)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.isHittable }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        if result != .completed { capture("diagnostic-unhittable-element") }
        XCTAssertEqual(result, .completed)
    }

    private func collapseDrawer(_ app: XCUIApplication) {
        let handle = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
        guard handle.exists, !handle.label.contains(", collapsed") else { return }
        wait(handle)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
            return current.exists && current.label.contains(", collapsed")
        }, object: nil)
        let result = XCTWaiter.wait(for: [collapsed], timeout: 10)
        if result != .completed { capture("diagnostic-drawer-drag") }
        XCTAssertEqual(result, .completed)
    }

    private func visibleButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // Native Picker menus use collection cells. Scope to their buttons so
        // the Lists tab and transient menu containers cannot shift the match.
        let option = app.collectionViews.cells.buttons.matching(
            NSPredicate(format: "label == %@", title)).firstMatch
        wait(option)
        return option
    }

    /// MapKit restores the camera after a card closes. Hittability can become
    /// true while an annotation is still moving, so wait for stable geometry.
    private func settle(_ element: XCUIElement) {
        var previous = CGRect.null
        var changedAt = Date.now
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            if frame != previous { previous = frame; changedAt = .now; return false }
            return Date.now.timeIntervalSince(changedAt) >= 0.8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed)
    }

    private func assertUniquePins(_ app: XCUIApplication) {
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex
        let identifiers = pins.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertLessThanOrEqual(identifiers.filter { $0.contains("totem_mixed") }.count, 1)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-657-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
