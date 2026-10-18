import UIKit
import XCTest

@MainActor
final class PlaceProfileAppearanceUITests: XCTestCase {
    func testPrimaryScreensAndPresentedSurfacesSurviveAppearanceChanges() throws {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        // Use the fixture root so account notification primers cannot cover
        // the screens whose appearance is under test.
        app.launchArguments = ["-WanderMapCapture", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "map"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: tabs.buttons["Map"])
        capture("Map startup")
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)

        for name in ["Map", "Feed", "Lists", "Events", "Profile"] {
            tabs.buttons[name].tap()
            for appearance in [XCUIDevice.Appearance.light, .dark] {
                XCUIDevice.shared.appearance = appearance
                waitForAppearanceTransition(to: appearance)
                capture("\(name) live appearance \(appearance)")
                XCTAssertTrue(tabs.buttons[name].isSelected)
                XCTAssertTrue(tabs.buttons[name].isHittable)
                // Events intentionally uses a black video background, which
                // affects the native translucent tab bar in both appearances.
                if name != "Events" { try assertAppearance(of: tabs, expected: appearance) }
            }
        }

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            waitForAppearanceTransition(to: appearance)
            XCTAssertTrue(back.isHittable)
            capture("Settings live appearance \(appearance)")
        }
        back.tap()
        tabs.buttons["Feed"].tap()
        let add = app.buttons["feed.headerAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let locationDenial = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Don’t Allow"]
        if locationDenial.waitForExistence(timeout: 3) { locationDenial.tap() }
        let search = app.textFields["add.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            waitForAppearanceTransition(to: appearance)
            XCTAssertTrue(search.isHittable)
            capture("Add live appearance \(appearance)")
        }
    }

    func testOpenHistorySurvivesLiveAppearanceChangesAndForegroundReturns() throws {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        XCUIDevice.shared.appearance = .dark

        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderREC386PhotoFixture",
            "-WanderMapPlace", "Dudley Market QA", "-WanderMapSheetExpanded"
        ]
        app.launch()
        let scroll = app.scrollViews["place-profile.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let note = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA proof: Ryan's uploaded check-in photo")
        ).firstMatch
        for _ in 0..<8 {
            if note.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(note.isHittable)
        let originalY = note.frame.minY
        capture("History initially dark")
        try assertAppearance(of: note, expected: .dark)

        for (index, appearance) in [XCUIDevice.Appearance.light, .dark, .light].enumerated() {
            XCUIDevice.shared.appearance = appearance
            // Wait for the OS appearance animation before measuring the same
            // scroll position and recording the rendered history card.
            waitForAppearanceTransition(to: appearance)
            XCTAssertTrue(note.isHittable)
            XCTAssertEqual(note.frame.minY, originalY, accuracy: 4)
            XCTAssertFalse(app.buttons["History could not refresh. Tap to retry."].exists)
            capture("History appearance transition \(index)")
            try assertAppearance(of: note, expected: appearance)
        }

        for (index, appearance) in [XCUIDevice.Appearance.dark, .light, .dark].enumerated() {
            XCUIDevice.shared.press(.home)
            XCUIDevice.shared.appearance = appearance
            app.activate()
            waitForAppearanceTransition(to: appearance)
            reopenHistoryAfterOrdinaryForegroundReturn(in: app)
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            XCTAssertTrue(note.isHittable)
            XCTAssertFalse(app.buttons["History could not refresh. Tap to retry."].exists)
            capture("History foreground return \(index)")
            try assertAppearance(of: note, expected: appearance)
        }
        XCTAssertTrue(app.buttons["place-profile.back"].isHittable)
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 5))
    }

    func testHistorySurvivesSettingsAppearanceChanges() throws {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.appearance
        // Drive this path through the actual Settings UI, separately from
        // the direct XCUIDevice appearance coverage above.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        defer {
            // Close Settings before restoring appearance for later tests.
            settings.terminate()
            XCUIDevice.shared.appearance = previous
        }
        settings.launch()
        #if targetEnvironment(simulator)
        // Simulator exposes the real system appearance switch under Developer;
        // it does not include the device's Display & Brightness settings page.
        let appearancePage = settings.buttons["Developer"]
        #else
        let appearancePage = settings.buttons["Display & Brightness"]
        #endif
        var admittedPageFrames: (row: CGRect, application: CGRect)?
        func pageControlIsVisible() -> Bool {
            admittedPageFrames = nil
            guard appearancePage.isHittable else { return false }
            let applicationFrame = settings.frame
            let rowFrame = appearancePage.frame
            var bottom = applicationFrame.maxY
            var hasChromeFrame = false
            // The Search settings row is content, not the floating SearchField.
            for chrome in [settings.toolbars.firstMatch,
                           settings.searchFields.firstMatch] where chrome.exists {
                let frame = chrome.frame
                if frame.width > 0, frame.height > 0, frame.intersects(applicationFrame) {
                    bottom = min(bottom, frame.minY)
                    hasChromeFrame = true
                }
            }
            // Collapsed search may omit native chrome frames; keep the whole
            // row above its recorded bottom area instead of tapping through it.
            if !hasChromeFrame { bottom -= 100 }
            guard rowFrame.width > 0, rowFrame.height > 0,
                  applicationFrame.contains(rowFrame),
                  rowFrame.minY >= settings.navigationBars.firstMatch.frame.maxY,
                  rowFrame.maxY < bottom,
                  appearancePage.frame == rowFrame,
                  settings.frame == applicationFrame else { return false }
            admittedPageFrames = (rowFrame, applicationFrame)
            return true
        }
        for _ in 0..<6 {
            if pageControlIsVisible() { break }
            settings.swipeUp()
        }
        XCTAssertTrue(pageControlIsVisible())
        let admittedFrames = try XCTUnwrap(admittedPageFrames)
        settings.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: admittedFrames.row.midX - admittedFrames.application.minX,
            dy: admittedFrames.row.midY - admittedFrames.application.minY
        )).tap()
        try changeAppearanceInSettings(settings, to: .dark)
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderREC386PhotoFixture",
            "-WanderMapPlace", "Dudley Market QA", "-WanderMapSheetExpanded"
        ]
        app.launch()
        let scroll = app.scrollViews["place-profile.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let note = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA proof: Ryan's uploaded check-in photo")
        ).firstMatch
        for _ in 0..<8 {
            if note.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(note.isHittable)
        try assertAppearance(of: note, expected: .dark)

        for appearance in [XCUIDevice.Appearance.light, .dark] {
            settings.activate()
            try changeAppearanceInSettings(settings, to: appearance)
            capture("Settings changed appearance \(appearance)")
            app.activate()
            waitForAppearanceTransition(to: appearance)
            reopenHistoryAfterOrdinaryForegroundReturn(in: app)
            XCTAssertTrue(note.isHittable)
            XCTAssertFalse(app.buttons["History could not refresh. Tap to retry."].exists)
            capture("History after Settings \(appearance)")
            try assertAppearance(of: note, expected: appearance)
        }
        app.activate()
        XCTAssertTrue(app.buttons["place-profile.back"].isHittable)
    }

    private func reopenHistoryAfterOrdinaryForegroundReturn(in app: XCUIApplication) {
        // REC-629 intentionally returns ordinary background entries to Feed.
        // Reopen the same place to verify its history and appearance; live
        // changes above still assert the mounted profile's scroll position.
        let feed = app.tabBars.buttons["Feed"]
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: feed)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        app.tabBars.buttons["Map"].tap()
        let card = app.buttons["map.selectedPlaceCard"]
        // The map retains its selected place across the ordinary Feed return.
        // Its card also includes the place name, so a broad name query can tap
        // that card as if it were a pin, then tap through the opened profile.
        if !card.exists {
            let pin = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@ AND identifier != %@",
                "Dudley Market QA", "map.selectedPlaceCard"
            )).firstMatch
            XCTAssertTrue(pin.waitForExistence(timeout: 5))
            pin.tap()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Dudley Market QA"))
        card.tap()
        let scroll = app.scrollViews["place-profile.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let note = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA proof: Ryan's uploaded check-in photo")
        ).firstMatch
        for _ in 0..<8 {
            if note.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(note.isHittable)
    }

    private func changeAppearanceInSettings(_ settings: XCUIApplication,
                                            to appearance: XCUIDevice.Appearance) throws {
        #if targetEnvironment(simulator)
        let choice = settings.switches["UIAppearanceSettings"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.navigationBars["Developer"].exists,
                      "Settings must open Developer before changing appearance.")
        let expectedValue = appearance == .dark ? "1" : "0"
        if choice.value as? String != expectedValue {
            // Hit the switch itself, rather than the combined cell label.
            choice.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedValue), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 5), .completed)
        #else
        let choice = settings.buttons[appearance == .light ? "Light" : "Dark"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        #endif
    }

    /// Measure actual rendered card/tab backgrounds so a stale surface fails
    /// even when its controls remain hittable.
    private func assertAppearance(of element: XCUIElement, expected: XCUIDevice.Appearance,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(XCUIDevice.shared.appearance, expected, file: file, line: line)
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 64 * 8 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 64, height: 8,
                bitsPerComponent: 8, bytesPerRow: 64 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 8))
        }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255.0
            let green = Double(pixels[index + 1]) / 255.0
            let blue = Double(pixels[index + 2]) / 255.0
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        let luminance = total / 512.0
        if expected == .light {
            XCTAssertGreaterThan(luminance, 0.6, "Light appearance retained a dark surface.", file: file, line: line)
        } else {
            XCTAssertLessThan(luminance, 0.45, "Dark appearance retained a light surface.", file: file, line: line)
        }
    }

    private func waitForAppearanceTransition(to appearance: XCUIDevice.Appearance) {
        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in XCUIDevice.shared.appearance == appearance },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 5), .completed)
        let settled = expectation(description: "System appearance transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Diagnostic only: original appearance methods above are byte-for-byte unchanged.
@MainActor
final class ProfileBlurLifecycleDiagnosticUITests: XCTestCase {
    func testLightActualBackdropFinishAtCurrentPreservesRenderedQuarterBlur() throws {
        try check(.light, argument: "light")
    }
    func testDarkActualBackdropFinishAtCurrentPreservesRenderedQuarterBlur() throws {
        try check(.dark, argument: "dark")
    }

    private func check(_ appearance: XCUIDevice.Appearance, argument: String) throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "map",
                               "-WanderProfileBlurLifecycleComponent", argument]
        app.launch()
        defer { app.terminate() }
        let probe = app.staticTexts["profile.blur.lifecycle.state"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        let before = try observation(probe, name: "\(argument) before lifecycle")
        try assertState(before, key: "reference", state: 1)
        try assertState(before, key: "immediateBefore", state: 1)
        try assertState(before, key: "immediateAfter", state: 0)
        XCTAssertEqual((before["immediate"] as? [String: Any])?["retained"] as? Bool, false)
        let viewportWidth = CGFloat(try XCTUnwrap(before["viewportWidth"] as? Double))
        let viewportHeight = CGFloat(try XCTUnwrap(before["viewportHeight"] as? Double))
        let beforeImage = capture("\(argument) before finishing retained quarter blur")
        let beforePanels = try panels(beforeImage, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        app.buttons["profile.blur.lifecycle.finish"].tap()
        let after = try observation(probe, name: "\(argument) after lifecycle")
        XCTAssertEqual(after["finished"] as? Bool, true)
        try assertState(after, key: "referenceBefore", state: 1)
        try assertState(after, key: "referenceAfter", state: 0)
        XCTAssertEqual((after["reference"] as? [String: Any])?["retained"] as? Bool, false)
        let afterPanels = try panels(capture("\(argument) after finishing retained quarter blur"),
                                     viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        // Fail closed if the OS screenshot did not contain an actual composited blur.
        XCTAssertGreaterThan(standardDeviation(beforePanels[0]), 0.12, "Raw fixture must be non-flat.")
        XCTAssertGreaterThan(standardDeviation(beforePanels[1]), 0.02, "Quarter blur must remain non-flat.")
        XCTAssertGreaterThan(meanDifference(beforePanels[0], beforePanels[1]), 0.01,
                             "Quarter blur must differ from the unblurred pattern.")
        XCTAssertGreaterThan(meanDifference(beforePanels[3], beforePanels[1]), 0.005,
                             "Quarter blur must differ from the full material.")
        assertEquivalent(beforePanels[1], beforePanels[2], "Immediate finish versus original quarter blur")
        assertEquivalent(beforePanels[0], afterPanels[0], "Raw display control stability")
        assertEquivalent(beforePanels[1], afterPanels[1], "Same rendered instance before versus after finish")
        assertEquivalent(beforePanels[2], afterPanels[2], "Immediate finish display stability")
        assertEquivalent(afterPanels[1], afterPanels[2], "Both finished quarter-blur instances")
    }

    private func observation(_ probe: XCUIElement, name: String) throws -> [String: Any] {
        let text = try XCTUnwrap(probe.value as? String) // Direct AX value; no snapshot truncation.
        let data = Data(text.utf8)
        XCTAssertLessThanOrEqual(data.count, 4096)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema"] as? Int, 1)
        XCTAssertEqual(object["fixture"] as? String, "profile-blur")
        XCTAssertEqual(object["ready"] as? Bool, true)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return object
    }
    private func assertState(_ object: [String: Any], key: String, state: Int) throws {
        let value = try XCTUnwrap(object[key] as? [String: Any])
        XCTAssertEqual(value["state"] as? Int, state)
        XCTAssertEqual(value["running"] as? Bool, false)
        XCTAssertEqual(value["windowAttached"] as? Bool, true)
        if state == 1 { XCTAssertEqual(try XCTUnwrap(value["fraction"] as? Double), 0.25, accuracy: 0.000001) }
    }
    private func capture(_ name: String) -> UIImage {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return screenshot.image
    }
    private func panels(_ image: UIImage, viewportWidth: CGFloat, viewportHeight: CGFloat) throws -> [[Double]] {
        let full = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(image.imageOrientation, .up)
        XCTAssertGreaterThan(viewportHeight, viewportWidth)
        let scale = CGFloat(full.width) / viewportWidth
        XCTAssertEqual(CGFloat(full.height) / viewportHeight, scale, accuracy: 0.001)
        return try (0..<4).map { index in
            // Interior crops exclude panel boundary effects; the source pattern has identical local phase.
            let rect = CGRect(x: 40, y: CGFloat(116 + index * 108), width: viewportWidth - 80, height: 56)
                .applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            let crop = try XCTUnwrap(full.cropping(to: rect))
            let width = crop.width, height = crop.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            try rgba.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
            return stride(from: 0, to: rgba.count, by: 4).flatMap { index in
                [Double(rgba[index]) / 255, Double(rgba[index + 1]) / 255, Double(rgba[index + 2]) / 255]
            }
        }
    }
    private func meanDifference(_ a: [Double], _ b: [Double]) -> Double {
        precondition(a.count == b.count && !a.isEmpty)
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
    }
    private func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count))
    }
    private func assertEquivalent(_ a: [Double], _ b: [Double], _ name: String) {
        XCTAssertEqual(a.count, b.count)
        let errors = zip(a, b).map { abs($0.0 - $0.1) }.sorted()
        let mean = meanDifference(a, b), p95 = errors[errors.count * 95 / 100]
        let metric = "{\"meanAbsoluteRGBError\":\(mean),\"p95AbsoluteRGBError\":\(p95)}"
        let attachment = XCTAttachment(data: Data(metric.utf8), uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertLessThanOrEqual(mean, 1.0 / 255, name)
        XCTAssertLessThanOrEqual(p95, 2.0 / 255, name)
    }
}
