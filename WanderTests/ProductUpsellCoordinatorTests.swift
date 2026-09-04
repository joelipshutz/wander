import XCTest
@testable import Wander

@MainActor
final class ProductUpsellCoordinatorTests: XCTestCase {
    func testPresentationGateDefersForEveryExistingRootPresentation() {
        let blockedStates = [
            ProductUpsellPresentationGate(isPresentingAdd: true),
            ProductUpsellPresentationGate(isPresentingImportHub: true),
            ProductUpsellPresentationGate(isPresentingAuth: true),
            ProductUpsellPresentationGate(isPresentingDeepLink: true),
            ProductUpsellPresentationGate(isPresentingSaveFlow: true),
            ProductUpsellPresentationGate(isPresentingWalkthrough: true),
            ProductUpsellPresentationGate(isPresentingSaveStreak: true),
            ProductUpsellPresentationGate(isPresentingAlert: true),
            ProductUpsellPresentationGate(hasTransientBanner: true)
        ]

        XCTAssertFalse(ProductUpsellPresentationGate().isBlocked)
        XCTAssertTrue(blockedStates.allSatisfy(\.isBlocked))
    }

    func testPresentationBlockerRegistryCountsDistinctChildPresentations() {
        let coordinator = ProductUpsellCoordinator()
        let first = UUID()
        let second = UUID()

        coordinator.setPresentationBlocker(id: first, isActive: true)
        coordinator.setPresentationBlocker(id: first, isActive: true)
        coordinator.setPresentationBlocker(id: second, isActive: true)
        XCTAssertEqual(coordinator.presentationBlockerCount, 2)

        coordinator.setPresentationBlocker(id: first, isActive: false)
        XCTAssertEqual(coordinator.presentationBlockerCount, 1)
        coordinator.setPresentationBlocker(id: second, isActive: false)
        XCTAssertEqual(coordinator.presentationBlockerCount, 0)
    }

    func testTriggerBufferRetainsDistinctEventsUntilSessionValidation() {
        var buffer = ProductUpsellTriggerBuffer()
        let saveRequest = ProductUpsellTriggerRequest(trigger: .placeSaved)
        let followRequest = ProductUpsellTriggerRequest(trigger: .followCreated)

        XCTAssertTrue(buffer.enqueue(saveRequest))
        XCTAssertTrue(buffer.enqueue(followRequest))
        XCTAssertFalse(buffer.enqueue(ProductUpsellTriggerRequest(trigger: .placeSaved)))
        XCTAssertTrue(buffer.drain(isSessionValidated: false).isEmpty)
        XCTAssertEqual(buffer.requests, [saveRequest, followRequest])

        XCTAssertEqual(
            buffer.drain(isSessionValidated: true),
            [saveRequest, followRequest]
        )
        XCTAssertTrue(buffer.requests.isEmpty)
    }

