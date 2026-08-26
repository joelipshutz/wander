#if DEBUG
@testable import Wander
import XCTest

final class InCommonDesignMockupTests: XCTestCase {
    func testLaunchArgumentResolvesEachDesignDirection() {
        XCTAssertEqual(
            InCommonDesignMockupPage.resolved(
                from: ["Wander", "-WanderInCommonMockup", "overlap"],
                environment: [:]
            ),
            .overlap
        )
        XCTAssertEqual(
            InCommonDesignMockupPage.resolved(
                from: ["Wander", "-WanderInCommonMockup", "tasteReceipt"],
                environment: [:]
            ),
            .tasteReceipt
        )
        XCTAssertEqual(
            InCommonDesignMockupPage.resolved(
                from: ["Wander", "-WanderInCommonMockup", "sharedMap"],
                environment: [:]
            ),
            .sharedMap
        )
    }

    func testEnvironmentLaunchValueSupportsDeterministicSimulatorCapture() {
        XCTAssertEqual(
            InCommonDesignMockupPage.resolved(
                from: ["Wander"],
                environment: ["WANDER_IN_COMMON_MOCKUP": "nonFriend"]
            ),
            .nonFriend
        )
    }

    func testMockupIsNotActivatedWithoutAnExplicitLaunchValue() {
        XCTAssertNil(
            InCommonDesignMockupPage.resolved(from: ["Wander"], environment: [:])
        )
    }

    func testNonFriendContextUsesOnlyItsVisibleComparisonCount() {
        XCTAssertEqual(InCommonMockupRelationship.friend.visiblePlaceCount, 18)
        XCTAssertEqual(InCommonMockupRelationship.following.visiblePlaceCount, 8)
        XCTAssertLessThan(
            InCommonMockupRelationship.following.score,
            InCommonMockupRelationship.friend.score
        )
    }

    func testMockupKeepsNativeNavigationStackBackGestureContract() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Profile/InCommonDesignMockups.swift"
            )
        )

        XCTAssertTrue(source.contains("NavigationStack(path: $path)"))
        XCTAssertTrue(
            source.contains(
                ".navigationDestination(for: InCommonMockupDirection.self)"
            )
        )
        XCTAssertFalse(source.contains(".navigationBarBackButtonHidden(true)"))
    }
}
#endif
