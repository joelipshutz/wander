#if DEBUG
import XCTest
@testable import Wander

final class ProfileHeaderMotionStateTests: XCTestCase {
    private let avatar = CGRect(x: 16, y: 68, width: 86, height: 86)

    func testExpandsWhenScrollingPastPhotoMidpoint() {
        var state = ProfileHeaderMotionState()
        XCTAssertFalse(state.update(offset: 110, originalAvatar: avatar))
        XCTAssertFalse(state.expanded)
        XCTAssertTrue(state.update(offset: 111, originalAvatar: avatar))
        XCTAssertTrue(state.expanded)
    }

    func testHoldsExpandedWhileScrollingContentAndOnEarlyReverse() {
        var state = ProfileHeaderMotionState()
        _ = state.update(offset: 300, originalAvatar: avatar)
        XCTAssertFalse(state.update(offset: 750, originalAvatar: avatar))
        XCTAssertFalse(state.update(offset: 200, originalAvatar: avatar))
        XCTAssertTrue(state.expanded)
    }

    func testReturnsAtPhotoBottomOnlyOnUpwardScroll() {
        var state = ProfileHeaderMotionState()
        _ = state.update(offset: 111, originalAvatar: avatar)
        XCTAssertFalse(state.update(offset: 154, originalAvatar: avatar))
        _ = state.update(offset: 300, originalAvatar: avatar)
        XCTAssertTrue(state.update(offset: 154, originalAvatar: avatar))
        XCTAssertFalse(state.expanded)
        XCTAssertFalse(state.update(offset: 50, originalAvatar: avatar))
    }

    func testStationaryScrollDoesNotRetriggerAnimation() {
        var state = ProfileHeaderMotionState()
        _ = state.update(offset: 111, originalAvatar: avatar)
        XCTAssertFalse(state.update(offset: 111, originalAvatar: avatar))
        XCTAssertTrue(state.expanded)
    }

    func testPinnedControlsDefineTheVisibleViewportEdge() {
        var state = ProfileHeaderMotionState()
        let visibleAvatar = avatar.offsetBy(dx: 0, dy: -56)
        XCTAssertFalse(state.update(offset: 54, originalAvatar: visibleAvatar))
        XCTAssertTrue(state.update(offset: 55, originalAvatar: visibleAvatar))
        _ = state.update(offset: 300, originalAvatar: visibleAvatar)
        XCTAssertTrue(state.update(offset: 98, originalAvatar: visibleAvatar))
        XCTAssertFalse(state.expanded)
    }

    func testInlineOptionRestoresAtBioBottomOnUpwardScroll() {
        var state = ProfileHeaderMotionState()
        let bioBottom: CGFloat = 240
        XCTAssertTrue(state.update(offset: 111, originalAvatar: avatar, restoreBoundary: bioBottom))
        XCTAssertFalse(state.update(offset: 300, originalAvatar: avatar, restoreBoundary: bioBottom))
        XCTAssertFalse(state.update(offset: 250, originalAvatar: avatar, restoreBoundary: bioBottom))
        XCTAssertTrue(state.update(offset: 240, originalAvatar: avatar, restoreBoundary: bioBottom))
        XCTAssertFalse(state.expanded)
    }

    func testPreviewRequiresExplicitKnownVariant() {
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: []))
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion"]))
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion", "unknown"]))
        for variant in ProfileHeaderMotionVariant.allCases {
            XCTAssertEqual(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion", variant.rawValue]), variant)
        }
    }
}
#endif
