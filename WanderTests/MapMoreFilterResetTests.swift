import XCTest
@testable import Wander

final class MapMoreFilterResetTests: XCTestCase {
    func testBadgeCountsEverySelectedCategoryPersonAndStatus() {
        let eightSelections = MapMoreFilterSelection(
            categories: [
                WanderPlaceCategory.coffeeTeaSweets,
                WanderPlaceCategory.barsNightlife,
                WanderPlaceCategory.outdoorsNature,
            ],
            people: ["user_1", "user_2", "user_3", "user_4"],
            status: .checkIns
        )
        let fiveSelections = MapMoreFilterSelection(
            categories: [WanderPlaceCategory.restaurantsFood],
            people: ["user_1", "user_2", "user_3"],
            status: .wanna
        )

        XCTAssertEqual(eightSelections.activeOptionCount, 8)
        XCTAssertEqual(fiveSelections.activeOptionCount, 5)
    }

    func testBadgeCountDecreasesAsOptionsAreDeselected() {
        var selection = MapMoreFilterSelection(
            categories: [
                WanderPlaceCategory.coffeeTeaSweets,
                WanderPlaceCategory.barsNightlife,
            ],
            people: ["user_1"],
            status: .checkIns
        )

        XCTAssertEqual(selection.activeOptionCount, 4)

        selection.toggleCategory(WanderPlaceCategory.barsNightlife)
        XCTAssertEqual(selection.activeOptionCount, 3)

        selection.togglePerson("user_1")
        XCTAssertEqual(selection.activeOptionCount, 2)

        selection.status = .all
        XCTAssertEqual(selection.activeOptionCount, 1)
    }

    @MainActor
    func testMorePanelUsesDeliberateMotionTiming() throws {
        XCTAssertEqual(MapMoreFilterMotionStyle.presentDuration, 0.46, accuracy: 0.001)
        XCTAssertEqual(MapMoreFilterMotionStyle.dismissDuration, 0.36, accuracy: 0.001)
        XCTAssertGreaterThan(MapMoreFilterMotionStyle.dismissDuration, 0.16)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(map.contains("MapMoreFilterMotionStyle.panelTransition"))
    }

    func testMorePanelUsesLiquidGlassAndOptionsUseIndependentAstirSurfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let popoverStart = try XCTUnwrap(map.range(of: "private struct MapMoreFiltersPopover"))
        let popoverEnd = try XCTUnwrap(
            map.range(of: "private struct MapMoreOptionChip", range: popoverStart.upperBound..<map.endIndex)
        )
        let optionEnd = try XCTUnwrap(
            map.range(of: "private struct SearchResultMarker", range: popoverEnd.upperBound..<map.endIndex)
        )
        let popover = String(map[popoverStart.lowerBound..<popoverEnd.lowerBound])
        let optionChip = String(map[popoverEnd.lowerBound..<optionEnd.lowerBound])

        XCTAssertTrue(popover.contains(".wanderGlassPanel("))
        XCTAssertTrue(popover.contains("tone: appearance.neutralGlassTone"))
        XCTAssertFalse(popover.contains(".background(\n            WanderTheme.surfaceBone.color"))
        XCTAssertFalse(optionChip.contains(".wanderGlassPanel("))
        XCTAssertFalse(optionChip.contains(".background(astirBrandMode.raisedBackground"))
        XCTAssertTrue(optionChip.contains("Rectangle()"))
        XCTAssertTrue(
            optionChip.contains(
                "isSelected ? astirBrandMode.accent : astirBrandMode.border"
            )
        )
        XCTAssertTrue(optionChip.contains(".overlay(alignment: .leading)"))
        XCTAssertTrue(popover.contains("emoji: WanderPlaceCategory.broadEmoji(for: category)"))
    }

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

    @MainActor
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

    @MainActor
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
