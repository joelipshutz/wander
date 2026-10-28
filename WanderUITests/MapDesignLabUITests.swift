import XCTest

@MainActor
final class MapDesignLabUITests: XCTestCase {
    func testEveryPinFamilyKeepsPhysicalSelectionAndPlaceNavigation() {
        for style in ["porcelain", "signal", "bookmark", "ticket", "compass"] {
            verifyMap(pin: style, map: "quiet")
        }
    }

    func testSecondPassPinFamiliesKeepPhysicalSelectionAndPlaceNavigation() {
        for style in ["cutout", "wayfinder", "letterpress", "totem", "contour"] {
            verifyMap(pin: style, map: "quiet")
        }
    }

    func testEveryMapTreatmentKeepsPhysicalSelectionAndPlaceNavigation() {
        for style in ["quiet", "atlas", "night", "dimension", "hybrid"] {
            verifyMap(pin: "porcelain", map: style)
        }
    }

    private func verifyMap(pin style: String, map mapStyle: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderPinDesign", style, "-WanderMapDesign", mapStyle
        ]
        if mapStyle == "night" { app.launchArguments.append("-WanderDarkMap") }
        app.launch()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 12), "\(style)/\(mapStyle)")
        let pin = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Canyon Lookout Trail,")
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 12), "\(style)/\(mapStyle)")
        let point = CGPoint(x: pin.frame.midX, y: pin.frame.midY)
        XCTAssertTrue(map.frame.contains(point))
        // Physical coordinate tap exercises the map observer, not accessibilityActivate().
        map.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - map.frame.minX) / map.frame.width,
            dy: (point.y - map.frame.minY) / map.frame.height
        )).tap()
        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "\(style)/\(mapStyle)")
        XCTAssertTrue(card.label.contains("Canyon Lookout Trail"))
        card.tap()
        XCTAssertTrue(app.buttons["place-profile.back"].waitForExistence(timeout: 8))
        app.buttons["place-profile.back"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        app.terminate()
    }
}
