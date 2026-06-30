import XCTest
@testable import Wander

final class NavigationContractTests: XCTestCase {
    func testBottomNavigationUsesRequestedFiveItemOrder() {
        XCTAssertEqual(WanderTab.allCases, [.map, .discover, .add, .lists, .profile])
    }

    @MainActor
    func testRootViewCanResolveInitialTabForVisualQA() {
        XCTAssertEqual(
            WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "discover"]),
            .discover
        )
        XCTAssertEqual(
            WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "lists"]),
            .lists
        )
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "add"]), .map)
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab", "nope"]), .map)
        XCTAssertEqual(WanderRootView.resolvedInitialTab(from: ["Wander", "-WanderInitialTab"]), .map)
    }

    @MainActor
    func testRootViewCanResolveSettingsPresentationForVisualQA() {
        XCTAssertEqual(
            WanderRootView.resolvedInitialPresentation(from: ["Wander", "-WanderOpenSettings"]),
            .settings
        )
        XCTAssertNil(WanderRootView.resolvedInitialPresentation(from: ["Wander"]))
    }

    func testListsScreenCanResolveInteractiveVisualQAScenarios() {
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collaboratorsSheet"]),
            .collaboratorsSheet
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "mapPreview"]),
            .mapPreview
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "mapSelectedPlace"]),
            .mapSelectedPlace
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "createCollaboratorsSearch"]),
            .createCollaboratorsSearch
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "editDeleteConfirm"]),
            .editDeleteConfirm
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collabEdit"]),
            .collabEdit
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "collabEditDeleteConfirm"]),
            .collabEditDeleteConfirm
        )
        XCTAssertEqual(
            ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "placeDetail"]),
            .placeDetail
        )
        XCTAssertEqual(ListsScreenScenario.resolved(from: ["Wander", "-WanderListsScenario", "unknown"]), .populated)
    }

    @MainActor
    func testRootViewUsesEmptyFixturesByDefaultAndDemoFixturesOnlyWhenRequested() {
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander"]), .empty)
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(from: ["Wander", "-WanderUseDemoFixtures"]), .demo)
    }

    @MainActor
    func testMapScreenCanResolvePlaceProfileLaunchArgumentsForVisualQA() {
        XCTAssertEqual(
            MapScreen.resolvedInitialMapPlaceQuery(from: ["Wander", "-WanderMapPlace", "Woodcat Coffee"]),
            "Woodcat Coffee"
        )
        XCTAssertNil(MapScreen.resolvedInitialMapPlaceQuery(from: ["Wander", "-WanderMapPlace"]))
        XCTAssertTrue(MapScreen.resolvedInitialPlaceProfilePresentation(from: ["Wander", "-WanderMapSheetExpanded"]))
        XCTAssertFalse(MapScreen.resolvedInitialPlaceProfilePresentation(from: ["Wander"]))
    }

    @MainActor
    func testPlaceProfileEdgeSwipeBackGestureOnlyTriggersFromLeftEdge() {
        XCTAssertTrue(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 96, height: 8)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 52,
                translation: CGSize(width: 120, height: 4)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 40, height: 2)
            )
        )

        XCTAssertFalse(
            PlaceProfileFullScreen.shouldTriggerEdgeSwipeBack(
                startX: 12,
                translation: CGSize(width: 110, height: 110)
            )
        )
    }

    @MainActor
    func testPlaceProfileFullBleedHeaderKeepsMinimumTopInset() {
        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: 0),
            54
        )

        XCTAssertEqual(
            PlaceProfileFullScreen.resolvedFullBleedHeaderTopInset(from: 62),
            62
        )
    }
}
