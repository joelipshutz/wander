import XCTest
@testable import Wander

final class MapMoreFilterResetTests: XCTestCase {
    func testOtherTabResetIntervalIsThreeMinutes() {
        XCTAssertEqual(MapMoreFilterResetPolicy.otherTabInterval, 180)
    }

    func testReturningBeforeThreeMinutesPreservesMoreFilters() {
        let leftMapAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(
            MapMoreFilterResetPolicy.shouldResetAfterReturning(
                leftMapAt: leftMapAt,
                returnedAt: leftMapAt.addingTimeInterval(179.99)
            )
        )
    }

    func testReturningAtThreeMinutesResetsMoreFilters() {
        let leftMapAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            MapMoreFilterResetPolicy.shouldResetAfterReturning(
                leftMapAt: leftMapAt,
                returnedAt: leftMapAt.addingTimeInterval(180)
            )
        )
    }

    func testColdLaunchStartsWithNoMoreFilters() {
        let state = MapScreen.resolvedInitialMapFilterState(
            from: ["Wander", "-WanderMapCaptureMode", "friends"]
        )

        XCTAssertEqual(state.source, .friends)
        XCTAssertEqual(state.more, MapMoreFilterSelection())
    }

    func testSelectingTheAlreadyActiveSourceResetsMoreFilters() {
        var state = MapFilterState(
            source: .friends,
            more: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_maya"],
                status: .checkIns
            )
        )

        state.selectSource(.friends)

        XCTAssertEqual(state.source, .friends)
        XCTAssertEqual(state.more, MapMoreFilterSelection())
    }

    func testUITestResetIntervalOverrideIsValidated() {
        XCTAssertEqual(
            MapScreen.resolvedMoreFiltersAwayResetInterval(
                from: ["Wander", "-WanderMapMoreFiltersAwayResetSeconds", "0.2"]
            ),
            0.2
        )
        XCTAssertEqual(
            MapScreen.resolvedMoreFiltersAwayResetInterval(
                from: ["Wander", "-WanderMapMoreFiltersAwayResetSeconds", "invalid"]
            ),
            MapMoreFilterResetPolicy.otherTabInterval
        )
    }
}
