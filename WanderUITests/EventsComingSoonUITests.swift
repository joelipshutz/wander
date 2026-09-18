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
            let luminance = try tabBarLuminance(tabs.screenshot().image)
            if isLight {
                XCTAssertGreaterThan(luminance, 0.55, "Light bar became dark on \(label), step \(index).")
            } else {
                XCTAssertLessThan(luminance, 0.45, "Dark bar became light on \(label), step \(index).")
            }
        }
    }

    /// Measure the visible native bar, not a SwiftUI environment value. Cropping
    /// its interior excludes transparent rounded corners and the outer shadow.
    private func tabBarLuminance(_ image: UIImage) throws -> Double {
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
        var total = 0.0, count = 0
        for y in (height / 5)..<(height * 4 / 5) {
            for x in (width / 10)..<(width * 9 / 10) {
                let offset = (y * width + x) * 4
                total += (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])) / 255
                count += 1
            }
        }
        return total / Double(count)
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
