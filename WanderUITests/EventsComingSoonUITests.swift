import XCTest
import UIKit

@MainActor final class EventsComingSoonUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLightTabBarStaysLightAcrossEventsVisits() throws {
        try verifyTabBarAppearance(isLight: true)
    }

    func testDarkTabBarStaysDarkAcrossEventsVisits() throws {
        try verifyTabBarAppearance(isLight: false)
    }

    func testTabGlassSurvivesScrubbingAndLiveAppearanceChanges() throws {
        let previous = XCUIDevice.shared.appearance
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = previous }
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "map"]
        app.launch()
        XCTAssertTrue(app.textFields["map.searchField"].waitForExistence(timeout: 20))
        let tabs = app.tabBars.firstMatch
        for destination in ["Events", "Map", "Profile", "Events", "Feed", "Map", "Events"] {
            let source = tabs.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch
            source.press(forDuration: 0.4, thenDragTo: tabs.buttons[destination])
            XCTAssertTrue(tabs.buttons[destination].isSelected)
            capture("Scrub — \(destination)")
            let pixels = try pixelStats(tabs.screenshot().image)
            XCTAssertGreaterThan(pixels.luminance, 0.55, "Light glass became dark after scrubbing to \(destination).")
        }
        for appearance in [XCUIDevice.Appearance.dark, .light, .dark, .light] {
            XCUIDevice.shared.appearance = appearance
            // The OS animates its appearance change; this wait is only for that
            // system transition, never for a tab selection.
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let pixels = try? self.pixelStats(tabs.screenshot().image) else { return false }
                return appearance == .light ? pixels.luminance > 0.55 : pixels.luminance < 0.45
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
            capture("Live appearance — \(appearance)")
        }
    }

    func testKeepMePostedIsTappableAndKeepsItsSelectionAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "events"]
        app.launch()
        let button = app.buttons["events.keepMePosted"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        XCTAssertLessThan(button.frame.maxY, tabs.frame.minY)
        XCTAssertEqual(button.label, "Keep me posted")
        capture("Events CTA — orange")
        button.tap()
        let confirmed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 5), .completed)
        XCTAssertEqual(button.label, "Added to waitlist")
        capture("Events CTA — white")
        tabs.buttons["Map"].tap()
        tabs.buttons["Events"].tap()
        XCTAssertTrue(button.isSelected)
        XCTAssertEqual(button.label, "Added to waitlist")
        XCTAssertTrue(button.isHittable)
    }

    private func verifyTabBarAppearance(isLight: Bool) throws {
        let previousAppearance = XCUIDevice.shared.appearance
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.appearance = previousAppearance
        }
        XCUIDevice.shared.appearance = isLight ? .light : .dark
        XCTAssertEqual(XCUIDevice.shared.appearance, isLight ? .light : .dark)
        let mode = isLight ? "Light" : "Dark"
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "map"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        XCTAssertTrue(app.textFields["map.searchField"].waitForExistence(timeout: 20))
        // Accessibility can expose tabs while the launch image is still on
        // screen. Establish the initial rendered appearance before measuring
        // transitions; subsequent switches must pass without this wait.
        let initialAppearance = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let pixels = try? self.pixelStats(tabs.screenshot().image) else { return false }
            return isLight ? pixels.luminance > 0.55 : pixels.luminance < 0.45
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [initialAppearance], timeout: 5), .completed)
        capture("\(mode) — Map before Events")
        for (index, label) in ["Map", "Events", "Feed", "Events", "Lists", "Events", "Profile", "Events", "Map"].enumerated() {
            tabs.buttons[label].tap()
            XCTAssertTrue(tabs.buttons[label].isSelected)
            XCTAssertEqual(tabs.identifier, "main.tabBar")
            if label == "Events" {
                let artwork = app.descendants(matching: .any)["events.comingSoon"].firstMatch
                XCTAssertGreaterThanOrEqual(artwork.frame.maxY, app.windows.firstMatch.frame.maxY - 1,
                                           "Events artwork must continue behind the floating bar without a footer.")
            }
            if index == 1 { capture("\(mode) — Events") }
            if index == 8 { capture("\(mode) — Map after Events") }
            let barPixels = try pixelStats(tabs.screenshot().image)
            let luminance = barPixels.luminance
            XCTAssertGreaterThan(barPixels.signalPixels, 30, "The selected tab must keep the coral accent on \(label), step \(index).")
            let inactive = tabs.buttons[label == "Map" ? "Feed" : "Map"]
            let inactivePixels = try pixelStats(inactive.screenshot().image)
            if isLight {
                XCTAssertGreaterThan(inactivePixels.darkPixels, 30, "Inactive tab ink must contrast with the light bar.")
            } else {
                XCTAssertGreaterThan(inactivePixels.lightPixels, 30, "Inactive tab ink must contrast with the dark bar.")
            }
            if isLight {
                XCTAssertGreaterThan(luminance, 0.55, "Light bar became dark on \(label), step \(index).")
            } else {
                XCTAssertLessThan(luminance, 0.45, "Dark bar became light on \(label), step \(index).")
            }
        }
    }

    /// Measure the visible native bar, not a SwiftUI environment value. Cropping
    /// its interior excludes transparent rounded corners and the outer shadow.
    private func pixelStats(_ image: UIImage) throws -> (luminance: Double, signalPixels: Int, darkPixels: Int, lightPixels: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var total = 0.0, count = 0, signalPixels = 0, darkPixels = 0, lightPixels = 0
        for y in (height / 5)..<(height * 4 / 5) {
            for x in (width / 10)..<(width * 9 / 10) {
                let offset = (y * width + x) * 4
                let red = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + 2]) / 255
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                total += luminance
                if red > 0.5 && red > green * 1.3 && red > blue * 1.3 { signalPixels += 1 }
                if luminance < 0.25 { darkPixels += 1 }
                if luminance > 0.8 { lightPixels += 1 }
                count += 1
            }
        }
        return (total / Double(count), signalPixels, darkPixels, lightPixels)
    }

    func testEventsIsMiddleNativeTabAndRepeatedSwitchesPreserveNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "events"]
        app.launch()
        let artwork = app.descendants(matching: .any)["events.comingSoon"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 20))
        let tabs = app.tabBars.firstMatch
        for label in ["Map", "Feed", "Events", "Lists", "Profile"] {
            XCTAssertTrue(tabs.buttons[label].isHittable)
        }
        XCTAssertLessThan(tabs.buttons["Feed"].frame.midX, tabs.buttons["Events"].frame.midX)
        XCTAssertLessThan(tabs.buttons["Events"].frame.midX, tabs.buttons["Lists"].frame.midX)
        capture("Events — native tab bar")
        for label in ["Map", "Feed", "Lists", "Profile", "Map", "Profile", "Feed", "Lists"] {
            tabs.buttons[label].tap()
            XCTAssertTrue(tabs.buttons[label].isSelected)
            if label == "Profile" {
                capture("Events — unselected beside Profile")
            }
            tabs.buttons["Events"].tap()
            XCTAssertTrue(tabs.buttons["Events"].isSelected)
            XCTAssertTrue(artwork.waitForExistence(timeout: 2))
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        capture("Events — after switching and foreground return")
    }

    func testTabBarHidesAndReturnsWithProfileNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        preview.tap()
        XCTAssertTrue(app.buttons["yourMap.snapshot"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("Tab bar hidden — Your Map")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Profile"].isSelected)
        capture("Tab bar restored — Profile")
    }

    func testTabSwitchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                               "-WanderDisableWalkthroughs", "-WanderInitialTab", "events"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["events.comingSoon"].firstMatch.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.tabBars.buttons["Profile"].tap()
            app.tabBars.buttons["Events"].tap()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
