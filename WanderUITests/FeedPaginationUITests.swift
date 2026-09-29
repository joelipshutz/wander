import XCTest

@MainActor
final class FeedPaginationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoadsTwentyMoreOnlyAtBottomThenStopsAtEnd() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedPaginationUITest", "-WanderInitialTab", "discover"]
        app.launch()
        let scroll = app.scrollViews["feed.places.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        expectCount(20, scroll: scroll)
        capture("feed-first-20")
        for _ in 0..<3 { scroll.swipeUp() }
        XCTAssertEqual(scroll.value as? String, "20 activities loaded")
        XCTAssertFalse(app.otherElements["feed.loadingMore"].exists)
        scrollToNextPage(app, scroll: scroll, previousCount: 20)
        expectCount(40, scroll: scroll)
        capture("feed-next-20")
        scrollToNextPage(app, scroll: scroll, previousCount: 40)
        expectCount(45, scroll: scroll)
        for _ in 0..<8 { scroll.swipeUp() }
        XCTAssertEqual(scroll.value as? String, "45 activities loaded")
        XCTAssertFalse(app.otherElements["feed.loadingMore"].exists)
        capture("feed-exhausted")
    }

    private func scrollToNextPage(_ app: XCUIApplication, scroll: XCUIElement, previousCount: Int) {
        for _ in 0..<35 {
            let loading = app.descendants(matching: .any)["feed.loadingMore"].firstMatch
            if loading.exists {
                capture("feed-loading-more")
                return
            }
            if scroll.value as? String != "\(previousCount) activities loaded" {
                XCTFail("The next page loaded without observable loading feedback")
                return
            }
            scroll.swipeUp(velocity: .fast)
        }
        XCTFail("Scrolling to the bottom did not load the next page")
    }

    private func expectCount(_ count: Int, scroll: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "\(count) activities loaded"), object: scroll
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
