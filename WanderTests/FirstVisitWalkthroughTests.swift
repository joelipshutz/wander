import XCTest
@testable import Wander

@MainActor
final class FirstVisitWalkthroughTests: XCTestCase {
    func testApprovedWalkthroughCoversEverySurfaceWithTwentyFourActionSteps() {
        XCTAssertEqual(FirstVisitWalkthroughContent.allSteps.count, 24)
        XCTAssertEqual(
            Set(FirstVisitWalkthroughContent.stepsBySurface.keys),
            Set(WalkthroughSurface.allCases)
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.map]?.map(\.target),
            [.mapAdd, .mapFilters, .mapSearch, .mapMarker, .mapTabs]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.profile]?.map(\.target),
            [.profileSettings, .profileSocial, .profileActivity, .profileShare]
        )
    }

    func testOnlyTheHighlightedActionAdvancesTheWalkthrough() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.map)
        XCTAssertEqual(coordinator.currentStep?.target, .mapAdd)

        coordinator.perform(.mapSearch)
        XCTAssertEqual(coordinator.currentStep?.target, .mapAdd)

        coordinator.perform(.mapAdd)
        XCTAssertEqual(coordinator.currentStep?.target, .mapFilters)
    }

    func testProgressResumesPerUserAndPerSurface() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let ryan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        ryan.activate(.feed)
        ryan.perform(.feedActivity)
        XCTAssertEqual(ryan.currentStep?.target, .feedSurfaceSwitch)

        ryan.activate(.profile)
        XCTAssertEqual(ryan.currentStep?.target, .profileSettings)

        let resumedRyan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        resumedRyan.activate(.feed)
        XCTAssertEqual(resumedRyan.currentStep?.target, .feedSurfaceSwitch)

        let joe = FirstVisitWalkthroughCoordinator(userID: "joe", store: store)
        joe.activate(.feed)
        XCTAssertEqual(joe.currentStep?.target, .feedActivity)
    }

    func testCompletedSurfaceDoesNotAppearAgain() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        coordinator.activate(.feedSearch)
        coordinator.perform(.feedSmartSearch)
        XCTAssertNil(coordinator.activeSurface)

        coordinator.activate(.feedSearch)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertTrue(store.isComplete(for: "ryan", surface: .feedSearch))
    }

    func testContentVersionMakesUpdatedWalkthroughEligibleAgain() throws {
        let defaults = try makeDefaults()
        let firstVersion = FirstVisitWalkthroughStore(defaults: defaults, version: 1)
        firstVersion.markComplete(for: "ryan", surface: .lists)

        XCTAssertTrue(firstVersion.isComplete(for: "ryan", surface: .lists))
        XCTAssertFalse(
            FirstVisitWalkthroughStore(defaults: defaults, version: 2)
                .isComplete(for: "ryan", surface: .lists)
        )
    }

    func testUnavailableTargetRecoveryOnlyAdvancesTheCurrentTarget() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.lists)
        coordinator.recoverUnavailableTarget(.listsOpenPlan)
        XCTAssertEqual(coordinator.currentStep?.target, .listsCreate)

        coordinator.recoverUnavailableTarget(.listsCreate)
        XCTAssertEqual(coordinator.currentStep?.target, .listsScope)
    }

    func testDisabledCoordinatorNeverPresentsWalkthroughs() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "snapshot-test",
            store: FirstVisitWalkthroughStore(defaults: defaults),
            isEnabled: false
        )

        coordinator.activate(.map)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "FirstVisitWalkthroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
