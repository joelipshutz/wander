import XCTest
@testable import Wander

final class VisibilityPolicyTests: XCTestCase {
    private let policy = VisibilityPolicy()

    func testOwnerCanSeeEveryVisibilityLevel() {
        for visibility in PlaceVisibility.allCases {
            XCTAssertTrue(policy.canSeePlace(viewerID: "user_a", ownerID: "user_a", visibility: visibility, relationship: .owner, isBlocked: false))
        }
    }

    func testFollowerCanSeeFollowersButNotMutualOrSelf() {
        XCTAssertTrue(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .followers, relationship: .follower, isBlocked: false))
        XCTAssertFalse(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .mutuals, relationship: .follower, isBlocked: false))
        XCTAssertFalse(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .selfOnly, relationship: .follower, isBlocked: false))
    }

    func testMutualCanSeeFollowersAndMutuals() {
        XCTAssertTrue(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .followers, relationship: .mutual, isBlocked: false))
        XCTAssertTrue(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .mutuals, relationship: .mutual, isBlocked: false))
        XCTAssertFalse(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .selfOnly, relationship: .mutual, isBlocked: false))
    }

    func testLoggedOutAndBlockedViewersSeeNoPlaces() {
        XCTAssertFalse(policy.canSeePlace(viewerID: nil, ownerID: "user_b", visibility: .followers, relationship: .nonFollower, isBlocked: false))
        XCTAssertFalse(policy.canSeePlace(viewerID: "user_a", ownerID: "user_b", visibility: .followers, relationship: .mutual, isBlocked: true))
    }

    func testStealthModeNormalizesLegacyFriendsToNotPrivate() {
        XCTAssertEqual(PlaceVisibility.followers.normalizedForStealthMode, .followers)
        XCTAssertEqual(PlaceVisibility.mutuals.normalizedForStealthMode, .followers)
        XCTAssertEqual(PlaceVisibility.selfOnly.normalizedForStealthMode, .selfOnly)
    }

    func testStealthModeToggleWritesOnlyPrivateOrFollowersVisibility() {
        XCTAssertEqual(PlaceVisibility.visibilityForStealthMode(isPrivate: true), .selfOnly)
        XCTAssertEqual(PlaceVisibility.visibilityForStealthMode(isPrivate: false), .followers)
    }

    func testOnlyStealthModeShowsTileLockIndicator() {
        XCTAssertFalse(PlaceVisibility.followers.showsTileLockIndicator)
        XCTAssertFalse(PlaceVisibility.mutuals.showsTileLockIndicator)
        XCTAssertTrue(PlaceVisibility.selfOnly.showsTileLockIndicator)
    }
}
