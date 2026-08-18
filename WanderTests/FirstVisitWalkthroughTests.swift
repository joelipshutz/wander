import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class FirstVisitWalkthroughTests: XCTestCase {
    func testEveryMapSourceRegistersItsOwnWalkthroughTarget() {
        XCTAssertEqual(MapSource.featured.walkthroughTarget, .mapFeatured)
        XCTAssertEqual(MapSource.friends.walkthroughTarget, .mapFriends)
        XCTAssertEqual(MapSource.you.walkthroughTarget, .mapYou)
    }

    func testWalkthroughAddSheetOnlyExpandsWhenCandidateResultsOverflow() {
        XCTAssertFalse(AddSuggestedPlaces.walkthroughRequiresExpansion(candidateCount: 0))
        XCTAssertFalse(AddSuggestedPlaces.walkthroughRequiresExpansion(candidateCount: 3))
        XCTAssertTrue(AddSuggestedPlaces.walkthroughRequiresExpansion(candidateCount: 4))
    }

    func testCondensedWalkthroughKeepsDormantLessonsButLimitsTheLiveJourney() {
        XCTAssertEqual(FirstVisitWalkthroughContent.allSteps.count, 26)
        XCTAssertEqual(
            Set(FirstVisitWalkthroughContent.stepsBySurface.keys),
            Set(WalkthroughSurface.allCases)
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.map]?.map(\.target),
            [.mapAdd, .mapAddAgain]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.sendoff]?.map(\.target),
            [.mapSendoff]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.add]?.map(\.target),
            [.addSearch, .addImport]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.saveFlow]?.map(\.target),
            [
                .saveStatus,
                .saveContinue,
                .saveDate,
                .saveNote,
                .saveRating,
                .saveMoreOptions,
                .saveQuestions,
                .saveTags,
                .saveSubmit
            ]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.feed]?.map(\.target),
            [.feedActivity, .feedDiscoverSearch, .feedPeopleSearch, .feedInvite]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.feedSearch]?.map(\.target),
            [.feedSearchField, .feedSmartSearch, .feedSearchResultsBack]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.lists]?.map(\.target),
            [.listsScope, .listsOpenPlan]
        )
        XCTAssertEqual(
            FirstVisitWalkthroughContent.stepsBySurface[.profile]?.map(\.target),
            []
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
        XCTAssertEqual(
            FirstVisitWalkthroughContent.primaryJourneySurfaces,
            [.map, .add, .saveFlow, .sendoff]
        )
        XCTAssertTrue(
            Set([WalkthroughSurface.feed, .feedSearch, .lists, .placeDetail])
                .isSubset(of: FirstVisitWalkthroughContent.suppressedSurfaces)
        )
    }

    func testRequestedExplanationStepsAdvanceWithNext() throws {
        let passiveTargets: [WalkthroughTargetID] = [
            .addImport,
            .feedActivity,
            .feedPeopleSearch,
            .feedInvite,
            .feedSearchField,
            .placeRatings,
            .placeActions,
            .placeHistory,
            .listsScope,
            .listsOpenPlan,
            .mapSendoff
        ]

        for target in passiveTargets {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .next, "Expected \(target) to show Next")
        }

        for target in [
            WalkthroughTargetID.addSearch,
            .saveDate,
            .saveNote,
            .saveRating,
            .saveMoreOptions,
            .saveQuestions,
            .saveTags,
            .saveSubmit
        ] {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .action)
        }
    }

    func testPassiveEditableLessonsAllowInteractionWithoutRequiringIt() throws {
        let editableTargets: [WalkthroughTargetID] = [.feedPeopleSearch]

        for target in editableTargets {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .next)
            XCTAssertTrue(step.allowsTargetInteraction, "Expected \(target) to remain editable")
        }

        for target in [
            WalkthroughTargetID.addImport,
            .addSearch,
            .saveDate,
            .saveNote,
            .saveRating,
            .saveMoreOptions,
            .saveQuestions,
            .saveTags,
            .saveSubmit,
            .feedActivity,
            .feedInvite,
            .feedSearchField,
            .listsScope,
            .listsOpenPlan,
            .mapTabs,
            .placeRatings,
            .placeActions,
            .placeHistory
        ] {
            let step = try XCTUnwrap(
                (FirstVisitWalkthroughContent.allSteps
                    + FirstVisitWalkthroughContent.suppressedMapExplorationSteps)
                    .first { $0.target == target }
            )
            XCTAssertFalse(step.allowsTargetInteraction, "Expected \(target) to be explanation-only")
        }

        let memoryStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapMemory }
        )
        XCTAssertTrue(memoryStep.allowsTargetInteraction)
        XCTAssertFalse(memoryStep.allowsBackNavigation)
    }

    func testFinalSendoffReturnsToMapWithMotivatingAction() throws {
        let step = try XCTUnwrap(
            FirstVisitWalkthroughContent.stepsBySurface[.sendoff]?.first
        )

        XCTAssertEqual(step.target, .mapSendoff)
        XCTAssertEqual(step.title, "Your map is yours now")
        XCTAssertEqual(step.nextButtonTitle, "Finish")
        XCTAssertEqual(step.advance, .next)
        XCTAssertEqual(step.spotlightStyle, .clearPage)
        XCTAssertEqual(step.presentationStyle, .finale)
    }

    func testBottomNavigationCopyExplainsTheConnectedProduct() throws {
        let step = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapTabs }
        )

        XCTAssertEqual(step.title, "Your places, all connected")
        XCTAssertEqual(
            step.message,
            "Map, Feed, Lists, and Profile work together to help you find, plan, and remember"
        )
    }

    func testMapFilterAndDiscoverSearchLessonsMatchSupportedBehavior() throws {
        let featured = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapFeatured }
        )
        let friends = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapFriends }
        )
        let you = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapYou }
        )
        let more = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapMoreFilters }
        )
        let searchField = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedSearchField }
        )
        let feedActivity = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedActivity }
        )

        XCTAssertEqual(featured.title, MapSource.featured.subtitle)
        XCTAssertTrue(featured.message.isEmpty)
        XCTAssertEqual(friends.title, MapSource.friends.subtitle)
        XCTAssertTrue(friends.message.isEmpty)
        XCTAssertEqual(you.title, "Only your Check Ins and Wanna places")
        XCTAssertTrue(you.message.isEmpty)
        XCTAssertTrue(more.message.contains("category"))
        XCTAssertTrue(more.message.contains("specific friends"))
        XCTAssertTrue(more.message.contains("check-in"))
        XCTAssertTrue(more.message.contains("wanna go"))
        XCTAssertTrue(searchField.message.contains("category"))
        XCTAssertTrue(searchField.message.contains("neighborhood"))
        XCTAssertTrue(searchField.message.contains("@handle"))
        XCTAssertTrue(searchField.message.contains("saved tag"))
        XCTAssertEqual(feedActivity.title, "See your friend's check-ins in real time")
        XCTAssertEqual(
            feedActivity.message,
            "Interact with your trusted feed with a like, comment, or share"
        )
    }

    func testRevisedCoachCopyIsCompactAndPeriodFree() throws {
        XCTAssertTrue(
            FirstVisitWalkthroughContent.allSteps.allSatisfy { step in
                step.message.last != "."
            }
        )
        XCTAssertEqual(FirstVisitWalkthroughContent.nextArrowNudgeDelayMilliseconds, 3_000)

        let importStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .addImport }
        )
        XCTAssertEqual(
            importStep.message,
            "Import your places and lists from Google Maps, Instagram, Tiktok, and more here"
        )

        let memoryStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.suppressedMapExplorationSteps.first { $0.target == .mapMemory }
        )
        XCTAssertEqual(
            memoryStep.message,
            "Tap the highlighted place to revisit everything you just saved"
        )

        let ratingStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .placeRatings }
        )
        XCTAssertEqual(
            ratingStep.message,
            "Your rating is the average of your check-ins. rec.me rating averages your network's ratings. And fit score predicts how well this place matches your taste"
        )

        let historyStep = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .placeHistory }
        )
        XCTAssertTrue(historyStep.message.contains("left or right breaking?"))
        XCTAssertTrue(historyStep.message.contains("dates, ratings, notes, photos, friends, and tags"))
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
        XCTAssertNil(coordinator.currentStep)
        XCTAssertEqual(coordinator.requestedSurface, .add)
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
                forKey: "wander.walkthrough.existing-user.authenticatedLaunchCount"
            ),
            0
        )
    }

    func testTransientFlagDisableDoesNotCountTheSamePhysicalLaunchTwice() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )

        coordinator.registerLaunch()
        coordinator.setEnabled(false)
        coordinator.setEnabled(true)
        coordinator.registerLaunch()
        coordinator.presentLaunchLessonIfEligible()

        XCTAssertFalse(coordinator.isPresentingImportLesson)
        XCTAssertFalse(coordinator.isPresentingDeviceFeaturesLesson)

        let nextPhysicalLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        nextPhysicalLaunch.registerLaunch()
        nextPhysicalLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(nextPhysicalLaunch.isPresentingImportLesson)
    }

    func testAccountSwitchingDoesNotCountTheSamePhysicalLaunchTwiceForReturningAccount() throws {
        let defaults = try makeDefaults()
        let launchRegistry = FirstVisitWalkthroughLaunchRegistry()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "user-a",
            store: store,
            launchRegistry: launchRegistry
        )

        coordinator.registerLaunch()
        coordinator.setUserID("user-b")
        coordinator.registerLaunch()
        coordinator.setUserID("user-a")
        coordinator.registerLaunch()

        let reconstructedCoordinator = FirstVisitWalkthroughCoordinator(
            userID: "user-a",
            store: store,
            launchRegistry: launchRegistry
        )
        reconstructedCoordinator.registerLaunch()

        XCTAssertEqual(
            defaults.integer(
                forKey: "wander.walkthrough.user-a.authenticatedLaunchCount"
            ),
            1
        )
        XCTAssertEqual(
            defaults.integer(
                forKey: "wander.walkthrough.user-b.authenticatedLaunchCount"
            ),
            1
        )
    }

    func testDebugResetAllowsAUserToRegisterAgainInTheCurrentProcess() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )

        coordinator.registerLaunch()
        coordinator.resetCurrentUser()
        coordinator.registerLaunch()

        XCTAssertEqual(
            defaults.integer(
                forKey: "wander.walkthrough.ryan.authenticatedLaunchCount"
            ),
            1
        )
    }

    func testDebugReplayClearsStaleDownstreamJourneyCompletion() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )

        store.markComplete(for: "ryan", surface: .feed)
        store.markComplete(for: "ryan", surface: .feedSearch)
        store.markComplete(for: "ryan", surface: .lists)

        coordinator.prepareDebugReplay(at: .mapAdd)

        XCTAssertEqual(coordinator.currentStep?.target, .mapAdd)
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .feed))
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .feedSearch))
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .lists))
    }

    func testFeedDiscoverListsAndPlaceDetailWalkthroughsCannotActivate() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        for surface in [WalkthroughSurface.feed, .feedSearch, .lists, .placeDetail] {
            coordinator.transition(to: surface)
            XCTAssertNil(coordinator.activeSurface, "Expected \(surface) to stay suppressed")
            XCTAssertNil(coordinator.currentStep)
        }

        for target in [
            WalkthroughTargetID.feedActivity,
            .feedSearchField,
            .listsScope,
            .placeRatings
        ] {
            coordinator.forceActivate(target)
            XCTAssertNil(coordinator.activeSurface, "Forced target \(target) must not bypass suppression")
            XCTAssertNil(coordinator.currentStep)
        }
    }

    func testTrustedSearchBackTargetRemainsAnchoredWhileSignedInResultsAreStillLoading() {
        XCTAssertEqual(
            DiscoverWalkthroughTargetPolicy.searchBackTarget(
                activeSurface: .feedSearch,
                target: .feedSearchResultsBack
            ),
            .feedSearchResultsBack,
            "A slow live search must not make the NUX target disappear before the user can return to Feed."
        )
        XCTAssertNil(
            DiscoverWalkthroughTargetPolicy.searchBackTarget(
                activeSurface: .feed,
                target: .feedSearchResultsBack
            )
        )
    }

    func testAutomaticWalkthroughTimingUsesAnAverageReadingBeat() {
        let shortDelay = FirstVisitWalkthroughContent
            .automaticReadingDelayMilliseconds(for: .saveDate)
        let longerDelay = FirstVisitWalkthroughContent
            .automaticReadingDelayMilliseconds(for: .saveMoreOptions)

        XCTAssertGreaterThanOrEqual(shortDelay, 2_800)
        XCTAssertGreaterThan(longerDelay, shortDelay)
        XCTAssertLessThanOrEqual(longerDelay, 6_500)
    }

    func testCalendarDemoDoesNotOfferBackNavigation() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        coordinator.forceActivate(.saveStatus)
        coordinator.recordTutorialSelectedStatus(.been)
        coordinator.perform(.saveStatus)
        coordinator.perform(.saveContinue)
        XCTAssertEqual(coordinator.currentStep?.target, .saveDate)
        XCTAssertFalse(coordinator.canGoBack)
        XCTAssertFalse(try XCTUnwrap(coordinator.currentStep).allowsBackNavigation)

        coordinator.goBack()

        XCTAssertEqual(coordinator.currentStep?.target, .saveDate)
        XCTAssertEqual(coordinator.tutorialSelectedStatus, .been)
        XCTAssertEqual(store.checkpoint(for: "ryan")?.target, .saveDate)
    }

    func testImportStepRoutesStraightToTheBourdainSendoff() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.forceActivate(.addImport)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)
        coordinator.advancePassiveStep()

        XCTAssertEqual(coordinator.requestedSurface, .sendoff)
        XCTAssertNil(coordinator.activeSurface)
    }

    func testSuppressedCheckpointRetiresInsteadOfReenteringFeedOrLists() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .feedActivity,
                updatedAt: .now,
                tutorialCandidate: nil,
                tutorialUserPlaceID: nil,
                tutorialMemorySnapshot: nil
            ),
            for: "ryan"
        )
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store
        )

        XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .expired)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "ryan"))
    }

    func testTransientFlagDisablePreservesSecondAndThirdLaunchLessons() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)

        let firstLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        firstLaunch.registerLaunch()

        let secondLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        secondLaunch.registerLaunch()
        secondLaunch.setEnabled(false)
        secondLaunch.setEnabled(true)
        secondLaunch.registerLaunch()
        secondLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(secondLaunch.isPresentingImportLesson)
        XCTAssertFalse(secondLaunch.isPresentingDeviceFeaturesLesson)
        secondLaunch.completeImportLesson()

        let thirdLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        thirdLaunch.registerLaunch()
        thirdLaunch.setEnabled(false)
        thirdLaunch.setEnabled(true)
        thirdLaunch.registerLaunch()
        XCTAssertEqual(thirdLaunch.restoreJourneyIfNeeded(), .resumed(.map))
        XCTAssertFalse(thirdLaunch.isPresentingImportLesson)
        XCTAssertTrue(thirdLaunch.isPresentingDeviceFeaturesLesson)
    }

    func testPassiveStepUserActivityResetsTheIdleGeneration() throws {
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: try makeDefaults())
        )

        coordinator.forceActivate(.mapSendoff)
        let initialGeneration = coordinator.userActivityGeneration
        coordinator.recordUserActivity()
        XCTAssertEqual(coordinator.userActivityGeneration, initialGeneration + 1)

        coordinator.forceActivate(.saveDate)
        coordinator.recordUserActivity()
        XCTAssertEqual(coordinator.userActivityGeneration, initialGeneration + 1)
    }

    func testEligibilityResolutionPendingStateIsExplicitAndReversible() {
        let coordinator = FirstVisitWalkthroughCoordinator(isEnabled: false)

        XCTAssertFalse(coordinator.isAwaitingEligibilityResolution)
        coordinator.setEligibilityResolutionPending(true)
        XCTAssertTrue(coordinator.isAwaitingEligibilityResolution)
        coordinator.setEligibilityResolutionPending(false)
        XCTAssertFalse(coordinator.isAwaitingEligibilityResolution)
    }

    func testCoordinatorCanEnableAfterRemoteResolutionAndStopsWhenDisabled() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "remote-user",
            store: store,
            isEnabled: false
        )

        coordinator.forceActivate(.mapAdd)
        XCTAssertNil(coordinator.currentStep)

        coordinator.setEnabled(true)
        coordinator.forceActivate(.mapAdd)
        XCTAssertEqual(coordinator.currentStep?.target, .mapAdd)

        coordinator.setEnabled(false)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(coordinator.isPresentingLaunchLesson)
        XCTAssertFalse(store.isComplete(for: "remote-user", surface: .map))
    }

    func testWalkthroughWaitsForRemoteFlagAndSupportsExplicitTestOverride() {
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: nil
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: false
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: true
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: false,
                launchArguments: [],
                resolvedValue: true
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: true
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: false,
                launchArguments: ["-WanderEnableWalkthroughs"],
                resolvedValue: nil
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [
                    "-WanderEnableWalkthroughs",
                    "-WanderDisableWalkthroughs"
                ],
                resolvedValue: true
            ),
            "The DEBUG disable argument must isolate non-NUX UI tests from persisted replay state."
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: ["-WanderEnableWalkthroughs"],
                resolvedValue: false,
                allowsLaunchOverride: false
            )
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: false,
                isEntitledDebugReplayRequested: true,
                allowsLaunchOverride: false
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: false,
                entitledDebugOverride: true,
                isEntitledDebugReplayRequested: true,
                isExplicitlyDisabledForAccount: true,
                allowsLaunchOverride: false
            ),
            "An explicit account disable must win over persisted debug replay state."
        )
        XCTAssertTrue(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: false,
                isUsingLiveData: true,
                launchArguments: ["-WanderEnableWalkthroughs"],
                resolvedValue: false,
                isEntitledDebugReplayRequested: true,
                isExplicitlyDisabledForAccount: true,
                allowsLaunchOverride: true
            ),
            "The DEBUG-only launch argument remains available for an intentional device test."
        )
        XCTAssertFalse(
            FirstVisitWalkthroughFeatureFlag.isEnabled(
                isEligible: true,
                isUsingLiveData: true,
                launchArguments: [],
                resolvedValue: true,
                entitledDebugOverride: false,
                allowsLaunchOverride: false
            ),
            "An entitled account-level debug disable must override a remotely enabled NUX."
        )
    }

    func testDebugPreferencesAreAccountScopedAndReplayResetsOnlyThatAccount() throws {
        let defaults = try makeDefaults()
        let walkthroughStore = FirstVisitWalkthroughStore(defaults: defaults)
        let preferences = FirstVisitWalkthroughDebugPreferences(defaults: defaults)
        let launchRegistry = FirstVisitWalkthroughLaunchRegistry()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "user_a",
            store: walkthroughStore,
            launchRegistry: launchRegistry
        )

        walkthroughStore.setProgress(2, for: "user_a", surface: .map)
        walkthroughStore.markComplete(for: "user_a", surface: .map)
        walkthroughStore.markComplete(for: "user_b", surface: .map)
        coordinator.registerLaunch()
        XCTAssertNil(preferences.nuxOverride(for: "user_a"))
        XCTAssertNil(preferences.nuxOverride(for: "user_b"))

        preferences.setNUXEnabled(
            true,
            for: "user_a",
            launchRegistry: launchRegistry
        )
        coordinator.registerLaunch()

        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), true)
        XCTAssertTrue(preferences.isReplayRequested(for: "user_a"))
        XCTAssertEqual(walkthroughStore.progress(for: "user_a", surface: .map), 0)
        XCTAssertFalse(walkthroughStore.isComplete(for: "user_a", surface: .map))
        XCTAssertNil(preferences.nuxOverride(for: "user_b"))
        XCTAssertFalse(preferences.isReplayRequested(for: "user_b"))
        XCTAssertTrue(walkthroughStore.isComplete(for: "user_b", surface: .map))
        XCTAssertEqual(
            defaults.integer(
                forKey: "wander.walkthrough.user_a.authenticatedLaunchCount"
            ),
            1
        )

        preferences.clearReplayRequest(for: "user_a")
        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), true)
        XCTAssertFalse(preferences.isReplayRequested(for: "user_a"))

        preferences.setNUXEnabled(false, for: "user_a")
        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), false)
        XCTAssertFalse(preferences.isReplayRequested(for: "user_a"))
    }

    func testDismissPermanentlyCompletesEveryWalkthroughForTheCurrentAccount() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        var completionCount = 0
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry(),
            onCompleted: { _ in completionCount += 1 }
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
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        nextLaunch.registerLaunch()
        nextLaunch.presentLaunchLessonIfEligible()
        nextLaunch.activate(.map)
        XCTAssertFalse(nextLaunch.isPresentingLaunchLesson)
        XCTAssertNil(nextLaunch.activeSurface)
    }

    func testCompletionCallbackUsesTheCoordinatorCurrentAccount() throws {
        let defaults = try makeDefaults()
        var completedUserIDs: [String] = []
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "user-a",
            store: FirstVisitWalkthroughStore(defaults: defaults),
            onCompleted: { completedUserIDs.append($0) }
        )

        coordinator.setUserID("user-b")
        coordinator.dismissEntireWalkthrough()

        XCTAssertEqual(completedUserIDs, ["user-b"])
    }

    func testSuppressedContactInviteCannotPresent() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "existing-user",
            store: store
        )

        coordinator.forceActivate(.feedInvite)
        coordinator.advancePassiveStep()
        XCTAssertFalse(coordinator.isRequestingContactInvite)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertFalse(store.hasCompletedEntireWalkthrough(for: "existing-user"))
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
            launchRegistry: FirstVisitWalkthroughLaunchRegistry(),
            onCompleted: { _ in completionCount += 1 }
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
        coordinator.perform(.addSearch, transitioningTo: .saveFlow)
        coordinator.forceActivate(.addImport)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)

        coordinator.perform(.addImport)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)

        coordinator.advancePassiveStep()
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertEqual(coordinator.requestedSurface, .sendoff)
    }

    func testSuppressedSurfaceDoesNotPersistProgressForAnyUser() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let ryan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        ryan.activate(.feed)
        ryan.advancePassiveStep()
        XCTAssertNil(ryan.currentStep)

        let resumedRyan = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        resumedRyan.activate(.feed)
        XCTAssertNil(resumedRyan.currentStep)

        let joe = FirstVisitWalkthroughCoordinator(userID: "joe", store: store)
        joe.activate(.feed)
        XCTAssertNil(joe.currentStep)
    }

    func testSuppressedDiscoverSurfaceNeverAppears() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        coordinator.transition(to: .feedSearch)
        coordinator.advancePassiveStep()
        coordinator.perform(.feedSmartSearch)
        coordinator.perform(.feedSearchResultsBack)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertNil(coordinator.requestedSurface)

        coordinator.transition(to: .feedSearch)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .feedSearch))
    }

    func testContentVersionDoesNotRestartCompletedWalkthroughContent() throws {
        let defaults = try makeDefaults()
        let firstVersion = FirstVisitWalkthroughStore(defaults: defaults, version: 1)
        firstVersion.markComplete(for: "ryan", surface: .lists)

        XCTAssertTrue(firstVersion.isComplete(for: "ryan", surface: .lists))
        XCTAssertTrue(
            FirstVisitWalkthroughStore(defaults: defaults)
                .isComplete(for: "ryan", surface: .lists)
        )
    }

    func testLegacyVersionedCompletionAndLaunchStateMigratesWithoutReEnrollment() throws {
        let defaults = try makeDefaults()
        let userID = "existing-user"
        defaults.set(
            true,
            forKey: "wander.walkthrough.v11.\(userID).map.complete"
        )
        defaults.set(
            3,
            forKey: "wander.walkthrough.v11.\(userID).authenticatedLaunchCount"
        )
        defaults.set(
            true,
            forKey: "wander.walkthrough.v11.\(userID).importLesson.complete"
        )

        let store = FirstVisitWalkthroughStore(defaults: defaults, version: 12)

        XCTAssertTrue(store.isComplete(for: userID, surface: .map))
        XCTAssertEqual(store.registerLaunch(for: userID), 4)
        XCTAssertTrue(store.hasCompletedImportLesson(for: userID))
        XCTAssertNil(
            defaults.object(
                forKey: "wander.walkthrough.v11.\(userID).map.complete"
            )
        )
        XCTAssertNil(
            defaults.object(
                forKey: "wander.walkthrough.v11.\(userID).authenticatedLaunchCount"
            )
        )
    }

    func testJourneyCheckpointMigratesAcrossContentVersionsWithoutResettingItsAge() throws {
        let defaults = try makeDefaults()
        let userID = "ryan"
        let leftAt = Date(timeIntervalSince1970: 1_000_000)
        let legacyCheckpoint = FirstVisitWalkthroughCheckpoint(
            target: .saveRating,
            updatedAt: leftAt,
            tutorialCandidate: nil,
            tutorialUserPlaceID: nil,
            tutorialMemorySnapshot: nil
        )
        let data = try JSONEncoder().encode(legacyCheckpoint)
        defaults.set(
            data,
            forKey: "wander.walkthrough.v11.\(userID).journeyCheckpoint"
        )

        let currentStore = FirstVisitWalkthroughStore(defaults: defaults, version: 12)
        XCTAssertEqual(currentStore.checkpoint(for: userID), legacyCheckpoint)
        XCTAssertNil(
            defaults.data(forKey: "wander.walkthrough.v11.\(userID).journeyCheckpoint")
        )

        let coordinator = FirstVisitWalkthroughCoordinator(userID: userID, store: currentStore)
        XCTAssertEqual(
            coordinator.restoreJourneyIfNeeded(
                now: leftAt.addingTimeInterval(FirstVisitWalkthroughStore.resumeWindow)
            ),
            .expired
        )
        XCTAssertTrue(currentStore.hasCompletedEntireWalkthrough(for: userID))
    }

    func testJourneyRestoresExactTargetAndTutorialPlaceWithinTwelveHours() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let candidate = PlaceCandidate(
            id: "hotchkiss",
            name: "Hotchkiss Park",
            category: "Park",
            primaryCategory: WanderPlaceCategory.outdoorsNature,
            subcategory: "Park",
            address: "2302 Fourth St",
            locality: "Santa Monica",
            region: "CA",
            latitude: 34.0057,
            longitude: -118.4843,
            confidence: 1
        )
        let leftAt = Date(timeIntervalSince1970: 1_000_000)
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .saveRating,
                updatedAt: leftAt,
                tutorialCandidate: candidate,
                tutorialUserPlaceID: "saved-hotchkiss",
                tutorialMemorySnapshot: nil,
                tutorialSelectedStatus: .wannaGo,
                tutorialDiscoverQuery: "sunset parks with a view"
            ),
            for: "ryan"
        )

        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(
            coordinator.restoreJourneyIfNeeded(
                now: leftAt.addingTimeInterval(FirstVisitWalkthroughStore.resumeWindow - 1)
            ),
            .resumed(.saveFlow)
        )
        XCTAssertEqual(coordinator.currentStep?.target, .saveRating)
        XCTAssertEqual(coordinator.tutorialCandidate, candidate)
        XCTAssertEqual(coordinator.tutorialUserPlaceID, "saved-hotchkiss")
        XCTAssertEqual(coordinator.tutorialSelectedStatus, .wannaGo)
        XCTAssertEqual(coordinator.tutorialDiscoverQuery, "sunset parks with a view")

        coordinator.activate(.map)
        XCTAssertEqual(
            coordinator.currentStep?.target,
            .saveRating,
            "An underlying Map appearance must not overwrite the restored save-flow checkpoint"
        )
    }

    func testJourneyCheckpointPersistsInteractiveSaveAndDiscoverState() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)

        coordinator.transition(to: .saveFlow)
        coordinator.recordTutorialSelectedStatus(.been)
        coordinator.recordTutorialDiscoverQuery("  quiet parks with a view  ")
        coordinator.recordSuspension(at: Date(timeIntervalSince1970: 2_000_000))

        let checkpoint = try XCTUnwrap(store.checkpoint(for: "ryan"))
        XCTAssertEqual(checkpoint.target, .saveStatus)
        XCTAssertEqual(checkpoint.tutorialSelectedStatus, .been)
        XCTAssertEqual(checkpoint.tutorialDiscoverQuery, "quiet parks with a view")
    }

    func testJourneyExpiresAtTwelveHoursAndNeverReentersNUX() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let leftAt = Date(timeIntervalSince1970: 1_000_000)
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .feedPeopleSearch,
                updatedAt: leftAt,
                tutorialCandidate: nil,
                tutorialUserPlaceID: nil,
                tutorialMemorySnapshot: nil
            ),
            for: "joe"
        )

        let coordinator = FirstVisitWalkthroughCoordinator(userID: "joe", store: store)
        XCTAssertEqual(
            coordinator.restoreJourneyIfNeeded(
                now: leftAt.addingTimeInterval(FirstVisitWalkthroughStore.resumeWindow)
            ),
            .expired
        )
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(store.checkpoint(for: "joe"))
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "joe"))

        coordinator.activate(.map)
        XCTAssertNil(coordinator.activeSurface)
    }

    func testDefinitivelyDisabledExperienceRetiresCheckpointWithoutCompletionCallback() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let userID = "established-user"
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .saveRating,
                updatedAt: .now,
                tutorialCandidate: nil,
                tutorialUserPlaceID: nil,
                tutorialMemorySnapshot: nil
            ),
            for: userID
        )
        var completedUserIDs: [String] = []
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: userID,
            store: store,
            isEnabled: false,
            onCompleted: { completedUserIDs.append($0) }
        )

        coordinator.retireJourneyForDisabledExperience()

        XCTAssertNil(store.checkpoint(for: userID))
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: userID))
        XCTAssertFalse(coordinator.hasActivePresentation)
        XCTAssertTrue(completedUserIDs.isEmpty)
    }

    func testInterruptedImportResumesUntilTwelveHoursThenClearsItsOverlay() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let userID = "ryan"
        let leftAt = Date(timeIntervalSince1970: 1_000_000)
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .mapAdd,
                updatedAt: leftAt,
                tutorialCandidate: nil,
                tutorialUserPlaceID: nil,
                tutorialMemorySnapshot: nil,
                presentation: .importLesson
            ),
            for: userID
        )

        let coordinator = FirstVisitWalkthroughCoordinator(userID: userID, store: store)
        XCTAssertEqual(
            coordinator.restoreJourneyIfNeeded(now: leftAt.addingTimeInterval(1)),
            .resumed(.map)
        )
        XCTAssertTrue(coordinator.isPresentingImportLesson)

        XCTAssertEqual(
            coordinator.restoreJourneyIfNeeded(
                now: leftAt.addingTimeInterval(FirstVisitWalkthroughStore.resumeWindow)
            ),
            .expired
        )
        XCTAssertFalse(coordinator.isPresentingLaunchLesson)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: userID))
    }

    func testContactInvitePresentationCannotBypassSuppressedFeed() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.forceActivate(.feedInvite)
        coordinator.advancePassiveStep()
        coordinator.recordTutorialInvitedContactIDs(["maya", "nico"])

        XCTAssertFalse(coordinator.isRequestingContactInvite)
        XCTAssertNil(store.checkpoint(for: "ryan"))

        let restored = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(restored.restoreJourneyIfNeeded(), .none)
        XCTAssertNil(restored.currentStep)
        XCTAssertFalse(restored.isRequestingContactInvite)
        XCTAssertTrue(restored.tutorialInvitedContactIDs.isEmpty)
    }

    func testAutomatedSearchTransitionsDirectlyToDurableSaveStatusCheckpoint() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.forceActivate(.addSearch)

        coordinator.perform(.addSearch, transitioningTo: .saveFlow)

        XCTAssertEqual(coordinator.activeSurface, .saveFlow)
        XCTAssertEqual(coordinator.currentStep?.target, .saveStatus)
        XCTAssertEqual(store.checkpoint(for: "ryan")?.target, .saveStatus)
        let importIndex = try XCTUnwrap(
            FirstVisitWalkthroughContent.stepsBySurface[.add]?.firstIndex {
                $0.target == .addImport
            }
        )
        XCTAssertEqual(
            store.progress(for: "ryan", surface: .add),
            importIndex
        )
    }

    func testCorruptCheckpointRetiresInsteadOfRestartingTheWalkthrough() throws {
        let defaults = try makeDefaults()
        let userID = "ryan"
        defaults.set(
            Data("not-json".utf8),
            forKey: "wander.walkthrough.\(userID).journeyCheckpoint"
        )
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: userID, store: store)

        XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .expired)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: userID))
    }

    func testUncheckpointedShippedV10SessionRetiresInsteadOfRestarting() throws {
        let defaults = try makeDefaults()
        let userID = "existing-v10-user"
        defaults.set(
            1,
            forKey: "wander.walkthrough.v10.\(userID).map.progress"
        )
        let store = FirstVisitWalkthroughStore(defaults: defaults, version: 12)
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: userID,
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        coordinator.registerLaunch()

        XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .expired)
        coordinator.activate(.map)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: userID))
    }

    func testSuspensionRefreshesTheResumeWindowWithoutChangingTheStep() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.activate(.map)
        coordinator.perform(.mapAdd)
        let suspendedAt = Date(timeIntervalSince1970: 2_000_000)

        coordinator.recordSuspension(at: suspendedAt)

        let checkpoint = try XCTUnwrap(store.checkpoint(for: "ryan"))
        XCTAssertEqual(checkpoint.target, .mapAddAgain)
        XCTAssertEqual(checkpoint.updatedAt, suspendedAt)
    }

    func testProfileWalkthroughIsFullySuppressed() throws {
        let profileSteps = try XCTUnwrap(
            FirstVisitWalkthroughContent.stepsBySurface[.profile]
        )
        XCTAssertTrue(profileSteps.isEmpty)
        XCTAssertTrue(FirstVisitWalkthroughContent.suppressedSurfaces.contains(.profile))

        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.profile)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
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
            .feedSearchResultsBack
        ] {
            let step = try XCTUnwrap(
                FirstVisitWalkthroughContent.allSteps.first { $0.target == target }
            )
            XCTAssertEqual(step.advance, .action)
            XCTAssertTrue(step.allowsTargetInteraction)
            XCTAssertFalse(step.allowsBackNavigation)
        }

        let resultsBack = try XCTUnwrap(
            FirstVisitWalkthroughContent.allSteps.first { $0.target == .feedSearchResultsBack }
        )
        XCTAssertEqual(
            resultsBack.presentationStyle,
            .delayedTargetOnly(
                milliseconds: FirstVisitWalkthroughContent.discoverResultsPreviewMilliseconds
            )
        )
        XCTAssertFalse(resultsBack.automaticallyRecoversWhenTargetIsMissing)
        XCTAssertEqual(FirstVisitWalkthroughContent.discoverResultsPreviewMilliseconds, 4_000)
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

    func testListsLessonsRemainCompiledButTheSurfaceIsSuppressed() throws {
        let listSteps = try XCTUnwrap(FirstVisitWalkthroughContent.stepsBySurface[.lists])
        XCTAssertEqual(listSteps.map(\.spotlightStyle), [.clearPage, .clearPage])
        XCTAssertEqual(listSteps.map(\.automaticallyAdvances), [true, true])
        XCTAssertEqual(listSteps.map(\.allowsBackNavigation), [false, false])
        XCTAssertTrue(FirstVisitWalkthroughContent.suppressedSurfaces.contains(.lists))

        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.lists)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
        coordinator.forceActivate(.listsScope)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(coordinator.currentStep)
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

        let firstLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        firstLaunch.registerLaunch()
        firstLaunch.presentLaunchLessonIfEligible()
        XCTAssertFalse(firstLaunch.isPresentingImportLesson)
        XCTAssertFalse(firstLaunch.isPresentingDeviceFeaturesLesson)

        let secondLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        secondLaunch.registerLaunch()
        secondLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(secondLaunch.isPresentingImportLesson)
        XCTAssertFalse(secondLaunch.isPresentingDeviceFeaturesLesson)

        secondLaunch.completeImportLesson()
        XCTAssertFalse(secondLaunch.isPresentingImportLesson)

        let thirdLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        thirdLaunch.registerLaunch()
        XCTAssertEqual(thirdLaunch.restoreJourneyIfNeeded(), .resumed(.map))
        XCTAssertTrue(thirdLaunch.isPresentingDeviceFeaturesLesson)

        thirdLaunch.completeDeviceFeaturesLesson()
        XCTAssertFalse(thirdLaunch.isPresentingDeviceFeaturesLesson)

        let fourthLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        fourthLaunch.registerLaunch()
        fourthLaunch.presentLaunchLessonIfEligible()
        XCTAssertFalse(fourthLaunch.isPresentingLaunchLesson)
    }

    func testInterruptedImportResumesExactlyBeforeDeviceLesson() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)

        let firstLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        firstLaunch.registerLaunch()

        let interruptedSecondLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        interruptedSecondLaunch.registerLaunch()
        interruptedSecondLaunch.presentLaunchLessonIfEligible()
        XCTAssertTrue(interruptedSecondLaunch.isPresentingImportLesson)

        let thirdLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        thirdLaunch.registerLaunch()
        XCTAssertEqual(thirdLaunch.restoreJourneyIfNeeded(), .resumed(.map))
        XCTAssertTrue(thirdLaunch.isPresentingImportLesson)
        XCTAssertFalse(thirdLaunch.isPresentingDeviceFeaturesLesson)
        thirdLaunch.completeImportLesson()

        let fourthLaunch = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: store,
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        fourthLaunch.registerLaunch()
        XCTAssertEqual(fourthLaunch.restoreJourneyIfNeeded(), .resumed(.map))
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
            store: FirstVisitWalkthroughStore(defaults: defaults),
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )

        importCoordinator.registerLaunch(forceImportLesson: true)
        XCTAssertTrue(importCoordinator.isPresentingImportLesson)
        XCTAssertNil(importCoordinator.currentStep)

        let deviceCoordinator = FirstVisitWalkthroughCoordinator(
            userID: "visual-test-2",
            store: FirstVisitWalkthroughStore(defaults: defaults),
            launchRegistry: FirstVisitWalkthroughLaunchRegistry()
        )
        deviceCoordinator.registerLaunch(forceDeviceFeaturesLesson: true)
        XCTAssertTrue(deviceCoordinator.isPresentingDeviceFeaturesLesson)
        XCTAssertNil(deviceCoordinator.currentStep)
    }

    func testLiveJourneyRoutesSaveThenImportThenSendoff() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "ryan",
            store: FirstVisitWalkthroughStore(defaults: defaults)
        )

        coordinator.activate(.map)
        coordinator.perform(.mapAdd)
        coordinator.transition(to: .add)
        coordinator.perform(.addSearch, transitioningTo: .saveFlow)
        for target in [
            WalkthroughTargetID.saveStatus,
            .saveContinue,
            .saveDate,
            .saveNote,
            .saveRating,
            .saveMoreOptions,
            .saveQuestions,
            .saveTags,
            .saveSubmit
        ] {
            XCTAssertEqual(coordinator.currentStep?.target, target)
            coordinator.perform(target)
        }
        XCTAssertEqual(coordinator.requestedSurface, .map)

        coordinator.consumeRequestedSurface(.map)
        coordinator.activate(.map)
        XCTAssertEqual(coordinator.currentStep?.target, .mapAddAgain)
        coordinator.perform(.mapAddAgain)
        coordinator.transition(to: .add)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)
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
