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
}
