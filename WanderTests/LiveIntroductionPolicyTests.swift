import XCTest
@testable import Wander

@MainActor
final class LiveIntroductionPolicyTests: XCTestCase {
    func testExplicitRouteAndAccountSetupDeferWithoutConsumingIntroduction() throws {
        let defaults = try makeDefaults()
        let store = LiveIntroductionStore(defaults: defaults)
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(priority: true), hasPresented: store.hasPresented(for: "a")))
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(setup: false), hasPresented: false))
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(validated: false), hasPresented: false))
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(active: false), hasPresented: false))
        XCTAssertFalse(store.hasPresented(for: "a"))
        XCTAssertEqual(LiveIntroductionPolicy.audience(for: context(), hasPresented: false), .returning)
    }

    func testFirstVisitUsesOrientationInsteadOfReturningMigrationCopy() {
        XCTAssertEqual(LiveIntroductionPolicy.audience(for: context(firstVisit: true), hasPresented: false), .firstVisit)
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(checkpoint: true, firstVisit: true), hasPresented: false))
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(userID: nil), hasPresented: false))
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(userID: ""), hasPresented: false))
    }

    func testOnlyActualPresentationConsumesOncePerAccountAndVersion() throws {
        let defaults = try makeDefaults()
        let store = LiveIntroductionStore(defaults: defaults)
        XCTAssertEqual(LiveIntroductionPolicy.audience(for: context(), hasPresented: store.hasPresented(for: "a")), .returning)
        XCTAssertFalse(store.hasPresented(for: "a"))
        store.markPresented(for: "a")
        XCTAssertNil(LiveIntroductionPolicy.audience(for: context(), hasPresented: store.hasPresented(for: "a")))
        XCTAssertTrue(LiveIntroductionStore(defaults: defaults).hasPresented(for: "a"))
        XCTAssertFalse(store.hasPresented(for: "b"))
        XCTAssertFalse(LiveIntroductionStore(defaults: defaults, version: 2).hasPresented(for: "a"))
    }

    func testNotNowAndShowMeAcknowledgementPreserveNUXProgressAndPayload() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let checkpoint = makeCheckpoint(target: .saveNote, presentation: nil)
        legacy.setProgress(3, for: "a", surface: .map)
        legacy.markComplete(for: "a", surface: .feed)
        legacy.setCheckpoint(checkpoint, for: "a")
        let before = defaults.dictionaryRepresentation().filter { $0.key.contains("walkthrough") || $0.key.contains("contextual") }
        LiveIntroductionStore(defaults: defaults).acknowledge(for: "a")
        let after = defaults.dictionaryRepresentation().filter { $0.key.contains("walkthrough") || $0.key.contains("contextual") }
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after))
        XCTAssertEqual(legacy.checkpoint(for: "a"), checkpoint)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 3)
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .map))
        XCTAssertTrue(legacy.isComplete(for: "a", surface: .feed))
    }

    func testInitialReviewDismissalIsRespectedWithoutWritingLegacyKeys() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "astir.live.introduction.v1.a")
        let store = LiveIntroductionStore(defaults: defaults)
        XCTAssertTrue(store.hasPresented(for: "a"))
        XCTAssertFalse(store.hasPresented(for: "b"))
        XCTAssertFalse(LiveIntroductionStore(defaults: defaults, version: 2).hasPresented(for: "a"))
        XCTAssertNil(defaults.object(forKey: "astir.live.introduction.v1.a.presented"))
    }

    func testSemanticMappingPreservesCheckpointAndCompletedSurface() {
        let original = makeCheckpoint(target: .mapMoreFilters)
        let plan = LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [], hasPriorityPresentation: false)
        XCTAssertEqual(plan.destination, .guide(.drawArea))
        XCTAssertEqual(plan.checkpoint, original)
        XCTAssertEqual(LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [.map], hasPriorityPresentation: false).destination, .alreadyCompleted)
        XCTAssertEqual(LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [], hasPriorityPresentation: true).destination, .deferred)
    }

    func testPendingSaveSearchProfileAndImportResumeTheirExistingFlows() {
        let cases: [(WalkthroughTargetID, WalkthroughSurface)] = [
            (.saveSubmit, .saveFlow), (.addImport, .add), (.feedSearchField, .feedSearch),
            (.placeHistory, .placeDetail), (.profileMap, .profile), (.profileCalendar, .profile),
            (.listEditorCollaborators, .listEditor), (.mapMemory, .map)
        ]
        for (target, surface) in cases {
            let original = makeCheckpoint(target: target)
            let plan = LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [], hasPriorityPresentation: false)
            XCTAssertEqual(plan.destination, .retained(surface, target))
            XCTAssertEqual(plan.checkpoint, original)
        }
        for presentation in [FirstVisitWalkthroughCheckpointPresentation.importLesson, .awaitingDeviceFeaturesLesson, .deviceFeaturesLesson, .contactInvite] {
            let original = makeCheckpoint(target: .mapAddAgain, presentation: presentation)
            let plan = LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [.map], hasPriorityPresentation: false)
            XCTAssertEqual(plan.destination, .retainedLesson(presentation))
            XCTAssertEqual(plan.checkpoint, original)
        }
    }

    func testExplicitDestinationAlwaysPrecedesLegacyLessonAndCompletedMarker() {
        let original = makeCheckpoint(target: .mapAddAgain, presentation: .contactInvite)
        let plan = LiveIntroductionCheckpointAdapter.plan(for: original, completedSurfaces: [.map], hasPriorityPresentation: true)
        XCTAssertEqual(plan.destination, .deferred)
        XCTAssertEqual(plan.checkpoint, original)
    }

    func testMigrationArchivesExactCheckpointBeforeRemovingActiveSlotWithoutCompletion() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let original = makeCheckpoint(target: .saveNote)
        legacy.setCheckpoint(original, for: "a")
        legacy.setProgress(2, for: "a", surface: .map)
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let record = try XCTUnwrap(migration.capture(for: "a"))
        XCTAssertEqual(record.checkpoint, original)
        XCTAssertEqual(migration.load(for: "a"), record)
        XCTAssertNil(legacy.checkpoint(for: "a"))
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 2)
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .map))
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .feed))
        XCTAssertFalse(legacy.hasCompletedDeviceFeaturesLesson(for: "a"))
        XCTAssertNotNil(defaults.data(forKey: "astir.live.migration.v1.a.archive.\(record.id.uuidString)"))
        // Simulates logical interruption after archive write, before removal.
        // UserDefaults is not an fsync/disk crash-durability test.
        legacy.setCheckpoint(original, for: "a")
        XCTAssertEqual(migration.capture(for: "a")?.id, record.id)
        XCTAssertNil(legacy.checkpoint(for: "a"))
    }

    func testMigrationNotNowAndOpeningRecoveryDoNotCompleteOrDiscardAction() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let checkpoint = makeCheckpoint(target: .saveSubmit)
        legacy.setCheckpoint(checkpoint, for: "a")
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let record = try XCTUnwrap(migration.capture(for: "a"))
        _ = migration.markOffered(userID: "a", recordID: record.id)
        let opened = try XCTUnwrap(migration.markRecoveryOpened(userID: "a", recordID: record.id))
        XCTAssertTrue(opened.hasBeenOffered)
        XCTAssertTrue(opened.recoveryOpened)
        XCTAssertFalse(opened.recoveryCompleted)
        XCTAssertFalse(opened.isComplete)
        XCTAssertEqual(opened.checkpoint, checkpoint)
        XCTAssertEqual(opened.recovery, .retained(.saveFlow, .saveSubmit))
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .saveFlow))
    }

    func testMigrationAcknowledgesOnlyRepresentedStepsAndNeverRewindsNewerProgress() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        legacy.setCheckpoint(makeCheckpoint(target: .mapFeatured), for: "a")
        legacy.setProgress(3, for: "a", surface: .map)
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let record = try XCTUnwrap(migration.capture(for: "a"))
        XCTAssertFalse(record.requiredTargets.contains(.mapFeatured))
        XCTAssertFalse(record.requiredTargets.contains(.mapMoreFilters))
        _ = migration.acknowledge(.searchAndPeople, userID: "a", recordID: record.id)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 4)
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .map))
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .feed))
        _ = migration.acknowledge(.addPlace, userID: "a", recordID: record.id)
        let completed = try XCTUnwrap(migration.acknowledge(.activity, userID: "a", recordID: record.id))
        XCTAssertTrue(completed.isComplete)
        XCTAssertTrue(legacy.isComplete(for: "a", surface: .map))
        XCTAssertTrue(legacy.isComplete(for: "a", surface: .feed))
        XCTAssertFalse(legacy.hasCompletedImportLesson(for: "a"))
        XCTAssertFalse(legacy.hasCompletedDeviceFeaturesLesson(for: "a"))
    }

    func testMigrationGuideCannotCompleteUnmappedOrRetainedActions() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        legacy.setCheckpoint(makeCheckpoint(target: .mapMemory), for: "a")
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let record = try XCTUnwrap(migration.capture(for: "a"))
        for step in record.pendingSteps { _ = migration.acknowledge(step, userID: "a", recordID: record.id) }
        let afterGuide = try XCTUnwrap(migration.load(for: "a"))
        XCTAssertTrue(afterGuide.pendingSteps.isEmpty)
        XCTAssertFalse(afterGuide.isComplete)
        XCTAssertEqual(afterGuide.recovery, .retained(.map, .mapMemory))
        let dismissed = try XCTUnwrap(migration.dismissRecovery(userID: "a", recordID: record.id))
        XCTAssertTrue(dismissed.recoveryDismissed)
        XCTAssertFalse(dismissed.recoveryCompleted)
        XCTAssertEqual(dismissed.checkpoint, record.checkpoint)

        let unknown = LiveIntroductionMigrationRecord(id: UUID(), userID: "a", checkpoint: makeCheckpoint(target: .mapFeatured), requiredTargets: [.mapAddAgain])
        XCTAssertTrue(unknown.pendingSteps.isEmpty)
        XCTAssertFalse(unknown.isComplete, "An unmapped required action cannot silently become completed")
    }

    func testMigrationKeepsSupersededArchiveAndRejectsOldAccountOrRecordCallbacks() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        legacy.setCheckpoint(makeCheckpoint(target: .mapFriends), for: "a")
        let old = try XCTUnwrap(migration.capture(for: "a"))
        let newerCheckpoint = makeCheckpoint(target: .saveSubmit)
        legacy.setCheckpoint(newerCheckpoint, for: "a")
        let newer = try XCTUnwrap(migration.capture(for: "a"))
        XCTAssertNotEqual(newer.id, old.id)
        XCTAssertEqual(newer.checkpoint, newerCheckpoint)
        XCTAssertNotNil(defaults.data(forKey: "astir.live.migration.v1.a.archive.\(old.id.uuidString)"))
        XCTAssertNil(migration.acknowledge(.activity, userID: "a", recordID: old.id))
        XCTAssertNil(migration.completeRecovery(userID: "b", recordID: newer.id))
        XCTAssertEqual(migration.load(for: "a"), newer)
    }

    func testMigrationPreservesIndependentLessonAndContactSelection() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        legacy.markComplete(for: "a", surface: .map)
        legacy.markComplete(for: "a", surface: .feed)
        let original = makeCheckpoint(target: .mapAdd, presentation: .contactInvite)
        legacy.setCheckpoint(original, for: "a")
        let migration = LiveIntroductionMigrationStore(defaults: defaults)
        let record = try XCTUnwrap(migration.capture(for: "a"))
        XCTAssertTrue(record.pendingSteps.isEmpty)
        XCTAssertFalse(record.isComplete)
        migration.updateContactSelection(["new-fixture-contact"], userID: "a", recordID: record.id)
        XCTAssertEqual(migration.load(for: "a")?.contactSelection, ["new-fixture-contact"])
        XCTAssertEqual(migration.load(for: "a")?.checkpoint, original)
        XCTAssertFalse(legacy.hasCompletedDeviceFeaturesLesson(for: "a"))
    }

    func testOrdinaryGuideReplayWithoutOrientationContextIsReadOnly() throws {
        let defaults = try makeDefaults()
        let orientation = LiveIntroductionOrientationStore(defaults: defaults)
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        legacy.setProgress(2, for: "a", surface: .map)
        let before = defaults.dictionaryRepresentation()
        for step in LiveIntroductionStep.allCases {
            XCTAssertFalse(orientation.acknowledge(step, context: nil,
                authenticatedUserID: "a", storeUserID: "a", isSessionValidated: true))
        }
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
    }

    func testFreshOrientationRetainsPartialAcknowledgementsAndAdvancesOnlyContiguously() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let context = LiveIntroductionOrientationContext(userID: "a")
        func acknowledge(_ step: LiveIntroductionStep) {
            XCTAssertTrue(LiveIntroductionOrientationStore(defaults: defaults).acknowledge(step,
                context: context, authenticatedUserID: "a", storeUserID: "a", isSessionValidated: true))
        }
        // Reading activity does not skip the earlier map teaching steps.
        acknowledge(.activity)
        XCTAssertTrue(legacy.isComplete(for: "a", surface: .feed))
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 0)
        acknowledge(.mapAndFeed)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 1)
        acknowledge(.drawArea)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 1)
        // A newly constructed store resumes the persisted acknowledgements.
        acknowledge(.searchAndPeople)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 4)
        XCTAssertFalse(legacy.isComplete(for: "a", surface: .map))
        acknowledge(.searchAndPeople)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 4)
        acknowledge(.addPlace)
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 6)
        XCTAssertTrue(legacy.hasCompletedEntireWalkthrough(for: "a"))
    }

    func testFreshGuideCompletesOnlyRepresentedOverviewAndNeverCreatesCheckpointOrActionSuccess() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let orientation = LiveIntroductionOrientationStore(defaults: defaults)
        let context = LiveIntroductionOrientationContext(userID: "a")
        for step in LiveIntroductionStep.allCases {
            _ = orientation.acknowledge(step, context: context, authenticatedUserID: "a",
                storeUserID: "a", isSessionValidated: true)
        }
        XCTAssertTrue(legacy.hasCompletedEntireWalkthrough(for: "a"))
        for surface in WalkthroughSurface.allCases where surface != .map && surface != .feed {
            XCTAssertFalse(legacy.isComplete(for: "a", surface: surface), "Must preserve \(surface)")
        }
        XCTAssertFalse(legacy.hasCompletedImportLesson(for: "a"))
        XCTAssertFalse(legacy.hasCompletedDeviceFeaturesLesson(for: "a"))
        XCTAssertFalse(legacy.hasContextualEnrollment(for: "a"))
        XCTAssertFalse(legacy.hasCheckpointRecord(for: "a"))
        XCTAssertFalse(LiveIntroductionMigrationStore(defaults: defaults).hasRecord(for: "a"))
    }

    func testFreshOrientationRejectsUnavailableChangedAccountsAndWrongVersionWithoutWrites() throws {
        let defaults = try makeDefaults()
        let orientation = LiveIntroductionOrientationStore(defaults: defaults)
        let context = LiveIntroductionOrientationContext(userID: "a")
        let before = defaults.dictionaryRepresentation()
        for (authenticated, current, validated) in [(nil, "a", true), ("b", "a", true),
                                                    ("a", "b", true), ("b", "b", true), ("a", "a", false)] as [(String?, String, Bool)] {
            XCTAssertFalse(orientation.acknowledge(.mapAndFeed, context: context,
                authenticatedUserID: authenticated, storeUserID: current, isSessionValidated: validated))
        }
        XCTAssertFalse(orientation.acknowledge(.mapAndFeed,
            context: LiveIntroductionOrientationContext(userID: "a", version: 2),
            authenticatedUserID: "a", storeUserID: "a", isSessionValidated: true))
        XCTAssertFalse(orientation.acknowledge(.mapAndFeed,
            context: LiveIntroductionOrientationContext(userID: ""),
            authenticatedUserID: "", storeUserID: "", isSessionValidated: true))
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
    }

    func testFreshOrientationRefusesPendingUnreadableAndLegacyRetirementCheckpoints() throws {
        for fixture in 0..<4 {
            let defaults = try makeDefaults()
            let legacy = FirstVisitWalkthroughStore(defaults: defaults)
            switch fixture {
            case 0: legacy.setCheckpoint(makeCheckpoint(target: .saveSubmit), for: "a")
            case 1: defaults.set(Data([0, 1]), forKey: "wander.walkthrough.a.journeyCheckpoint")
            case 2: defaults.set("unreadable", forKey: "wander.walkthrough.v10.a.journeyCheckpoint")
            default: defaults.set(1, forKey: "wander.walkthrough.v10.a.map.progress")
            }
            let before = defaults.dictionaryRepresentation()
            XCTAssertFalse(LiveIntroductionOrientationStore(defaults: defaults).acknowledge(.mapAndFeed,
                context: LiveIntroductionOrientationContext(userID: "a"), authenticatedUserID: "a",
                storeUserID: "a", isSessionValidated: true))
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
        }
    }

    func testFreshOrientationRefusesExistingOrUnreadableMigrationAndCorruptAcknowledgements() throws {
        for fixture in 0..<3 {
            let defaults = try makeDefaults()
            if fixture == 0 {
                FirstVisitWalkthroughStore(defaults: defaults).setCheckpoint(makeCheckpoint(target: .saveSubmit), for: "a")
                _ = LiveIntroductionMigrationStore(defaults: defaults).capture(for: "a")
            } else {
                defaults.set(Data([0, 1]), forKey: fixture == 1
                    ? "astir.live.migration.v1.a" : "astir.live.orientation.v1.a")
            }
            let before = defaults.dictionaryRepresentation()
            XCTAssertFalse(LiveIntroductionOrientationStore(defaults: defaults).acknowledge(.mapAndFeed,
                context: LiveIntroductionOrientationContext(userID: "a"), authenticatedUserID: "a",
                storeUserID: "a", isSessionValidated: true))
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
        }
    }

    func testFreshOrientationDoesNotRewindExistingProgressAndFencesNewRecovery() throws {
        let defaults = try makeDefaults()
        let legacy = FirstVisitWalkthroughStore(defaults: defaults)
        let orientation = LiveIntroductionOrientationStore(defaults: defaults)
        let context = LiveIntroductionOrientationContext(userID: "a")
        legacy.setProgress(4, for: "a", surface: .map)
        XCTAssertTrue(orientation.acknowledge(.mapAndFeed, context: context,
            authenticatedUserID: "a", storeUserID: "a", isSessionValidated: true))
        XCTAssertEqual(legacy.progress(for: "a", surface: .map), 4)
        let checkpoint = makeCheckpoint(target: .saveNote)
        legacy.setCheckpoint(checkpoint, for: "a")
        let before = defaults.dictionaryRepresentation()
        XCTAssertFalse(orientation.acknowledge(.addPlace, context: context,
            authenticatedUserID: "a", storeUserID: "a", isSessionValidated: true))
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
        XCTAssertEqual(legacy.checkpoint(for: "a"), checkpoint)
    }

    func testUnmappedFreshGuidePageDoesNotWriteOrCompleteAnySurface() throws {
        let defaults = try makeDefaults()
        let before = defaults.dictionaryRepresentation()
        XCTAssertFalse(LiveIntroductionOrientationStore(defaults: defaults).acknowledge(.yourMap,
            context: LiveIntroductionOrientationContext(userID: "a"), authenticatedUserID: "a",
            storeUserID: "a", isSessionValidated: true))
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: defaults.dictionaryRepresentation()))
    }

    private func context(userID: String? = "a", active: Bool = true, validated: Bool = true,
                         setup: Bool = true, priority: Bool = false, checkpoint: Bool = false,
                         firstVisit: Bool = false) -> LiveIntroductionContext {
        LiveIntroductionContext(userID: userID, isLiveActive: active, isSessionValidated: validated,
                                hasFinishedAccountSetup: setup, hasPriorityPresentation: priority,
                                hasPendingLegacyCheckpoint: checkpoint, isFirstVisitEligible: firstVisit)
    }

    private func makeCheckpoint(target: WalkthroughTargetID,
                                presentation: FirstVisitWalkthroughCheckpointPresentation? = nil) -> FirstVisitWalkthroughCheckpoint {
        FirstVisitWalkthroughCheckpoint(target: target, updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tutorialCandidate: nil, tutorialUserPlaceID: "fixture-save",
            tutorialMemorySnapshot: nil, tutorialSelectedStatus: .wannaGo,
            tutorialDiscoverQuery: "fixture search", tutorialInvitedContactIDs: ["fixture-contact"],
            presentation: presentation)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "LiveIntroductionPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
