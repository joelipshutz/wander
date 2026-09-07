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

    func testMorePanelUsesAdaptiveMapGlassAndOptionsUseUnderlineSelection() throws {
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
        XCTAssertTrue(
            popover.contains("tone: appearance.neutralGlassTone")
        )
        XCTAssertFalse(optionChip.contains(".wanderGlassPanel("))
        XCTAssertFalse(optionChip.contains(".background(astirBrandMode.raisedBackground"))
        XCTAssertTrue(optionChip.contains("Rectangle()"))
        XCTAssertTrue(
            optionChip.contains(
                "isSelected ? astirBrandMode.accent : astirBrandMode.border"
            )
        )
        XCTAssertTrue(optionChip.contains(".overlay(alignment: .bottom)"))
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

    func testSelectingPeopleFromAnySourceSwitchesToFriendsAndPreservesRefinements() {
        for source in MapSource.allCases {
            var state = MapFilterState(source: source)
            let selection = MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_maya", "user_demo"],
                status: .checkIns
            )

            state.setMoreSelection(selection)

            XCTAssertEqual(state.source, .friends, "Starting source: \(source)")
            XCTAssertEqual(state.more, selection)
        }
    }

    func testChangingOtherRefinementsWithoutPeopleKeepsTheCurrentSource() {
        for source in MapSource.allCases {
            var state = MapFilterState(source: source)
            let selection = MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                status: .wanna
            )

            state.setMoreSelection(selection)

            XCTAssertEqual(state.source, source)
            XCTAssertEqual(state.more, selection)
        }
    }

    func testDeselectingTheLastPersonKeepsFriendsAndOtherRefinements() {
        var state = MapFilterState(source: .you)
        var selection = MapMoreFilterSelection(
            categories: [WanderPlaceCategory.coffeeTeaSweets],
            people: ["user_maya"],
            status: .wanna
        )
        state.setMoreSelection(selection)

        selection.togglePerson("user_maya")
        state.setMoreSelection(selection)

        XCTAssertEqual(state.source, .friends)
        XCTAssertTrue(state.more.people.isEmpty)
        XCTAssertEqual(state.more.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(state.more.status, .wanna)
    }

    func testAllPeopleAndResetKeepTheAutomaticallySelectedFriendsSource() {
        var state = MapFilterState(source: .featured)
        var selection = MapMoreFilterSelection(people: ["user_maya", "user_demo"])
        state.setMoreSelection(selection)

        selection.selectAllPeople()
        state.setMoreSelection(selection)
        XCTAssertEqual(state.source, .friends)
        XCTAssertTrue(state.more.people.isEmpty)

        state.setMoreSelection(MapMoreFilterSelection())
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
