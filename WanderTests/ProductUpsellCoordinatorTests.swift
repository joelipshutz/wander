import XCTest
import UserNotifications
@testable import Wander

@MainActor
final class ProductUpsellCoordinatorTests: XCTestCase {
    func testRemindersAppearOnFirstThreeEligibleOpensAcrossRelaunches() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let analytics = ProductUpsellRecordingAnalyticsClient()

        for appOpen in 1...6 {
            let coordinator = ProductUpsellCoordinator(userDefaults: defaults, analytics: analytics)
            coordinator.bind(to: "user_a")
            coordinator.recordAppOpen(for: "user_a")
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), appOpen)
            XCTAssertEqual(coordinator.activePresentation?.trigger, (1...3).contains(appOpen) ? .appOpened : nil)
            XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), min(3, appOpen))
            coordinator.completeCurrent(with: .dismissed)
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertNil(coordinator.activePresentation, "Dismissing cannot immediately re-prompt in the same open.")
        }

        let shown = analytics.events.filter { $0.name == WanderAnalyticsEvents.productUpsellShown }
        XCTAssertEqual(shown.count, 3)
        for (index, event) in shown.enumerated() {
            XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(event.properties["presentation_id"])))
            XCTAssertEqual(event.properties.filter { $0.key != "presentation_id" }, [
                "prompt_analytics_version": "1",
                "campaign": "notification_app_open", "trigger": "app_opened", "impression_number": "\(index + 1)"
            ])
        }
    }

    func testExistingUserReminderAudienceUsesPermissionAndPreference() throws {
        let states: [(UNAuthorizationStatus, Bool, Bool)] = [
            (.notDetermined, false, true), (.notDetermined, true, true),
            (.denied, false, true), (.denied, true, true),
            (.authorized, false, true), (.authorized, true, false),
            (.provisional, true, false), (.ephemeral, true, false)
        ]
        for (status, pushEnabled, shouldShow) in states {
            let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
            coordinator.bind(to: "existing_user")
            let eligible = !PushNotificationManager.notificationsAreEnabled(
                pushEnabled: pushEnabled, authorizationStatus: status
            )
            coordinator.recordAppOpen(for: "existing_user")
            coordinator.requestAppOpenNotificationReminder(userID: "existing_user", isEligible: eligible, canPresent: true)
            XCTAssertEqual(coordinator.activePresentation != nil, shouldShow, "Existing users are eligible on their first visit.")
            coordinator.completeCurrent(with: .dismissed)
            coordinator.recordAppBackground()
            coordinator.recordAppForeground()
            coordinator.recordAppOpen(for: "existing_user")
            coordinator.requestAppOpenNotificationReminder(userID: "existing_user", isEligible: eligible, canPresent: true)
            XCTAssertEqual(coordinator.activePresentation != nil, shouldShow)
            // No token-registration state is used to decide who gets a primer.
        }
    }

    func testUnansweredOnboardingResumesAcrossRelaunchesBeyondTheOldImpressionCap() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let analytics = ProductUpsellRecordingAnalyticsClient()

        // This also exercises migration from the old impression-only behavior:
        // the persisted show count exists, but no answer was recorded.
        for visit in 1...5 {
            let coordinator = ProductUpsellCoordinator(userDefaults: defaults, analytics: analytics)
            coordinator.bind(to: "user_a")
            coordinator.request(trigger: .onboardingNotifications, userID: "user_a", isEligible: true)
            let presentation = try XCTUnwrap(coordinator.activePresentation)
            XCTAssertEqual(presentation.impressionNumber, visit)
            XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), 0)
            XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 0)
            coordinator.recordAction(.openedSettings, for: presentation.id)
            // Opening Settings or terminating without an answer must not resolve onboarding.
        }
        XCTAssertEqual(analytics.events.filter { $0.name == WanderAnalyticsEvents.productUpsellShown }.count, 5)
    }

    func testOnboardingResolutionPersistsOnlyForTheCompletedPresentationAndAccount() throws {
        for action in [ProductUpsellAction.enabled, .declined, .dismissed] {
            for suspended in [false, true] {
                let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
                coordinator.request(trigger: .onboardingNotifications, userID: "user_a", isEligible: true)
                let id = try XCTUnwrap(coordinator.activePresentation?.id)
                coordinator.complete(presentationID: UUID(), with: action)
                XCTAssertTrue(coordinator.ownsPresentation(id: id), "A stale completion cannot resolve the step.")
                if suspended { coordinator.suspendActivePresentation() }
                coordinator.complete(presentationID: id, with: action)

                let relaunched = ProductUpsellCoordinator(userDefaults: defaults)
                var didSkipAnsweredStep = false
                relaunched.request(trigger: .onboardingNotifications, userID: "user_a", isEligible: true) {
                    didSkipAnsweredStep = true
                }
                XCTAssertNil(relaunched.activePresentation)
                XCTAssertTrue(didSkipAnsweredStep)
                relaunched.bind(to: "user_b")
                relaunched.request(trigger: .onboardingNotifications, userID: "user_b", isEligible: true)
                XCTAssertEqual(relaunched.activePresentation?.userID, "user_b")
            }
        }
    }

    func testPromptAnalyticsCorrelateShowsClicksAndOutcomesWithoutPrivateData() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recording = ProductUpsellRecordingAnalyticsClient()
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults, analytics: ContextualAnalyticsClient(client: recording, environment: .development))
        coordinator.bind(to: "user_private")
        coordinator.request(trigger: .onboardingNotifications, userID: "user_private", isEligible: true)
        let id = try XCTUnwrap(coordinator.activePresentation?.id)
        coordinator.recordButtonClick(.continue, for: UUID()) // Stale callback.
        coordinator.recordButtonClick(.continue, for: id)
        coordinator.suspendActivePresentation()
        coordinator.recordButtonClick(.notNow, for: id) // Not visible.
        coordinator.presentDeferredIfPossible(userID: "user_private", isEligible: true, canPresent: true)
        coordinator.recordButtonClick(.openSettings, for: id)
        coordinator.recordButtonClick(.openSettings, for: id) // Real repeat tap remains measurable.
        coordinator.recordButtonClick(.notNow, for: id)
        coordinator.complete(presentationID: id, with: .dismissed)
        coordinator.recordButtonClick(.notNow, for: id) // Already dismissed.
        XCTAssertEqual(recording.events.filter { $0.name == WanderAnalyticsEvents.productUpsellShown }.count, 1)
        let clicks = recording.events.filter { $0.name == WanderAnalyticsEvents.productUpsellButtonClicked }
        XCTAssertEqual(clicks.compactMap { $0.properties["button"] }, ["continue", "open_settings", "open_settings", "not_now"])
        XCTAssertEqual(recording.events.last?.properties["action"], "dismissed")
        for event in recording.events {
            XCTAssertEqual(event.properties["presentation_id"], id.uuidString)
            XCTAssertEqual(event.properties["prompt_analytics_version"], "1")
            XCTAssertEqual(event.properties["analytics_environment"], "development")
            XCTAssertFalse(event.properties.values.contains("user_private"))
            XCTAssertTrue(Set(event.properties.keys).isDisjoint(with: WanderAnalyticsSchema.forbiddenPropertyKeys))
        }
    }

    func testAppOpenRequiresBackgroundReturnAndSurvivesRootRemountAndAuthValidation() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.recordAppOpen(for: "user_a")
        for _ in 0..<3 {
            coordinator.recordAppForeground() // No background: permission alert, Control Center, etc.
            coordinator.bind(to: nil)
            coordinator.bind(to: "user_a")
            coordinator.recordAppOpen(for: "user_a")
        }
        XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), 1)
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), 2)
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.trigger, .appOpened)
    }

    func testBlockedOrEnabledOpensDoNotConsumeReminderAllowance() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.recordAppOpen(for: "user_a")
        for _ in 2...4 {
            coordinator.recordAppBackground()
            coordinator.recordAppForeground()
            coordinator.recordAppOpen(for: "user_a")
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: false)
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: false, canPresent: true)
            XCTAssertNil(coordinator.activePresentation)
        }
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 0)
        let blocker = UUID()
        coordinator.setPresentationBlocker(id: blocker, isActive: true)
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
        coordinator.setPresentationBlocker(id: blocker, isActive: false)
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.impressionNumber, 1)
        coordinator.completeCurrent(with: .enabled)
        for _ in 0..<3 {
            coordinator.recordAppBackground()
            coordinator.recordAppForeground()
            coordinator.recordAppOpen(for: "user_a")
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: false, canPresent: true)
            XCTAssertNil(coordinator.activePresentation)
        }
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 1)
    }

    func testFinishingOnboardingDoesNotStackFirstVisitReminderEvenAfterBackgrounding() throws {
        for backgroundDuringOnboarding in [false, true] {
            let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
            coordinator.bind(to: "new_user")
            coordinator.request(trigger: .onboardingNotifications, userID: "new_user", isEligible: true)
            XCTAssertNotNil(coordinator.activePresentation)
            if backgroundDuringOnboarding {
                coordinator.recordAppBackground()
                coordinator.recordAppForeground()
            }
            coordinator.completeCurrent(with: .declined)
            coordinator.recordAppOpen(for: "new_user")
            coordinator.requestAppOpenNotificationReminder(userID: "new_user", isEligible: true, canPresent: true)
            coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "new_user", isEligible: true, canPresent: true)
            XCTAssertNil(coordinator.activePresentation, "The onboarding answer already handled this visit.")
            XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "new_user"), 0)
            for reminder in 1...3 {
                coordinator.recordAppBackground()
                coordinator.recordAppForeground()
                coordinator.recordAppOpen(for: "new_user")
                coordinator.requestAppOpenNotificationReminder(userID: "new_user", isEligible: true, canPresent: true)
                XCTAssertEqual(coordinator.activePresentation?.impressionNumber, reminder)
                coordinator.completeCurrent(with: .dismissed)
            }
        }
    }

    func testAppOpenReminderCountsAreIndependentOfOnboardingAndLegacyPrompts() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        for trigger in ProductUpsellTrigger.legacyNotificationTriggers {
            coordinator.request(trigger: trigger, userID: "user_a", isEligible: true)
            coordinator.completeCurrent(with: .dismissed)
        }
        XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), 0, "Onboarding is not a main-app open.")
        coordinator.recordAppOpen(for: "user_a")
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.impressionNumber, 1)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_a"), 3)
    }

    func testAppOpenReminderRejectsStaleAccountsAndRetainsSeparateProgress() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.recordAppOpen(for: "user_a")
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        coordinator.bind(to: "user_b")
        coordinator.recordAppOpen(for: "user_b")
        coordinator.recordAppOpen(for: "user_a")
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation, "A stale account cannot request a reminder.")
        coordinator.requestAppOpenNotificationReminder(userID: "user_b", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.userID, "user_b", "The current account is eligible on its first visit.")
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 0)
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_b"), 1)
        XCTAssertEqual(coordinator.appOpenCount(for: "user_a"), 2)
        XCTAssertEqual(coordinator.appOpenCount(for: "user_b"), 1)
        coordinator.bind(to: "user_a")
        coordinator.recordAppOpen(for: "user_a")
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.userID, "user_a")
    }

    func testRemoteAndReturnRemindersDoNotStackInEitherOrder() throws {
        for remoteFirst in [true, false] {
            let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
            coordinator.bind(to: "user_a")
            coordinator.recordAppOpen(for: "user_a")
            coordinator.recordAppBackground()
            coordinator.recordAppForeground()
            coordinator.recordAppOpen(for: "user_a")
            if remoteFirst {
                coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
            } else {
                coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            }
            let id = try XCTUnwrap(coordinator.activePresentation?.id)
            coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertEqual(coordinator.activePresentation?.id, id)
            coordinator.completeCurrent(with: .dismissed)
            coordinator.requestRemoteNotificationReprompt(campaignVersion: 2, userID: "user_a", isEligible: true, canPresent: true)
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertNil(coordinator.activePresentation)
        }
    }

    func testSuspendedReminderDoesNotCountAgainAfterBackgroundOrRemount() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.recordAppOpen(for: "user_a")
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        let id = coordinator.activePresentation?.id
        coordinator.suspendActivePresentation()
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        coordinator.presentDeferredIfPossible(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.id, id)
        coordinator.completeCurrent(with: .dismissed)
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 1)
    }

    func testReminderUITestPersistenceRequiresDebugAndAuthenticatedFixture() {
        let environment = ["WANDER_PRODUCT_UPSELL_TEST_SUITE": "ProductUpsellUITests.test"]
        XCTAssertNil(ProductUpsellDebugPolicy.testUserDefaults(arguments: ["-WanderAuthenticatedUITest"], environment: environment, isDebugBuild: false))
        XCTAssertNil(ProductUpsellDebugPolicy.testUserDefaults(arguments: [], environment: environment, isDebugBuild: true))
    }

    func testRemoteCampaignBypassesAutomaticCapAndPersistsAcrossRelaunch() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        for trigger in ProductUpsellTrigger.legacyNotificationTriggers {
            coordinator.request(trigger: trigger, userID: "user_a", isEligible: true)
            coordinator.completeCurrent(with: .dismissed)
        }

        // Exhaust the actual return-reminder budget on separate visits.
        // Onboarding already handled the starting visit, so do not stack there.
        for _ in 0..<3 {
            coordinator.recordAppBackground()
            coordinator.recordAppForeground()
            coordinator.recordAppOpen(for: "user_a")
            coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertEqual(coordinator.activePresentation?.trigger, .appOpened)
            coordinator.completeCurrent(with: .dismissed)
        }
        XCTAssertEqual(coordinator.impressionCount(for: .notificationAppOpen, userID: "user_a"), 3)
        coordinator.recordAppBackground()
        coordinator.recordAppForeground()
        coordinator.recordAppOpen(for: "user_a")
        coordinator.requestAppOpenNotificationReminder(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation, "The automatic budget is exhausted.")
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.trigger, .remoteNotificationReprompt)
        XCTAssertEqual(coordinator.impressionCount(for: .notifications, userID: "user_a"), 3)
        XCTAssertEqual(coordinator.impressionCount(for: .notificationReprompt, userID: "user_a"), 1)
        coordinator.completeCurrent(with: .dismissed)

        let relaunched = ProductUpsellCoordinator(userDefaults: defaults)
        relaunched.bind(to: "user_a")
        relaunched.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(relaunched.activePresentation)
        relaunched.requestRemoteNotificationReprompt(campaignVersion: 2, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(relaunched.activePresentation?.trigger, .remoteNotificationReprompt)
        XCTAssertEqual(relaunched.activePresentation?.impressionNumber, 2)
        relaunched.completeCurrent(with: .dismissed)
        relaunched.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(relaunched.activePresentation, "An old campaign cannot replay after a newer campaign.")
    }

    func testRemoteCampaignWaitsForEligibilityAndPresentationWithoutConsumingExposure() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        for version in [-1, 0, 1_000_001] {
            coordinator.requestRemoteNotificationReprompt(campaignVersion: version, userID: "user_a", isEligible: true, canPresent: true)
            XCTAssertNil(coordinator.activePresentation)
        }
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: false, canPresent: true)
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: false)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 0)

        // Withdrawing the remote request while blocked leaves no stale queue.
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 0, userID: "user_a", isEligible: true, canPresent: true)
        coordinator.presentDeferredIfPossible(userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 2, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 2)
        XCTAssertEqual(coordinator.activePresentation?.trigger, .remoteNotificationReprompt)
    }

    func testRemoteCampaignIsAccountScopedAndRejectsStaleAccount() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_b", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_b"), 0)
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        coordinator.bind(to: "user_b")
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_b", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.userID, "user_b")
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 1)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_b"), 1)
    }

    func testVisiblePrimerSatisfiesRemoteCampaignWithoutAnotherDialog() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.request(trigger: .placeSaved, userID: "user_a", isEligible: true)
        let presentationID = coordinator.activePresentation?.id
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.id, presentationID)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 1)
        coordinator.completeCurrent(with: .dismissed)
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
    }

    func testRemoteCampaignCannotReplaceOrConsumeASuspendedPrimer() throws {
        let suite = "ProductUpsellCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ProductUpsellCoordinator(userDefaults: defaults)
        coordinator.bind(to: "user_a")
        coordinator.request(trigger: .followCreated, userID: "user_a", isEligible: true)
        coordinator.suspendActivePresentation()
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertNil(coordinator.activePresentation)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 0)
        coordinator.presentDeferredIfPossible(userID: "user_a", isEligible: true, canPresent: true)
        coordinator.requestRemoteNotificationReprompt(campaignVersion: 1, userID: "user_a", isEligible: true, canPresent: true)
        XCTAssertEqual(coordinator.activePresentation?.trigger, .followCreated)
        XCTAssertEqual(coordinator.lastShownRemoteCampaignVersion(for: "user_a"), 1)
    }

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
            ProductUpsellPresentationGate(isPresentingChildModal: true)
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

        for trigger in ProductUpsellTrigger.legacyNotificationTriggers {
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
        for trigger in ProductUpsellTrigger.legacyNotificationTriggers {
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

        for trigger in ProductUpsellTrigger.legacyNotificationTriggers {
            coordinator.request(
                trigger: trigger,
                userID: userID,
                isEligible: true,
                canPresent: false
            )
        }

        for expectedTrigger in ProductUpsellTrigger.legacyNotificationTriggers {
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
