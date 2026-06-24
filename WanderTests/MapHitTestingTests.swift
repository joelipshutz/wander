import CoreGraphics
import XCTest
@testable import Wander

final class MapHitTestingTests: XCTestCase {
    func testScreenPointWithinMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertTrue(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 146, y: 260),
                nearAny: [marker]
            )
        )
    }

    func testScreenPointOutsideMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertFalse(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 190, y: 260),
                nearAny: [marker]
            )
        )
    }
}

final class MapFilterSelectionTests: XCTestCase {
    func testNoOwnerFiltersSelectedProducesNoPlaceFilters() {
        XCTAssertNil(
            MapFilterSelection.placeFilters(
                selectedFilters: [.been, .wanna],
                selectedSocialOwnerID: nil
            )
        )
    }

    func testNoStatusFiltersSelectedProducesNoPlaceFilters() {
        XCTAssertNil(
            MapFilterSelection.placeFilters(
                selectedFilters: [.you, .social],
                selectedSocialOwnerID: nil
            )
        )
    }

    func testAllOwnerAndStatusFiltersSelectedKeepsUnrestrictedGroups() {
        let filters = MapFilterSelection.placeFilters(
            selectedFilters: [.you, .social, .been, .wanna],
            selectedSocialOwnerID: nil
        )

        XCTAssertEqual(filters?.ownerScopes, Set(["you", "social"]))
        XCTAssertEqual(filters?.statuses, Set<PlaceStatus>())
        XCTAssertEqual(filters?.ownerIDs, Set<String>())
    }

    func testSingleStatusAndSocialOwnerSelectionBuildsNarrowFilters() {
        let filters = MapFilterSelection.placeFilters(
            selectedFilters: [.social, .wanna],
            selectedSocialOwnerID: "user_maya"
        )

        XCTAssertEqual(filters?.ownerScopes, Set(["social"]))
        XCTAssertEqual(filters?.statuses, Set([.wannaGo]))
        XCTAssertEqual(filters?.ownerIDs, Set(["user_maya"]))
    }
}