    func testNotificationCampaignSharesThreeImpressionCapAcrossEveryTrigger() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ProductUpsellRecordingAnalyticsClient()
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults, analytics: analytics)
        let userID = "user_cap"

        for trigger in ProductUpsellTrigger.allCases {
            coordinator.request(trigger: trigger, userID: userID, isEligible: true)
            XCTAssertEqual(coordinator.activePresentation?.trigger, trigger)
            coordinator.completeCurrent(with: .dismissed)
        }

        var didSkipCappedRequest = false
        coordinator.request(
            trigger: .placeSaved,
            userID: userID,
            isEligible: true
        ) {
            didSkipCappedRequest = true
        }

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertTrue(didSkipCappedRequest)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 3)
        XCTAssertEqual(
            analytics.events.filter { $0.name == WanderAnalyticsEvents.productUpsellShown }.count,
            3
        )
    }

    func testEachCampaignTriggerShowsAtMostOnce() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        let userID = "user_trigger_cap"

        coordinator.request(trigger: .placeSaved, userID: userID, isEligible: true)
        coordinator.completeCurrent(with: .dismissed)
        coordinator.request(trigger: .placeSaved, userID: userID, isEligible: true)

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 1)
        XCTAssertEqual(
            coordinator.impressionCount(
                for: .placeSaved,
                campaignID: .notifications,
                userID: userID
            ),
            1
        )
    }

    func testAuthorizedBackendEnabledAccountSkipsOnboardingCampaign() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        var didComplete = false
        let notificationsAreEnabled = PushNotificationManager.notificationsAreEnabled(
            pushEnabled: true,
            authorizationStatus: .authorized
        )

        coordinator.request(
            trigger: .onboardingNotifications,
            userID: "user_enabled",
            isEligible: !notificationsAreEnabled
        ) {
            didComplete = true
        }

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_enabled"), 0)
    }

    func testImpressionCapIsScopedToTheAuthenticatedAccount() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)

        coordinator.bind(to: "user_a")
        for trigger in ProductUpsellTrigger.allCases {
            coordinator.request(trigger: trigger, userID: "user_a", isEligible: true)
            coordinator.completeCurrent(with: .dismissed)
        }
        coordinator.bind(to: "user_b")
        coordinator.request(trigger: .followCreated, userID: "user_b", isEligible: true)

        XCTAssertEqual(coordinator.activePresentation?.trigger, .followCreated)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_a"), 3)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_b"), 1)
    }

    func testDeferredRequestWaitsForPresentationAndCurrentEligibility() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        var didComplete = false

        coordinator.request(
            trigger: .placeSaved,
            userID: "user_deferred",
            isEligible: true,
            canPresent: false
        ) {
            didComplete = true
        }
        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_deferred"), 0)

        coordinator.presentDeferredIfPossible(
            userID: "user_deferred",
            isEligible: false,
            canPresent: true
        )

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_deferred"), 0)
    }

    func testRequestQueuesBehindAnActiveUpsellUntilPresentationIsAvailable() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)

        coordinator.request(trigger: .placeSaved, userID: "user_queue", isEligible: true)
        coordinator.request(trigger: .followCreated, userID: "user_queue", isEligible: true)
        coordinator.completeCurrent(with: .dismissed)

        XCTAssertNil(coordinator.activePresentation)
        coordinator.presentDeferredIfPossible(
            userID: "user_queue",
            isEligible: true,
            canPresent: true
        )
        XCTAssertEqual(coordinator.activePresentation?.trigger, .followCreated)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_queue"), 2)
    }

    func testActiveUpsellSuspendsForNewBlockerAndResumesWithoutAnotherImpression() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        let userID = "user_suspended"
        let blockerID = UUID()

        coordinator.request(trigger: .placeSaved, userID: userID, isEligible: true)
        let originalPresentation = try XCTUnwrap(coordinator.activePresentation)
        coordinator.setPresentationBlocker(id: blockerID, isActive: true)

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 1)

        coordinator.request(trigger: .followCreated, userID: userID, isEligible: true)
        XCTAssertNil(coordinator.activePresentation)
        coordinator.setPresentationBlocker(id: blockerID, isActive: false)
        coordinator.presentDeferredIfPossible(
            userID: userID,
            isEligible: true,
            canPresent: true
        )

        XCTAssertEqual(coordinator.activePresentation, originalPresentation)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 1)
        coordinator.completeCurrent(with: .dismissed)
        coordinator.presentDeferredIfPossible(
            userID: userID,
            isEligible: true,
            canPresent: true
        )
        XCTAssertEqual(coordinator.activePresentation?.trigger, .followCreated)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 2)
    }

    func testInFlightActionCanCompleteASuspendedPresentationExactlyOnce() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let analytics = ProductUpsellRecordingAnalyticsClient()
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults, analytics: analytics)
        let userID = "user_in_flight"
        let blockerID = UUID()
        var completionCount = 0

        coordinator.request(
            trigger: .onboardingNotifications,
            userID: userID,
            isEligible: true
        ) {
            completionCount += 1
        }
        let presentationID = try XCTUnwrap(coordinator.activePresentation?.id)
        XCTAssertTrue(coordinator.beginAction(for: presentationID))
        coordinator.setPresentationBlocker(id: blockerID, isActive: true)
        XCTAssertTrue(coordinator.actionInFlightPresentationIDs.contains(presentationID))
        XCTAssertFalse(coordinator.beginAction(for: presentationID))
        coordinator.complete(presentationID: presentationID, with: .enabled)
        coordinator.complete(presentationID: presentationID, with: .enabled)
        coordinator.setPresentationBlocker(id: blockerID, isActive: false)
        coordinator.presentDeferredIfPossible(
            userID: userID,
            isEligible: true,
            canPresent: true
        )

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertFalse(coordinator.actionInFlightPresentationIDs.contains(presentationID))
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(
            analytics.events.filter {
                $0.name == WanderAnalyticsEvents.productUpsellActioned
            }.count,
            1
        )
    }

    func testDeferredQueuePreservesEveryDistinctTriggerInOrder() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        let userID = "user_fifo"

        for trigger in ProductUpsellTrigger.allCases {
            coordinator.request(
                trigger: trigger,
                userID: userID,
                isEligible: true,
                canPresent: false
            )
        }

        for expectedTrigger in ProductUpsellTrigger.allCases {
            coordinator.presentDeferredIfPossible(
                userID: userID,
                isEligible: true,
                canPresent: true
            )
            XCTAssertEqual(coordinator.activePresentation?.trigger, expectedTrigger)
            coordinator.completeCurrent(with: .dismissed)
        }
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: userID), 3)
    }

    func testDuplicateOnboardingRequestCoalescesUntilTheVisibleUpsellCompletes() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        var completionCount = 0

        coordinator.request(
            trigger: .onboardingNotifications,
            userID: "user_onboarding",
            isEligible: true
        ) {
            completionCount += 1
        }
        coordinator.request(
            trigger: .onboardingNotifications,
            userID: "user_onboarding",
            isEligible: true
        ) {
            completionCount += 1
        }

        XCTAssertEqual(coordinator.activePresentation?.trigger, .onboardingNotifications)
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_onboarding"), 1)

        coordinator.completeCurrent(with: .dismissed)
        XCTAssertEqual(completionCount, 2)
    }

    func testAccountChangeCancelsActivePresentationWithoutCompletingThePriorAccount() throws {
        let suiteName = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        var didComplete = false

        coordinator.bind(to: "user_a")
        coordinator.request(
            trigger: .onboardingNotifications,
            userID: "user_a",
            isEligible: true
        ) {
            didComplete = true
        }
        coordinator.bind(to: "user_b")

        XCTAssertNil(coordinator.activePresentation)
        XCTAssertFalse(didComplete)
    }

    func testDebugTriggerRequiresDebugBuildAndKnownValue() {
        XCTAssertEqual(
            ProductUpsellDebugPolicy.forcedTrigger(
                arguments: ["Wander", "-WanderProductUpsellTrigger", "follow_created"],
                isDebugBuild: true
            ),
            .followCreated
        )
        XCTAssertNil(
            ProductUpsellDebugPolicy.forcedTrigger(
                arguments: ["Wander", "-WanderProductUpsellTrigger", "follow_created"],
                isDebugBuild: false
            )
        )
        XCTAssertTrue(
            ProductUpsellDebugPolicy.bypassesFrequencyCap(
                arguments: ["Wander", "-WanderBypassProductUpsellFrequencyCap"],
                isDebugBuild: true
            )
        )
        XCTAssertFalse(
            ProductUpsellDebugPolicy.bypassesFrequencyCap(
                arguments: ["Wander", "-WanderBypassProductUpsellFrequencyCap"],
                isDebugBuild: false
            )
        )
    }
}

private final class ProductUpsellRecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}
