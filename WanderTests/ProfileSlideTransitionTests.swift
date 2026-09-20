import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class ProfileSlideTransitionTests: XCTestCase {
    func testHiddenProfileStartsToTheRightAndBackUsesTheSameEdge() {
        let controller = makeController(presented: false)
        let page = controller.children[0].view!
        XCTAssertEqual(page.transform.tx, 390)
        XCTAssertEqual(page.transform.ty, 0)
        controller.setPresented(true, animated: false)
        XCTAssertEqual(page.transform, .identity)
        controller.setPresented(false, animated: false)
        XCTAssertEqual(page.transform.tx, 390)
        XCTAssertEqual(page.transform.ty, 0)
        XCTAssertNil(page.superview)
    }

    func testSwipeDrivesTheNativePageWithoutPublishingAnotherRoot() {
        let controller = makeController(presented: true)
        let page = controller.children[0].view!
        controller.beginInteractiveDismissal()
        controller.updateInteractiveDismissal(translation: 110)
        XCTAssertEqual(page.transform.tx, 110)
        XCTAssertEqual(page.transform.ty, 0)
        XCTAssertTrue(controller.isPresented)
        controller.updateInteractiveDismissal(translation: -10)
        XCTAssertEqual(page.transform.tx, 0)
        controller.updateInteractiveDismissal(translation: 900)
        XCTAssertEqual(page.transform.tx, 390)
    }

    func testCancelledSwipeRestoresPageWithoutRequestingDismissal() async {
        let controller = makeController(presented: true)
        var requests = 0
        controller.onRequestDismiss = { requests += 1 }
        controller.beginInteractiveDismissal()
        controller.updateInteractiveDismissal(translation: 180)
        controller.endInteractiveDismissal(translation: 180, velocity: 800, cancelled: true)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(controller.children[0].view.transform, .identity)
        XCTAssertTrue(controller.isPresented)
        XCTAssertFalse(controller.isInteracting)
        XCTAssertEqual(requests, 0)
    }

    func testCompletedSwipeNotifiesRequestBeforeCompletionExactlyOnceWithReduceMotion() {
        let controller = makeController(presented: true)
        controller.reduceMotion = true
        var events: [String] = []
        controller.onRequestDismiss = { events.append("request") }
        controller.onTransitionCompleted = { events.append("complete:\($0)") }
        controller.beginInteractiveDismissal()
        controller.updateInteractiveDismissal(translation: 180)
        XCTAssertEqual(controller.children[0].view.transform, .identity)
        controller.endInteractiveDismissal(translation: 180, velocity: 0, cancelled: false)
        controller.setPresented(false, animated: false)
        XCTAssertEqual(events, ["request", "complete:false"])
        XCTAssertFalse(controller.isPresented)
    }

    func testDisabledSwipeCannotMoveOrDismissThePage() {
        let controller = makeController(presented: true)
        controller.isInteractiveDismissEnabled = false
        controller.beginInteractiveDismissal()
        controller.updateInteractiveDismissal(translation: 200)
        controller.endInteractiveDismissal(translation: 200, velocity: 800, cancelled: false)
        XCTAssertEqual(controller.children[0].view.transform, .identity)
        XCTAssertTrue(controller.isPresented)
    }

    private func makeController(presented: Bool) -> PlaceProfileSlidingHostingController<Text> {
        let controller = PlaceProfileSlidingHostingController(
            rootView: Text("Profile"), isPresented: presented, onTransitionCompleted: { _ in }
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }
}
