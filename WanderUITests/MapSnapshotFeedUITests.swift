import XCTest

@MainActor
final class MapSnapshotFeedUITests: XCTestCase {
    func testSnapshotCardShowsCountAndCoverOpensList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-WanderFeedPhotoStackUITest", "-WanderMapSnapshotFeedReview",
                               "-WanderDisableWalkthroughs"]
        app.launch()
        let cover = app.buttons["feed.photo-stack.postcard.photos"]
        XCTAssertTrue(cover.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["7 places"].exists)
        XCTAssertTrue(cover.label.contains("map snapshot list"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "map-snapshot-feed-\(Int(app.frame.width))"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        cover.tap()
        XCTAssertTrue(app.staticTexts["feed.photo-stack.place.opened"].waitForExistence(timeout: 5))
    }
}
