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
        for _ in 0..<6 {
            if appearancePage.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(appearancePage.isHittable)
        appearancePage.tap()
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
        let pin = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Dudley Market QA")
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
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
