import SwiftUI
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

    func testInlineTransitionStartsAsTheNamePassesUnderTheToolbar() {
        var state = ProfileHeaderMotionState()
        let visibleAvatar = avatar.offsetBy(dx: 0, dy: -56)
        let nameTop: CGFloat = 68 - 56
        XCTAssertFalse(state.update(offset: 11, originalAvatar: visibleAvatar, entryBoundary: nameTop))
        XCTAssertTrue(state.update(offset: 12, originalAvatar: visibleAvatar, entryBoundary: nameTop))
        XCTAssertTrue(state.expanded)
        XCTAssertLessThan(nameTop, visibleAvatar.midY)
        XCTAssertFalse(state.update(offset: 300, originalAvatar: visibleAvatar, entryBoundary: nameTop))
    }

    #if DEBUG
    func testPreviewRequiresExplicitKnownVariant() {
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: []))
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion"]))
        XCTAssertNil(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion", "unknown"]))
        for variant in ProfileHeaderMotionVariant.allCases {
            XCTAssertEqual(ProfileHeaderMotionVariant.resolved(arguments: ["-ProfileHeaderMotion", variant.rawValue]), variant)
        }
    }
    #endif

    func testApprovedMotionIsTheDefaultForNormalProfiles() {
        XCTAssertEqual(EnvironmentValues().resolvedProfileHeaderMotion, .compact)
    }

    func testAccessibilityTextSizesKeepTheOriginalReadingLayout() {
        var environment = EnvironmentValues()
        environment.dynamicTypeSize = .accessibility3
        XCTAssertNil(environment.resolvedProfileHeaderMotion)
        environment.dynamicTypeSize = .xxxLarge
        XCTAssertEqual(environment.resolvedProfileHeaderMotion, .compact)
    }

    func testPhotoStaysPinnedAcrossBothScrollDirectionsIncludingBioRestoration() {
        var state = ProfileHeaderMotionState()
        let pinnedY = avatar.midY
        for offset: CGFloat in [0, 12, 100, 300, 750, 300, 240, 150, 50, 12, 0] {
            _ = state.update(offset: offset, originalAvatar: avatar, entryBoundary: 12, restoreBoundary: 240)
            let center = ProfileHeaderPhotoLayout.center(
                inlineFrame: avatar.offsetBy(dx: 0, dy: -offset), pinnedY: pinnedY
            )
            XCTAssertEqual(center, CGPoint(x: avatar.midX, y: pinnedY))
            XCTAssertGreaterThanOrEqual(center.y - avatar.height / 2, 0)
            if offset == 240 { XCTAssertFalse(state.expanded) }
        }
    }

    func testPhotoRejoinsInlinePositionContinuouslyAndFollowsPullDownBounce() {
        for offset: CGFloat in [1, 0, -1, -20, -80, -20, -1, 0, 1] {
            let inlineFrame = avatar.offsetBy(dx: 0, dy: -offset)
            let center = ProfileHeaderPhotoLayout.center(inlineFrame: inlineFrame, pinnedY: avatar.midY)
            XCTAssertEqual(center.x, inlineFrame.midX)
            XCTAssertEqual(center.y, avatar.midY - min(offset, 0))
        }
    }

}
