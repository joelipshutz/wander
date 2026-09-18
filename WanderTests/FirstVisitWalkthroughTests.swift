import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class FirstVisitWalkthroughTests: XCTestCase {
    func testMapDemoContainsBothRingStatesAndCannotAttachToPersistentStore() {
        let demo = NUXMapDemonstration.places(around: NUXMapDemonstration.center())
        XCTAssertEqual(demo.count, 8)
        XCTAssertEqual(Set(demo.map(\.userPlace.status)), [.been, .wannaGo])
        XCTAssertTrue(demo.allSatisfy { $0.place.sourceProvider == "nux_demo" })
        XCTAssertTrue(demo.allSatisfy { $0.place.modelContext == nil && $0.userPlace.modelContext == nil })
    }

    func testOverviewRoutesFromRingsThroughFeedWithoutOpeningOrSavingAPlace() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.activate(.map)
        for target in [WalkthroughTargetID.mapFeatured, .mapFriends, .mapMoreFilters,
                       .mapSearch, .mapAdd, .mapPinLegend] {
            XCTAssertEqual(coordinator.currentStep?.target, target)
            XCTAssertNil(coordinator.tutorialCandidate)
            XCTAssertNil(coordinator.tutorialUserPlaceID)
            XCTAssertNil(coordinator.requestedSurface)
            coordinator.advancePassiveStep()
        }
        XCTAssertEqual(coordinator.requestedSurface, .feed)
        XCTAssertEqual(store.checkpoint(for: "ryan")?.target, .feedActivity)
        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.feed)
        XCTAssertEqual(coordinator.currentStep?.target, .feedActivity)
        coordinator.advancePassiveStep()
        XCTAssertTrue(coordinator.hasCompletedPrimaryJourney)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertNil(coordinator.activeSurface)
        XCTAssertNil(store.checkpoint(for: "ryan"))
        XCTAssertFalse(store.hasCompletedDeviceFeaturesLesson(for: "ryan"))
    }

    func testRetiredQuoteCheckpointRoutesToFeedAndCompletionClearsIt() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.setCheckpoint(FirstVisitWalkthroughCheckpoint(target: .mapSendoff, updatedAt: .now,
            tutorialCandidate: nil, tutorialUserPlaceID: nil, tutorialMemorySnapshot: nil), for: "ryan")
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .resumed(.feed))
        coordinator.consumeRequestedSurface(.feed)
        coordinator.activate(.feed)
        coordinator.advancePassiveStep()
        XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "ryan"))
        XCTAssertNil(store.checkpoint(for: "ryan"))
        coordinator.activate(.lists)
        XCTAssertNil(coordinator.currentStep)
    }

    func testLateCoachCallbackCannotSkipTheNextMapBeat() throws {
        let coordinator = FirstVisitWalkthroughCoordinator(
            userID: "reviewer", store: FirstVisitWalkthroughStore(defaults: try makeDefaults())
        )
        coordinator.activate(.map)
        let featuredID = try XCTUnwrap(coordinator.currentStep?.id)
        coordinator.advancePassiveStep(ifCurrentStepID: featuredID)
        XCTAssertEqual(coordinator.currentStep?.target, .mapFriends)
        coordinator.advancePassiveStep(ifCurrentStepID: featuredID)
        XCTAssertEqual(coordinator.currentStep?.target, .mapFriends)
        let friendsID = try XCTUnwrap(coordinator.currentStep?.id)
        coordinator.advancePassiveStep(ifCurrentStepID: friendsID)
        XCTAssertEqual(coordinator.currentStep?.target, .mapMoreFilters)
    }

    func testOpeningPlusExitsOverviewAndShowsOnlyVoluntaryNearbyHint() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.activate(.map)
        coordinator.finishOverviewForUserNavigation()
        coordinator.transition(to: .add)
        XCTAssertTrue(coordinator.hasCompletedPrimaryJourney)
        XCTAssertEqual(coordinator.currentStep?.target, .addNearby)
        coordinator.perform(.addSearch)
        XCTAssertEqual(coordinator.currentStep?.target, .addNearby)
        coordinator.advancePassiveStep()
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)
        coordinator.activate(.add)
        XCTAssertEqual(coordinator.currentStep?.target, .addImport)
        coordinator.advancePassiveStep()
        coordinator.activate(.add)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertNil(coordinator.requestedSurface)
        XCTAssertNil(coordinator.tutorialCandidate)
        XCTAssertFalse(store.hasCompletedDeviceFeaturesLesson(for: "ryan"))
    }

    func testEnrolledNewUserKeepsHintsAfterPrimaryRetirementWithoutRedirect() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.enrollContextualHints(for: "existing")
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "existing", store: store, isEnabled: false)
        coordinator.setContextualEnabled(true)
        coordinator.retireJourneyForDisabledExperience()
        coordinator.activate(.map)
        XCTAssertNil(coordinator.currentStep)
        coordinator.activate(.placeDetail)
        XCTAssertEqual(coordinator.currentStep?.target, .placeSaveActions)
        XCTAssertEqual(coordinator.currentStep?.presentationStyle, .contextual)
        XCTAssertNil(store.checkpoint(for: "existing"))
        coordinator.recordUserActivity()
        XCTAssertNil(coordinator.currentStep)
        XCTAssertNil(coordinator.requestedSurface)
        coordinator.activate(.placeDetail)
        XCTAssertNil(coordinator.currentStep)
        coordinator.activate(.lists)
        XCTAssertNil(coordinator.currentStep)
    }

    func testEstablishedAccountCannotAcquireHintsFromGlobalFlagOrLegacyCompletion() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "wander.walkthrough.established.map.complete")
        defaults.set(true, forKey: "wander.walkthrough.v14.established.feed.complete")
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "established", store: store, isEnabled: false)
        coordinator.setContextualEnabled(true)
        coordinator.retireJourneyForDisabledExperience()
        for surface in FirstVisitWalkthroughContent.contextualSurfaces {
            coordinator.activate(surface)
            XCTAssertNil(coordinator.currentStep)
        }
        XCTAssertFalse(coordinator.hasContextualEnrollment)
        XCTAssertFalse(coordinator.isContextualEnabled)
    }

    func testContextualEnrollmentPersistsOnlyForTheNewUserWhoStartedTheTour() throws {
        let defaults = try makeDefaults()
        let first = FirstVisitWalkthroughCoordinator(userID: "new-user", store: FirstVisitWalkthroughStore(defaults: defaults))
        first.activate(.map)
        XCTAssertTrue(first.hasContextualEnrollment)
        first.finishOverviewForUserNavigation()
        first.setEnabled(false)
        let relaunched = FirstVisitWalkthroughCoordinator(userID: "new-user", store: FirstVisitWalkthroughStore(defaults: defaults), isEnabled: false)
        relaunched.setContextualEnabled(true)
        relaunched.activate(.placeDetail)
        XCTAssertEqual(relaunched.currentStep?.target, .placeSaveActions)
        relaunched.setUserID("unrelated-user")
        relaunched.setContextualEnabled(true)
        relaunched.activate(.placeDetail)
        XCTAssertNil(relaunched.currentStep)
        XCTAssertFalse(relaunched.hasContextualEnrollment)
    }

    func testDebugResetNeedsEnabledReplayToEnrollAgain() throws {
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "reviewer", store: FirstVisitWalkthroughStore(defaults: try makeDefaults()))
        coordinator.prepareDebugReplay(at: .placeSaveActions)
        XCTAssertTrue(coordinator.hasContextualEnrollment)
        coordinator.setEnabled(false)
        coordinator.resetCurrentUser()
        coordinator.setContextualEnabled(true)
        coordinator.activate(.placeDetail)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertFalse(coordinator.hasContextualEnrollment)
        coordinator.setEnabled(true)
        coordinator.prepareDebugReplay(at: .placeSaveActions)
        XCTAssertTrue(coordinator.hasContextualEnrollment)
        XCTAssertEqual(coordinator.currentStep?.target, .placeSaveActions)
    }

    func testExplicitDisableSuppressesEnrolledHintsWithoutErasingEnrollment() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.enrollContextualHints(for: "new-user")
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "new-user", store: store, isEnabled: false)
        coordinator.setContextualEnabled(false)
        coordinator.activate(.feed)
        XCTAssertNil(coordinator.currentStep)
        XCTAssertTrue(coordinator.hasContextualEnrollment)
        coordinator.setContextualEnabled(true)
        coordinator.activate(.feed)
        XCTAssertEqual(coordinator.currentStep?.target, .feedActivity)
    }

    func testPrimaryCompletionDoesNotEraseAnActiveContextualHint() throws {
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: FirstVisitWalkthroughStore(defaults: try makeDefaults()))
        coordinator.setContextualEnabled(true)
        coordinator.activate(.placeDetail)
        coordinator.setEnabled(false)
        coordinator.retireJourneyForDisabledExperience()
        XCTAssertEqual(coordinator.currentStep?.target, .placeSaveActions)
        coordinator.advancePassiveStep()
        XCTAssertNil(coordinator.currentStep)
    }

    func testContextualDismissalIsAccountScopedAndSurvivesReconstruction() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.activate(.placeDetail)
        coordinator.advancePassiveStep()
        let restored = FirstVisitWalkthroughCoordinator(userID: "ryan", store: FirstVisitWalkthroughStore(defaults: defaults))
        restored.activate(.placeDetail)
        XCTAssertNil(restored.currentStep)
        restored.setUserID("joe")
        restored.activate(.placeDetail)
        XCTAssertEqual(restored.currentStep?.target, .placeSaveActions)
        restored.resetCurrentUser()
        restored.activate(.placeDetail)
        XCTAssertEqual(restored.currentStep?.target, .placeSaveActions)
    }

    func testLegacyCompleteAllMarkerDoesNotConsumeNewContextualHints() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "wander.walkthrough.ryan.lists.complete")
        defaults.set(true, forKey: "wander.walkthrough.v14.ryan.feed.complete")
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .lists))
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .feed))
    }

    func testRetiredImportCheckpointsNeverReopenOrConsumeDeviceGuide() throws {
        for presentation in [FirstVisitWalkthroughCheckpointPresentation.importLesson, .awaitingDeviceFeaturesLesson] {
            let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
            let checkpoint = FirstVisitWalkthroughCheckpoint(target: .mapAdd, updatedAt: .distantPast,
                tutorialCandidate: nil, tutorialUserPlaceID: nil, tutorialMemorySnapshot: nil, presentation: presentation)
            store.setCheckpoint(checkpoint, for: "ryan")
            let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
            XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .none)
            XCTAssertTrue(coordinator.hasCompletedPrimaryJourney)
            XCTAssertTrue(store.hasCompletedImportLesson(for: "ryan"))
            XCTAssertFalse(store.hasCompletedDeviceFeaturesLesson(for: "ryan"))
            XCTAssertFalse(coordinator.isPresentingImportLesson)
            XCTAssertNil(store.checkpoint(for: "ryan"))
        }
    }

    func testRetiredForcedSaveAndAddCheckpointsCannotOpenAnEditor() throws {
        for target in [WalkthroughTargetID.addSearch, .addImport, .saveStatus, .saveRating, .mapAddAgain] {
            let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
            store.setCheckpoint(FirstVisitWalkthroughCheckpoint(target: target, updatedAt: .now,
                tutorialCandidate: nil, tutorialUserPlaceID: nil, tutorialMemorySnapshot: nil), for: "ryan")
            let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
            XCTAssertEqual(coordinator.restoreJourneyIfNeeded(), .none)
            XCTAssertNil(coordinator.activeSurface)
            XCTAssertNil(coordinator.requestedSurface)
            XCTAssertTrue(coordinator.hasCompletedPrimaryJourney)
            XCTAssertFalse(store.hasCompletedDeviceFeaturesLesson(for: "ryan"))
        }
    }

    func testFreshOverviewRestoresItsExactCheckpoint() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        let now = Date()
        let first = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        first.forceActivate(.mapMoreFilters)
        first.recordSuspension(at: now)
        let next = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(next.restoreJourneyIfNeeded(now: now.addingTimeInterval(60)), .resumed(.map))
        XCTAssertEqual(next.currentStep?.target, .mapMoreFilters)
    }

    func testExpiredOverviewRetiresPrimaryButStillAllowsContextualHints() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        coordinator.forceActivate(.mapFriends)
        coordinator.recordSuspension(at: .distantPast)
        let restored = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(restored.restoreJourneyIfNeeded(), .expired)
        XCTAssertTrue(restored.hasCompletedPrimaryJourney)
        restored.activate(.placeDetail)
        XCTAssertEqual(restored.currentStep?.target, .placeSaveActions)
        XCTAssertFalse(restored.isPresentingLegacyPlaceWalkthrough)
    }

    func testNoScheduledLessonReturnsAfterFeedCompletion() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.markPrimaryJourneyComplete(for: "ryan")
        for _ in 1...3 {
            let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store,
                launchRegistry: FirstVisitWalkthroughLaunchRegistry())
            coordinator.registerLaunch(forceImportLesson: true)
            coordinator.presentLaunchLessonIfEligible()
            XCTAssertFalse(coordinator.isPresentingImportLesson)
            XCTAssertFalse(coordinator.isPresentingDeviceFeaturesLesson)
            XCTAssertTrue(store.hasCompletedEntireWalkthrough(for: "ryan"))
        }
    }

    func testRegisteringTheSamePhysicalLaunchDoesNotAccelerateDeviceGuide() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        let registry = FirstVisitWalkthroughLaunchRegistry()
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store, launchRegistry: registry)
        for _ in 0..<5 { coordinator.registerLaunch() }
        coordinator.presentLaunchLessonIfEligible()
        XCTAssertFalse(coordinator.isPresentingDeviceFeaturesLesson)
        XCTAssertEqual(store.registerLaunch(for: "ryan"), 2)
    }

    func testDeviceGuideCheckpointStillResumesAfterPrimaryCompletion() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.markPrimaryJourneyComplete(for: "ryan")
        let first = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        first.registerLaunch(forceDeviceFeaturesLesson: true)
        let next = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store)
        XCTAssertEqual(next.restoreJourneyIfNeeded(), .resumed(.map))
        XCTAssertTrue(next.isPresentingDeviceFeaturesLesson)
        next.completeDeviceFeaturesLesson()
        XCTAssertNil(store.checkpoint(for: "ryan"))
    }

    func testOptionalHintsAreNotRequiredForPrimaryCompletionCallback() throws {
        let store = FirstVisitWalkthroughStore(defaults: try makeDefaults())
        store.markPrimaryJourneyComplete(for: "ryan")
        var completed: [String] = []
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: store, onCompleted: { completed.append($0) })
        coordinator.registerLaunch(forceDeviceFeaturesLesson: true)
        coordinator.completeDeviceFeaturesLesson()
        XCTAssertEqual(completed, ["ryan"])
        XCTAssertFalse(store.isComplete(for: "ryan", surface: .placeDetail))
        coordinator.activate(.placeDetail)
        coordinator.advancePassiveStep()
        XCTAssertEqual(completed, ["ryan"])
    }

    func testSuppressedSaveFlowCannotStartOrMutateTutorialSave() throws {
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "ryan", store: FirstVisitWalkthroughStore(defaults: try makeDefaults()))
        coordinator.transition(to: .saveFlow)
        coordinator.forceActivate(.saveStatus)
        coordinator.recordTutorialSave(userPlaceID: "unexpected")
        XCTAssertNil(coordinator.currentStep)
        XCTAssertNil(coordinator.tutorialUserPlaceID)
    }

    func testQuoteAndListsAreRetiredAndAddHasTwoAnnotations() throws {
        let map = FirstVisitWalkthroughContent.stepsBySurface[.map, default: []]
        for step in map {
            XCTAssertEqual(step.advance, .next)
            XCTAssertTrue(step.allowsTargetInteraction)
            XCTAssertEqual(step.presentationStyle, .contextual)
            XCTAssertGreaterThanOrEqual(FirstVisitWalkthroughContent.presentationDelayMilliseconds(for: step), 2_800)
        }
        XCTAssertTrue(FirstVisitWalkthroughContent.stepsBySurface[.sendoff, default: []].isEmpty)
        XCTAssertTrue(FirstVisitWalkthroughContent.stepsBySurface[.lists, default: []].isEmpty)
        XCTAssertEqual(FirstVisitWalkthroughContent.primaryJourneySurfaces, [.map, .feed])
        XCTAssertEqual(FirstVisitWalkthroughContent.stepsBySurface[.add]?.map(\.target), [.addNearby, .addImport])
        XCTAssertEqual(FirstVisitWalkthroughContent.stepsBySurface[.add]?.last?.message,
                       "Import your saved places from Instagram, TikTok and Google Maps")
    }

    func testPlaceIntroductionCompletionPersistsAcrossProfilesAndRelaunch() throws {
        let defaults = try makeDefaults()
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "new-user", store: FirstVisitWalkthroughStore(defaults: defaults))
        coordinator.activate(.map)
        coordinator.finishOverviewForUserNavigation()
        coordinator.activate(.placeDetail)
        let step = try XCTUnwrap(coordinator.currentStep)
        XCTAssertEqual(step.target, .placeSaveActions)
        XCTAssertEqual(FirstVisitWalkthroughContent.presentationDelayMilliseconds(for: step), 3_500)
        XCTAssertEqual(NUXPlaceIntroductionTiming.glimmerMilliseconds, 1_400)
        coordinator.advancePassiveStep(ifCurrentStepID: step.id)
        coordinator.activate(.placeDetail)
        XCTAssertNil(coordinator.currentStep)
        let relaunched = FirstVisitWalkthroughCoordinator(userID: "new-user", store: FirstVisitWalkthroughStore(defaults: defaults))
        relaunched.activate(.placeDetail)
        XCTAssertNil(relaunched.currentStep)
        XCTAssertEqual(NUXCoachMotion.selected, .slide)
    }

    func testFeedIntroductionIsOneSequenceAndStaysConsumedAcrossVisitsAndRelaunch() throws {
        let defaults = try makeDefaults()
        let store = FirstVisitWalkthroughStore(defaults: defaults)
        store.enrollContextualHints(for: "new-user")
        let coordinator = FirstVisitWalkthroughCoordinator(userID: "new-user", store: store)
        coordinator.activate(.feed)
        let step = try XCTUnwrap(coordinator.currentStep)
        XCTAssertEqual(step.target, .feedActivity)
        XCTAssertEqual(FirstVisitWalkthroughContent.stepsBySurface[.feed]?.count, 1)
        XCTAssertEqual(FirstVisitWalkthroughContent.presentationDelayMilliseconds(for: step), 5_600)
        XCTAssertEqual(NUXFeedIntroductionTiming.totalMilliseconds + NUXFeedIntroductionTiming.readinessMilliseconds, 5_950)
        coordinator.advancePassiveStep(ifCurrentStepID: step.id)
        coordinator.activate(.feed)
        XCTAssertNil(coordinator.currentStep)
        let relaunched = FirstVisitWalkthroughCoordinator(userID: "new-user", store: FirstVisitWalkthroughStore(defaults: defaults))
        relaunched.activate(.feed)
        XCTAssertNil(relaunched.currentStep)
    }

    func testFeedFocusPreservesTheEntireActualTileIncludingItsFooter() throws {
        let size = CGSize(width: 393, height: 852)
        XCTAssertNil(NUXFeedFocus.circle.visibleFrame(in: [:], size: size, safeTop: 59))
        XCTAssertNil(NUXFeedFocus.circle.visibleFrame(in: [.feedCircle: CGRect(x: 420, y: 200, width: 184, height: 188)], size: size, safeTop: 59))
        let card = try XCTUnwrap(NUXFeedFocus.recent.visibleFrame(
            in: [.feedRecent: CGRect(x: 16, y: 500, width: 361, height: 600)], size: size, safeTop: 59))
        XCTAssertEqual(card.minY, 500)
        XCTAssertEqual(card, CGRect(x: 16, y: 500, width: 361, height: 600))
    }

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

    func testDebugPreferencesAreAccountScopedAndReplayStartsOnNextLaunchOnly() throws {
        let defaults = try makeDefaults()
        let walkthroughStore = FirstVisitWalkthroughStore(defaults: defaults)
        let preferences = FirstVisitWalkthroughDebugPreferences(defaults: defaults)

        walkthroughStore.setProgress(2, for: "user_a", surface: .map)
        walkthroughStore.markComplete(for: "user_a", surface: .map)
        walkthroughStore.markComplete(for: "user_b", surface: .map)
        XCTAssertNil(preferences.nuxOverride(for: "user_a"))
        XCTAssertNil(preferences.nuxOverride(for: "user_b"))

        preferences.setNUXEnabled(true, for: "user_a")

        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), true)
        XCTAssertTrue(preferences.isReplayRequested(for: "user_a"))
        XCTAssertEqual(walkthroughStore.progress(for: "user_a", surface: .map), 2)
        XCTAssertTrue(walkthroughStore.isComplete(for: "user_a", surface: .map))
        XCTAssertNil(preferences.nuxOverride(for: "user_b"))
        XCTAssertFalse(preferences.isReplayRequested(for: "user_b"))
        XCTAssertTrue(walkthroughStore.isComplete(for: "user_b", surface: .map))

        let nextLaunch = preferences.launchSnapshot()
        XCTAssertTrue(nextLaunch.isReplayRequested(for: "user_a"))
        XCTAssertTrue(nextLaunch.shouldStartReplay(for: "user_a"))
        preferences.markReplayStarted(for: "user_a")
        XCTAssertFalse(preferences.launchSnapshot().shouldStartReplay(for: "user_a"))

        preferences.clearReplayRequest(for: "user_a")
        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), true)
        XCTAssertFalse(preferences.isReplayRequested(for: "user_a"))

        preferences.setNUXEnabled(false, for: "user_a")
        XCTAssertEqual(preferences.nuxOverride(for: "user_a"), false)
        XCTAssertFalse(preferences.isReplayRequested(for: "user_a"))
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
