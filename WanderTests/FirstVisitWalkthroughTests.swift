import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class FirstVisitWalkthroughTests: XCTestCase {
    func testCondensedWalkthroughCoversEveryActiveSurfaceWithThirtyEightGuidedSteps() {
        XCTAssertEqual(FirstVisitWalkthroughContent.allSteps.count, 38)
        XCTAssertEqual(
            Set(FirstVisitWalkthroughContent.stepsBySurface.keys),
            Set(WalkthroughSurface.allCases)
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.map]?.map(\.target),
            [
                .mapAdd,
                .mapAddAgain,
                .mapFeatured,
                .mapFriends,
                .mapMoreFilters,
                .mapSearch,
                .mapMemory,
                .mapTabs
            ]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.sendoff]?.map(\.target),
            [.mapSendoff]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.add]?.map(\.target),
            [.addSearch, .addPlace, .addImport, .addClose]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.saveFlow]?.map(\.target),
            [
                .saveStatus,
                .saveContinue,
                .saveDate,
                .saveDetails,
                .saveRating,
                .saveFriends,
                .saveMoreOptions,
                .saveSubmit
            ]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.feed]?.map(\.target),
            [.feedActivity, .feedDiscoverSearch, .feedPeopleSearch, .feedInvite]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.feedSearch]?.map(\.target),
            [.feedSearchField, .feedSmartSearch, .feedSearchResultsBack, .feedSearchExitBack]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.lists]?.map(\.target),
            [.listsScope, .listsOpenPlan]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.profile]?.map(\.target),
            [.profileShare, .profileActivity, .profileCalendar, .profileMap]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.placeDetail]?.map(\.target),
            [.placeRatings, .placeActions, .placeHistory]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.listDetail]?.map(\.target),
            []
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.listEditor]?.map(\.target),
            []
        )
    }

    func testRequestedExplanationStepsAdvanceWithNext() throws {
        let passiveTargets: [WalkthroughTargetID] = [
            .mapFeatured,
            .mapFriends,
            .mapMoreFilters,
            .mapSearch,
            .mapMemory,
            .mapTabs,
            .addImport,
            .saveDate,
            .saveDetails,
            .saveRating,
            .saveFriends,
            .saveMoreOptions,
            .feedActivity,
            .feedPeopleSearch,
            .feedInvite,
            .feedSearchField,
            .placeRatings,
            .placeActions,
            .placeHistory,
            .listsScope,
            .listsOpenPlan,
            .profileShare,
            .profileActivity,
            .profileCalendar,
            .profileMap,
            .mapSendoff
        ]

        for target in passiveTargets {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .next, "Expected \(target) to show Next")
        }

        let closeStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .addClose }
        )
        XCTAssertEqual(closeStep.advance, .action)
    }

    func testPassiveEditableLessonsAllowInteractionWithoutRequiringIt() throws {
        let editableTargets: [WalkthroughTargetID] = [
            .saveDate,
            .saveDetails,
            .saveRating,
            .saveFriends,
            .feedPeopleSearch
        ]

        for target in editableTargets {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .next)
            XCTAssertTrue(step.allowsTargetInteraction, "Expected \(target) to remain editable")
        }

        for target in [
            WalkthroughTargetID.mapSearch,
            .mapFeatured,
            .mapFriends,
            .mapMoreFilters,
            .addImport,
            .saveMoreOptions,
            .feedActivity,
            .feedInvite,
            .feedSearchField,
            .listsScope,
            .listsOpenPlan,
            .mapTabs,
            .placeRatings,
            .placeActions,
            .placeHistory,
            .profileShare,
            .profileActivity,
            .profileCalendar,
            .profileMap
        ] {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertFalse(step.allowsTargetInteraction, "Expected \(target) to be explanation-only")
        }
    }

    func testFinalSendoffReturnsToMapWithMotivatingAction() throws {
        let step = try XCTUnwrap(
            FirstVisitWalkthroughContent.stepsBySurface[.sendoff]?.first
        )

        XCTAssertEqual(step.target, .mapSendoff)
        XCTAssertEqual(step.title, "Your map is yours now")
        XCTAssertEqual(step.nextButtonTitle, "Start exploring")
        XCTAssertEqual(step.advance, .next)
    }

    func testBottomNavigationCopyExplainsTheConnectedProduct() throws {
        let step = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .mapTabs }
        )

        XCTAssertEqual(step.title, "Your places, all connected")
        XCTAssertEqual(
            step.message,
            "Map, Feed, Lists, and Profile work together to help you find, plan, and remember."
        )
    }

    func testMapFilterAndDiscoverSearchLessonsMatchSupportedBehavior() throws {
        let featured = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .mapFeatured }
        )
        let friends = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .mapFriends }
        )
        let more = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .mapMoreFilters }
        )
        let searchField = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedSearchField }
        )
        let feedActivity = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedActivity }
        )

        XCTAssertEqual(featured.title, "Featured shows you recommendations based on your taste")
        XCTAssertTrue(featured.message.isEmpty)
        XCTAssertEqual(friends.title, "All places from everyone you follow")
        XCTAssertTrue(friends.message.isEmpty)
        XCTAssertTrue(more.message.contains("Category"))
        XCTAssertTrue(more.message.contains("People"))
        XCTAssertTrue(more.message.contains("Status"))
        XCTAssertTrue(searchField.message.contains("category"))
        XCTAssertTrue(searchField.message.contains("neighborhood"))
        XCTAssertTrue(searchField.message.contains("@handle"))
        XCTAssertTrue(searchField.message.contains("saved tag"))
        XCTAssertEqual(feedActivity.title, "See your friends’ check-ins here")
        XCTAssertEqual(
            feedActivity.message,
            "Interact with your trusted feed with a like, comment, or share."
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
        XCTAssertEqual(coordinator.currentStep?.target, .mapFeatured)

        coordinator.perform(.mapFeatured)
        XCTAssertEqual(coordinator.currentStep?.target, .mapFeatured)

        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .mapFriends)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .mapMoreFilters)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .mapSearch)
    }

    func testIneligibleAccountCannotStartAnyFirstVisitLesson() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: FirstVisitWalkthroughStore(defaults: defaults),
            isEnabled: false
        )

        coordinator.registerLaunch(
            forceImportLesson: true,
            forceDeviceFeaturesLesson: true
        )
        coordinator.activate(.map)
        coordinator.forceActivate(.mapAdd)
        coordinator.presentLaunchLessonIfEligible()

        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(coordinator.isPresentingLaunchLesson)
        XCTAssertEqual(
            defaults.integer(
                forKey: "wander.walkthrough.v\(FirstVisitWalkthroughContent.version).existing-user.authenticatedLaunchCount"
            ),
            0
        )
    }

    func testWalkthroughRolloutIsOffByDefaultButSupportsExplicitTestOverride() {
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: []
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: true,
                launchArguments: [],
                isRolloutEnabled: true
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: false,
                launchArguments: [],
                isRolloutEnabled: true
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                isRolloutEnabled: true
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: false,
                launchArguments: ["-WanderEnableWalkthroughs"]
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: ["-WanderEnableWalkthroughs"],
                allowsLaunchOverride: false
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.shouldRetireEligibility(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                allowsLaunchOverride: false
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.shouldRetireEligibility(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                isRolloutEnabled: true,
                allowsLaunchOverride: false
            )
        )
    }

    func testDismissPermanentlyCompletesEveryWalkthroughForTheCurrentAccount() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        var completionCount = 0
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: store,
            onCompleted: { completionCount += 1 }
        )

        coordinator.registerLaunch(forceImportLesson: true)
        XCTAssertTrue(coordinator.isPresentingImportLesson)

        coordinator.dismissEntireWalkthrough()

        XCTAssertFalse(coordinator.isPresentingLaunchLesson)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "existing-user"))
        XCTAssertTrue(
            WalkthroughSurface.allCases.allSatisfy {
                store.isComplete(for: "existing-user", surface: $0)
            }
        )
        XCTAssertEqual(completionCount, 1)

        coordinator.dismissEntireWalkthrough()
        XCTAssertEqual(completionCount, 1)

        let nextLaunch = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: store
        )
        nextLaunch.registerLaunch()
        nextLaunch.presentLaunchLessonIfEligible()
        nextLaunch.activate(.map)
        XCTAssertFalse(nextLaunch.isPresentingLaunchLesson)
        XCTAssertNil(nextLaunch.activeSurface)
    }

    func testDismissDuringContactInviteRetiresInsteadOfAdvancingTheWalkthrough() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: store
        )

        coordinator.forceActivate(.feedInvite)
        coordinator.advancePassiveStep()
        XCTAssertTrue(coordinator.isRequestingContactInvite)

        coordinator.dismissEntireWalkthrough()
        coordinator.completeContactInviteRequest()

        XCTAssertFalse(coordinator.isRequestingContactInvite)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "existing-user"))
    }

    func testCompletedEntireNuxRetiresAccountEligibility() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        for surface in WalkthroughSurface.allCases
            where !FirstVisitWalkthroughContent.suppressedSurfaces.contains(surface) {
            store.markComplete(for: "new-user", surface: surface)
        }
        store.markImportLessonComplete(for: "new-user")
        store.markDeviceFeaturesLessonComplete(for: "new-user")
        var completionCount = 0
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "new-user",
            store: store,
            onCompleted: { completionCount += 1 }
        )

        coordinator.registerLaunch()
        coordinator.registerLaunch()

        XCTAssertEqual(completionCount, 1)
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
        XCTAssertEqual(coordinator.currentStep?.target, .addClose)

        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .addClose)

        coordinator.perform(.addClose)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertEqual(coordinator.requestedSurface, .map)
    }

    func testProgressResumesPerUserAndPerSurface() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let ryan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        ryan.activate(.feed)
        ryan.advancePassiveStep()
        XCTAssertEqual(ryan.currentStep?.target, .feedDiscoverSearch)

        ryan.activate(.profile)
        XCTAssertEqual(ryan.currentStep?.target, .profileShare)

        let resumedRyan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        resumedRyan.activate(.feed)
        XCTAssertEqual(resumedRyan.currentStep?.target, .feedDiscoverSearch)

        let joe = FirstVisitWalkthroughCoordinator(userID: "joe", store: store)
        joe.activate(.feed)
        XCTAssertEqual(joe.currentStep?.target, .feedActivity)
    }

    func testCompletedSurfaceDoesNotAppearAgain() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        coordinator.activate(.feedSearch)
        coordinator.advancePassiveStep()
        coordinator.perform(.feedSmartSearch)
        coordinator.perform(.feedSearchResultsBack)
        coordinator.perform(.feedSearchExitBack)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertEqual(coordinator.requestedSurface, .feed)

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
            FirstVisitWalkthroughStore(defaults: defaults)
                .isComplete(for: "ryan", surface: .lists)
        )
    }

    func testProfileUsesFourClearPageAutoAdvancingLessonsWithoutBackControls() throws {
        let profileSteps = try XCTUnwrap(
            FirstVisitWalkthroughContent.stepsBySurface[.profile]
        )
        XCTAssertEqual(profileSteps.count, 4)
        XCTAssertTrue(profileSteps.allSatisfy { $0.spotlightStyle == .clearPage })
        XCTAssertTrue(profileSteps.allSatisfy(\.automaticallyAdvances))
        XCTAssertTrue(profileSteps.allSatisfy { !$0.allowsBackNavigation })
        XCTAssertLessThan(
            profileSteps.count * FirstVisitWalkthroughContent.profileAutoAdvanceDelayMilliseconds,
            15_000
        )

        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.profile)
        XCTAssertFalse(coordinator.canGoBack)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .profileActivity)
        XCTAssertTrue(coordinator.canGoBack)
        XCTAssertFalse(coordinator.currentStep?.allowsBackNavigation ?? true)
    }

    func testDiscoverActionsRequireTheirHighlightedTapWithoutOfferingCoachBack() throws {
        let launcher = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedDiscoverSearch }
        )

        XCTAssertEqual(launcher.advance, .action)
        XCTAssertTrue(launcher.allowsTargetInteraction)
        XCTAssertFalse(launcher.allowsBackNavigation)

        for target in [
            WalkthroughTargetID.feedSmartSearch,
            .feedSearchResultsBack,
            .feedSearchExitBack
        ] {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .action)
            XCTAssertTrue(step.allowsTargetInteraction)
            XCTAssertFalse(step.allowsBackNavigation)
        }
    }

    func testFullListsLessonsStayRetainedButSuppressed() throws {
        XCTAssertEqual(
            FirstVisitWalkthroughContent.suppressedListsStepsBySurface[.lists]?.map(\.target),
            [.listsCreate, .listsScope, .listsOpenPlan]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.suppressedListsStepsBySurface[.listDetail]?.map(\.target),
            [.listMap, .listMapPlace]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.suppressedListsStepsBySurface[.listEditor]?.map(\.target),
            [.listEditorTitle, .listEditorCollaborators, .listEditorPrivacy]
        )

        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.listDetail)
        XCTAssertNil(coordinator.activeSurface)
        coordinator.activate(.listEditor)
        XCTAssertNil(coordinator.activeSurface)
    }

    func testListsUsesTwoClearPageAutoAdvancingLessonsThenRoutesToProfile() throws {
        let listSteps = try XCTUnwrap(FirstVisitWalkthroughContent.stepsBySurface[.lists])
        XCTAssertEqual(listSteps.map(\.spotlightStyle), [.clearPage, .clearPage])
        XCTAssertEqual(listSteps.map(\.automaticallyAdvances), [true, true])
        XCTAssertEqual(listSteps.map(\.allowsBackNavigation), [false, false])

        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.lists)
        coordinator.recoverUnavailableTarget(.listsOpenPlan)
        XCTAssertEqual(coordinator.currentStep?.target, .listsScope)

        coordinator.recoverUnavailableTarget(.listsCreate)
        XCTAssertEqual(coordinator.currentStep?.target, .listsScope)

        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .listsOpenPlan)
        XCTAssertNil(coordinator.requestedSurface)

        coordinator.advancePassiveStep()
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertEqual(coordinator.requestedSurface, .profile)
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

    func testInterruptedImportLessonResumesBeforeTheDeviceLesson() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)

        let firstLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        firstLaunch.registerLaunch()

        let interruptedSecondLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store
        )
        interruptedSecondLaunch.registerLaunch()
        interruptedSecondLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(interruptedSecondLaunch.isPresentingImportLesson)

        let thirdLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        thirdLaunch.registerLaunch()
        thirdLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(thirdLaunch.isPresentingImportLesson)
        XCTAssertFalse(thirdLaunch.isPresentingDeviceFeaturesLesson)
        thirdLaunch.completeImportLesson()

        let fourthLaunch = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        fourthLaunch.registerLaunch()
        fourthLaunch.presentLaunchLessonIfEligible()
        XCTAssertFalse(fourthLaunch.isPresentingImportLesson)
        XCTAssertTrue(fourthLaunch.isPresentingDeviceFeaturesLesson)
    }

    func testImportLessonMatchesTheAdaptiveBuild124ReviewFlow() {
        XCTAssertEqual(ImportWalkthroughContent.actionTitle, "Open import form")
        XCTAssertEqual(
            ImportWalkthroughContent.helpURL.absoluteString,
            "https://getrec.me/import-help"
        )
        XCTAssertTrue(ImportWalkthroughContent.message.contains("one place, a few links, or a whole list"))
        XCTAssertTrue(ImportWalkthroughContent.message.contains("Check In or Wanna"))
        XCTAssertTrue(ImportWalkthroughContent.message.contains("before anything reaches your map"))
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
        coordinator.perform(.mapAdd)
        coordinator.perform(.mapAddAgain)
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.requestedSurface, .feed)

        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.placeDetail)
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.requestedSurface, .map)

        coordinator.consumeRequestedSurface(.map)
        coordinator.activate(.feed)
        XCTAssertEqual(coordinator.currentStep?.target, .feedActivity)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .feedDiscoverSearch)
        coordinator.perform(.feedDiscoverSearch)
        XCTAssertEqual(coordinator.currentStep?.target, .feedPeopleSearch)

        coordinator.activate(.feedSearch)
        coordinator.advancePassiveStep()
        coordinator.perform(.feedSmartSearch)
        XCTAssertEqual(coordinator.currentStep?.target, .feedSearchResultsBack)
        coordinator.perform(.feedSearchResultsBack)
        XCTAssertEqual(coordinator.currentStep?.target, .feedSearchExitBack)
        coordinator.perform(.feedSearchExitBack)
        XCTAssertEqual(coordinator.requestedSurface, .feed)

        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.feed)
        XCTAssertEqual(coordinator.currentStep?.target, .feedPeopleSearch)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .feedInvite)
        coordinator.advancePassiveStep()
        XCTAssertTrue(coordinator.isRequestingContactInvite)
        XCTAssertEqual(coordinator.currentStep?.target, .feedInvite)
        coordinator.completeContactInviteRequest()
        XCTAssertEqual(coordinator.requestedSurface, .lists)

        coordinator.consumeRequestedSurface(.lists)
        coordinator.activate(.lists)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .listsOpenPlan)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.requestedSurface, .profile)

        coordinator.consumeRequestedSurface(.profile)
        coordinator.activate(.profile)
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.requestedSurface, .sendoff)

        coordinator.consumeRequestedSurface(.sendoff)
        coordinator.activate(.sendoff)
        XCTAssertEqual(coordinator.currentStep?.target, .mapSendoff)
        coordinator.advancePassiveStep()
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.requestedSurface)
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

    func testScrimRenderingDimsEveryEdgeAndCutsOutOnlyTheSpotlight() throws {
        let size = CGSize(width: 100, height: 100)
        let spotlight = CGRect(x: 30, y: 30, width: 40, height: 40)
        let renderer = ImageRenderer(
            content: WalkthroughScrim(
                spotlightFrame: spotlight,
                containerSize: size
            )
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.cgImage)
        let pixels = try rgbaPixels(from: image)

        for point in [
            CGPoint(x: 1, y: 1),
            CGPoint(x: 98, y: 1),
            CGPoint(x: 1, y: 98),
            CGPoint(x: 98, y: 98)
        ] {
            XCTAssertGreaterThan(pixels.alpha(at: point), 150, "Expected scrim at \(point)")
        }

        XCTAssertLessThan(pixels.alpha(at: CGPoint(x: 50, y: 50)), 10)
    }

    func testTutorialSaveIsRememberedOnlyDuringTheSaveWalkthrough() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.recordTutorialSave(userPlaceID: "outside-walkthrough")
        XCTAssertNil(coordinator.tutorialUserPlaceID)

        coordinator.activate(.saveFlow)
        coordinator.recordTutorialSave(userPlaceID: "tutorial-save")
        XCTAssertEqual(coordinator.tutorialUserPlaceID, "tutorial-save")
    }

    func testPlaceMemoryUsesOnlyTheTutorialSaveAcrossLocalAndServerIdentifiers() {
        let owner = LocalProfile(
            localID: "owner",
            handle: "owner",
            displayName: "Owner"
        )
        let older = makeVisiblePlace(
            id: "older",
            owner: owner,
            status: .been,
            savedAt: Date(timeIntervalSince1970: 10)
        )
        let tutorial = makeVisiblePlace(
            id: "tutorial",
            owner: owner,
            status: .been,
            savedAt: Date(timeIntervalSince1970: 20),
            serverID: "server-tutorial"
        )

        XCTAssertEqual(
            MapWalkthroughMemoryPolicy.preferredVisiblePlace(
                from: [older, tutorial],
                tutorialUserPlaceID: tutorial.userPlace.localID,
                currentUserID: owner.id
            )?.userPlace.id,
            tutorial.userPlace.id
        )
        XCTAssertEqual(
            MapWalkthroughMemoryPolicy.preferredVisiblePlace(
                from: [older, tutorial],
                tutorialUserPlaceID: tutorial.userPlace.serverID,
                currentUserID: owner.id
            )?.userPlace.id,
            tutorial.userPlace.id
        )
        XCTAssertNil(
            MapWalkthroughMemoryPolicy.preferredVisiblePlace(
                from: [older, tutorial],
                tutorialUserPlaceID: nil,
                currentUserID: owner.id
            )
        )
        XCTAssertNil(
            MapWalkthroughMemoryPolicy.preferredVisiblePlace(
                from: [older, tutorial],
                tutorialUserPlaceID: "missing-save",
                currentUserID: owner.id
            )
        )
    }

    func testDisplayOnlyWalkthroughNoteDoesNotMutateTheSavedPlace() {
        let owner = LocalProfile(
            localID: "owner",
            handle: "owner",
            displayName: "Owner"
        )
        let savedPlace = makeVisiblePlace(
            id: "tutorial",
            owner: owner,
            status: .been,
            savedAt: Date(timeIntervalSince1970: 20)
        )
        let displayNote = "Worth remembering—and an easy place to recommend when someone asks."

        XCTAssertNil(savedPlace.userPlace.note)

        let summary = PlaceSaveSummary(
            visiblePlace: savedPlace,
            attributes: [],
            displayNoteOverride: displayNote
        )

        XCTAssertEqual(summary.displayNoteOverride, displayNote)
        XCTAssertNil(savedPlace.userPlace.note)
    }

    func testPlaceMemoryFallbackLooksLikeARealCheckIn() {
        let owner = LocalProfile(
            localID: "owner",
            handle: "owner",
            displayName: "Owner"
        )

        let fallback = MapWalkthroughMemoryPolicy.realisticFallback(owner: owner)

        XCTAssertEqual(fallback.place.canonicalName, "Kirk Creek Campground")
        XCTAssertEqual(fallback.place.primaryCategory, WanderPlaceCategory.outdoorsNature)
        XCTAssertEqual(fallback.userPlace.status, .been)
        XCTAssertEqual(fallback.userPlace.ratingScore, 4.5)
        XCTAssertEqual(fallback.userPlace.recommendedScore, 4.5)
        XCTAssertFalse(try XCTUnwrap(fallback.userPlace.note).isEmpty)
        XCTAssertEqual(fallback.owner.id, owner.id)
        XCTAssertTrue(MapWalkthroughMemoryPolicy.supportsFullPlaceCardTour(fallback))
        XCTAssertNotNil(fallback.place.websiteURLString)
        XCTAssertNotNil(fallback.place.phoneNumber)
        XCTAssertTrue(
            PlaceActionLink.decode(fallback.place.actionLinksJSON).contains {
                $0.kind == .reserve && $0.confidence == .exact
            }
        )
    }

    private func rgbaPixels(from image: CGImage) throws -> RGBAPixels {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAPixels(bytes: bytes, width: width, height: height)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "FirstVisitWalkthroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeVisiblePlace(
        id: String,
        owner: LocalProfile,
        status: PlaceStatus,
        savedAt: Date,
        serverID: String? = nil
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "place-\(id)",
            canonicalName: id.capitalized,
            category: "coffee",
            latitude: 34.0,
            longitude: -118.0
        )
        let userPlace = LocalUserPlace(
            localID: "user-place-\(id)",
            serverID: serverID,
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            savedAt: savedAt,
            sourceType: "test"
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner
        )
    }
}

private struct RGBAPixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    func alpha(at point: CGPoint) -> UInt8 {
        let x = min(max(Int(point.x), 0), width - 1)
        let y = min(max(Int(point.y), 0), height - 1)
        return bytes[((y * width) + x) * 4 + 3]
    }
}
