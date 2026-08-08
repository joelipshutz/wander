import XCTest
@testable import Wander

@MainActor
final class FirstVisitWalkthroughTests: XCTestCase {
    func testApprovedWalkthroughCoversEverySurfaceWithThirtyGuidedSteps() {
        XCTAssertEqual(FirstVisitWalkthroughContent.allSteps.count, 30)
        XCTAssertEqual(
            Set(FirstVisitWalkthroughContent.stepsBySurface.keys),
            Set(WalkthroughSurface.allCases)
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.map]?.map(\.target),
            [.mapAdd, .mapAddAgain, .mapFilters, .mapSearch, .mapMarker, .mapTabs]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.add]?.map(\.target),
            [.addSearch, .addPlace, .addImport]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.saveFlow]?.map(\.target),
            [.saveStatus, .saveContinue, .saveDetails, .saveSubmit]
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
        XCTAssertEqual(coordinator.currentStep?.target, .mapAddAgain)

        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .mapAddAgain)

        coordinator.perform(.mapAddAgain)
        XCTAssertEqual(coordinator.currentStep?.target, .mapFilters)
    }

    func testPassiveStepOnlyAdvancesThroughNext() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.add)
        coordinator.perform(.addSearch)
        coordinator.perform(.addPlace)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)

        coordinator.perform(.addImport)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)

        coordinator.advancePassiveStep()
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertEqual(coordinator.requestedSurface, .map)
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

    func testImportLessonUsesSecondLaunchAndDeviceLessonUsesThirdLaunch() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)

        let firstLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        firstLaunch.registerLaunch()
        firstLaunch.presentLaunchLessonIfEligible()
        XCTAssertFalse(firstLaunch.isPresentingImportLesson)
        XCTAssertFalse(firstLaunch.isPresentingDeviceFeaturesLesson)

        let secondLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        secondLaunch.registerLaunch()
        secondLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(secondLaunch.isPresentingImportLesson)
        XCTAssertFalse(secondLaunch.isPresentingDeviceFeaturesLesson)

        secondLaunch.completeImportLesson()
        XCTAssertFalse(secondLaunch.isPresentingImportLesson)

        let thirdLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        thirdLaunch.registerLaunch()
        thirdLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(thirdLaunch.isPresentingDeviceFeaturesLesson)

        thirdLaunch.completeDeviceFeaturesLesson()
        XCTAssertFalse(thirdLaunch.isPresentingDeviceFeaturesLesson)

        let fourthLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        fourthLaunch.registerLaunch()
        fourthLaunch.presentLaunchLessonIfEligible()
        XCTAssertFalse(fourthLaunch.isPresentingLaunchLesson)
    }

    func testForcedLaunchLessonsSupportVisualTesting() throws {
        let defaults = try makeDefaults()
        let importCoordinator = FirstVisitWalkthroughCoordinator(
            userID: "visual-test",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        importCoordinator.registerLaunch(forceImportLesson: true)
        XCTAssertTrue(importCoordinator.isPresentingImportLesson)
        XCTAssertNil(importCoordinator.currentStep)

        let deviceCoordinator = FirstVisitWalkthroughCoordinator(
            userID: "visual-test-2",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )
        deviceCoordinator.registerLaunch(forceDeviceFeaturesLesson: true)
        XCTAssertTrue(deviceCoordinator.isPresentingDeviceFeaturesLesson)
        XCTAssertNil(deviceCoordinator.currentStep)
    }

    func testCompletedSurfacesRequestTheNextGuidedDestination() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.map)
        for target in [
            WalkthroughTargetID.mapAdd,
            .mapAddAgain,
            .mapFilters,
            .mapSearch,
            .mapMarker
        ] {
            coordinator.perform(target)
        }
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.requestedSurface, .feed)

        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.feedSearch)
        coordinator.perform(.feedSmartSearch)
        XCTAssertEqual(coordinator.requestedSurface, .feed)

        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.listEditor)
        coordinator.perform(.listEditorTitle)
        coordinator.perform(.listEditorPrivacy)
        coordinator.perform(.listEditorCollaborators)
        XCTAssertEqual(coordinator.requestedSurface, .lists)

        coordinator.consumeRequestedSurface(.lists)
        coordinator.activate(.listDetail)
        coordinator.perform(.listMap)
        coordinator.perform(.listActions)
        XCTAssertEqual(coordinator.requestedSurface, .profile)
    }

    func testCaretConnectsTopTargetToCardAndStaysInsideSpotlight() {
        let layout = WalkthroughCoachMarkLayout(
            targetFrame: CGRect(x: 650, y: 72, width: 56, height: 56),
            containerSize: CGSize(width: 734, height: 844),
            cardSize: CGSize(width: 286, height: 112)
        )

        XCTAssertFalse(layout.cardAboveTarget)
        XCTAssertEqual(layout.pointerTip.y, layout.spotlightFrame.maxY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.pointerTip.x, layout.spotlightFrame.minX)
        XCTAssertLessThanOrEqual(layout.pointerTip.x, layout.spotlightFrame.maxX)
        XCTAssertGreaterThanOrEqual(layout.cardFrame.minX, 16)
        XCTAssertLessThanOrEqual(layout.cardFrame.maxX, 718)
    }

    func testCaretConnectsBottomTabTargetToCardAndStaysInsideSpotlight() {
        let layout = WalkthroughCoachMarkLayout(
            targetFrame: CGRect(x: 252, y: 758, width: 92, height: 56),
            containerSize: CGSize(width: 390, height: 844),
            cardSize: CGSize(width: 326, height: 146)
        )

        XCTAssertTrue(layout.cardAboveTarget)
        XCTAssertEqual(layout.pointerTip.y, layout.spotlightFrame.minY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.pointerTip.x, layout.spotlightFrame.minX)
        XCTAssertLessThanOrEqual(layout.pointerTip.x, layout.spotlightFrame.maxX)
        XCTAssertEqual(layout.spotlightFrame.minY - layout.cardFrame.maxY, 12, accuracy: 0.001)
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
