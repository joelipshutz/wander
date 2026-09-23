import Combine
import Foundation

enum ProductUpsellTrigger: String, CaseIterable, Codable, Equatable, Hashable {
    case onboardingNotifications = "onboarding_notifications"
    case placeSaved = "place_saved"
    case followCreated = "follow_created"
    case appOpened = "app_opened"
    case remoteNotificationReprompt = "remote_notification_reprompt"

    // Retained for the original campaign's persisted counters and debug previews.
    static let legacyNotificationTriggers: [Self] = [.onboardingNotifications, .placeSaved, .followCreated]
}

enum ProductUpsellCampaignID: String, Codable, Equatable, Hashable {
    case notifications
    case notificationReprompt = "notification_reprompt"
    case notificationAppOpen = "notification_app_open"
}

enum ProductUpsellActionPolicy: String, Codable, Equatable {
    case notifications
}

enum ProductUpsellPalette: String, Codable, Equatable {
    case sun
}

struct ProductUpsellContent: Equatable {
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String
    let palette: ProductUpsellPalette
}

struct ProductUpsellCampaignConfiguration: Equatable {
    let id: ProductUpsellCampaignID
    let triggers: Set<ProductUpsellTrigger>
    let contentByTrigger: [ProductUpsellTrigger: ProductUpsellContent]
    let actionPolicy: ProductUpsellActionPolicy
    let maxLifetimeImpressionsPerTrigger: Int
    let maxLifetimeImpressions: Int

    func content(for trigger: ProductUpsellTrigger) -> ProductUpsellContent? {
        contentByTrigger[trigger]
    }
}

struct ProductUpsellCatalog {
    let campaigns: [ProductUpsellCampaignConfiguration]

    func configuration(for trigger: ProductUpsellTrigger) -> ProductUpsellCampaignConfiguration? {
        campaigns.first { $0.triggers.contains(trigger) && $0.content(for: trigger) != nil }
    }

    static let production = ProductUpsellCatalog(
        campaigns: [
            ProductUpsellCampaignConfiguration(
                id: .notifications,
                triggers: [.onboardingNotifications, .placeSaved, .followCreated],
                contentByTrigger: [
                    .onboardingNotifications: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with your people",
                        message: "See when your friends check in, tag you, or you get a new follower.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    ),
                    .placeSaved: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with your people",
                        message: "See when your friends check in, tag you, or you get a new follower.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    ),
                    .followCreated: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with your people",
                        message: "See when your friends check in, tag you, or you get a new follower.",
                        systemImage: "person.crop.circle.badge.checkmark",
                        palette: .sun
                    )
                ],
                actionPolicy: .notifications,
                maxLifetimeImpressionsPerTrigger: 1,
                maxLifetimeImpressions: 3
            ),
            ProductUpsellCampaignConfiguration(
                id: .notificationAppOpen,
                triggers: [.appOpened],
                contentByTrigger: [
                    .appOpened: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with your people",
                        message: "See when your friends check in, tag you, or you get a new follower.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    )
                ],
                actionPolicy: .notifications,
                maxLifetimeImpressionsPerTrigger: 3,
                maxLifetimeImpressions: 3
            ),
            ProductUpsellCampaignConfiguration(
                id: .notificationReprompt,
                triggers: [.remoteNotificationReprompt],
                contentByTrigger: [
                    .remoteNotificationReprompt: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with your people",
                        message: "See when your friends check in, tag you, or you get a new follower.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    )
                ],
                actionPolicy: .notifications,
                maxLifetimeImpressionsPerTrigger: 1_000_000,
                maxLifetimeImpressions: 1_000_000
            )
        ]
    )
}

struct ProductUpsellPresentationGate: Equatable {
    var isPresentingAdd = false
    var isPresentingImportHub = false
    var isPresentingAuth = false
    var isPresentingDeepLink = false
    var isPresentingSaveFlow = false
    var isPresentingWalkthrough = false
    var isPresentingSaveStreak = false
    var isPresentingAlert = false
    var isPresentingChildModal = false

    var isBlocked: Bool {
        isPresentingAdd
            || isPresentingImportHub
            || isPresentingAuth
            || isPresentingDeepLink
            || isPresentingSaveFlow
            || isPresentingWalkthrough
            || isPresentingSaveStreak
            || isPresentingAlert
            || isPresentingChildModal
    }
}

enum ProductUpsellDebugPolicy {
    static let triggerArgument = "-WanderProductUpsellTrigger"
    static let frequencyBypassArgument = "-WanderBypassProductUpsellFrequencyCap"

    static func testUserDefaults(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = isDebug
    ) -> UserDefaults? {
        guard isDebugBuild,
              arguments.contains("-WanderAuthenticatedUITest"),
              let suite = environment["WANDER_PRODUCT_UPSELL_TEST_SUITE"],
              suite.hasPrefix("ProductUpsellUITests.") else { return nil }
        return UserDefaults(suiteName: suite)
    }

    static func forcedTrigger(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDebugBuild: Bool = isDebug
    ) -> ProductUpsellTrigger? {
        guard isDebugBuild,
              let flagIndex = arguments.firstIndex(of: triggerArgument)
        else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return ProductUpsellTrigger(rawValue: arguments[valueIndex])
    }

    static func bypassesFrequencyCap(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDebugBuild: Bool = isDebug
    ) -> Bool {
        isDebugBuild && arguments.contains(frequencyBypassArgument)
    }

    private static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct ProductUpsellTriggerRequest: Identifiable, Equatable {
    let id: UUID
    let trigger: ProductUpsellTrigger

    init(id: UUID = UUID(), trigger: ProductUpsellTrigger) {
        self.id = id
        self.trigger = trigger
    }
}

struct ProductUpsellTriggerBuffer: Equatable {
    private(set) var requests: [ProductUpsellTriggerRequest] = []

    @discardableResult
    mutating func enqueue(_ request: ProductUpsellTriggerRequest) -> Bool {
        guard !requests.contains(where: { $0.trigger == request.trigger }) else { return false }
        requests.append(request)
        return true
    }

    mutating func drain(isSessionValidated: Bool) -> [ProductUpsellTriggerRequest] {
        guard isSessionValidated else { return [] }
        let drainedRequests = requests
        requests.removeAll()
        return drainedRequests
    }

    mutating func removeAll() {
        requests.removeAll()
    }
}

struct ProductUpsellPresentation: Identifiable, Equatable {
    let id: UUID
    let userID: String
    let campaignID: ProductUpsellCampaignID
    let trigger: ProductUpsellTrigger
    let content: ProductUpsellContent
    let actionPolicy: ProductUpsellActionPolicy
    let impressionNumber: Int

    var isOnboarding: Bool {
        trigger == .onboardingNotifications
    }

    var analyticsProperties: [String: String] {
        [
            "campaign": campaignID.rawValue,
            "trigger": trigger.rawValue,
            "impression_number": "\(impressionNumber)",
            // Random per-presentation correlation, never an account, token, or app-open ID.
            "presentation_id": id.uuidString,
            "prompt_analytics_version": "1"
        ]
    }
}

enum ProductUpsellButton: String, CaseIterable {
    case `continue`
    case openSettings = "open_settings"
    case notNow = "not_now"
}

enum ProductUpsellAction: String, Equatable {
    case enabled
    case declined
    case dismissed
    case openedSettings = "opened_settings"
}

@MainActor
final class ProductUpsellCoordinator: ObservableObject {
    @Published private(set) var activePresentation: ProductUpsellPresentation?
    @Published private(set) var appOpenID = UUID()
    @Published private(set) var presentationBlockerCount = 0
    @Published private(set) var actionInFlightPresentationIDs: Set<UUID> = []

    private struct PendingRequest {
        let trigger: ProductUpsellTrigger
        let userID: String
        let bypassesFrequencyCap: Bool
        let completion: () -> Void
    }

    private struct SuspendedPresentation {
        let presentation: ProductUpsellPresentation
        let userID: String
        let completion: (() -> Void)?
    }

    private let catalog: ProductUpsellCatalog
    private let userDefaults: UserDefaults
    private let analytics: AnalyticsClient
    private var activeCompletion: (() -> Void)?
    private var pendingRequests: [PendingRequest] = []
    private var suspendedPresentation: SuspendedPresentation?
    private var boundUserID: String?
    private var presentationBlockerIDs: Set<UUID> = []
    private var didEnterBackground = false
    private var registeredAppOpenIDs: [String: UUID] = [:]
    private var presentedAppOpenIDs: [String: UUID] = [:]

    init(
        catalog: ProductUpsellCatalog = .production,
        userDefaults: UserDefaults = .standard,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.catalog = catalog
        self.userDefaults = userDefaults
        self.analytics = analytics
    }

    func bind(to userID: String?) {
        guard boundUserID != userID else { return }
        boundUserID = userID
        cancelAllRequests()
    }

    func recordAppBackground() {
        didEnterBackground = true
    }

    func recordAppForeground() {
        // Permission alerts and other inactive/active transitions are still
        // the same app open. Only a real background return begins another.
        guard didEnterBackground else { return }
        didEnterBackground = false
        appOpenID = UUID()
    }

    func recordAppOpen(for userID: String) {
        guard boundUserID == userID,
              registeredAppOpenIDs[userID] != appOpenID else { return }
        registeredAppOpenIDs[userID] = appOpenID
        // Called only from the authenticated main app, after onboarding.
        // Remounting the root or revalidating auth cannot count another open.
        userDefaults.set(appOpenCount(for: userID) + 1, forKey: appOpenCountKey(userID: userID))
        if activePresentation?.userID == userID || suspendedPresentation?.userID == userID {
            presentedAppOpenIDs[userID] = appOpenID
        }
    }

    func appOpenCount(for userID: String) -> Int {
        userDefaults.integer(forKey: appOpenCountKey(userID: userID))
    }

    func requestAppOpenNotificationReminder(userID: String, isEligible: Bool, canPresent: Bool) {
        guard boundUserID == userID,
              registeredAppOpenIDs[userID] == appOpenID,
              appOpenCount(for: userID) >= 2,
              presentedAppOpenIDs[userID] != appOpenID,
              isEligible, canPresent,
              presentationBlockerCount == 0,
              activePresentation == nil, suspendedPresentation == nil,
              pendingRequests.isEmpty else { return }
        // Reconcile at safe boundaries rather than queueing a request. An
        // interrupted open never consumes one of the three actual reminders.
        request(trigger: .appOpened, userID: userID, isEligible: true)
    }

    private func appOpenCountKey(userID: String) -> String {
        "recme.productUpsell.notificationAppOpen.\(userID).openCount.v1"
    }

    /// Remote requests are reconciled at safe presentation boundaries, never
    /// queued. Disabling or changing the remote campaign while blocked therefore
    /// cannot leave an obsolete prompt waiting to appear.
    func requestRemoteNotificationReprompt(
        campaignVersion: Int,
        userID: String,
        isEligible: Bool,
        canPresent: Bool
    ) {
        guard boundUserID == userID,
              isEligible, canPresent,
              presentationBlockerCount == 0,
              campaignVersion > 0,
              FeatureFlagKey.notificationRepromptCampaign.definition.accepts(.integer(campaignVersion)),
              campaignVersion > lastShownRemoteCampaignVersion(for: userID)
        else { return }

        // A currently visible notification primer already fulfils this request.
        // Do not put a second copy immediately behind it.
        if let activePresentation {
            guard activePresentation.userID == userID,
                  activePresentation.actionPolicy == .notifications else { return }
            userDefaults.set(campaignVersion, forKey: remoteCampaignVersionKey(userID: userID))
            return
        }
        guard presentedAppOpenIDs[userID] != appOpenID else { return }
        guard suspendedPresentation == nil, pendingRequests.isEmpty else { return }

        request(trigger: .remoteNotificationReprompt, userID: userID, isEligible: true)
        guard activePresentation?.trigger == .remoteNotificationReprompt,
              activePresentation?.userID == userID else { return }
        userDefaults.set(campaignVersion, forKey: remoteCampaignVersionKey(userID: userID))
    }

    func lastShownRemoteCampaignVersion(for userID: String) -> Int {
        userDefaults.integer(forKey: remoteCampaignVersionKey(userID: userID))
    }

    private func remoteCampaignVersionKey(userID: String) -> String {
        "recme.productUpsell.notificationReprompt.\(userID).lastShownCampaign.v1"
    }

    func request(
        trigger: ProductUpsellTrigger,
        userID: String,
        isEligible: Bool,
        canPresent: Bool = true,
        bypassesFrequencyCap: Bool = false,
        completion: @escaping () -> Void = {}
    ) {
        if boundUserID == nil {
            boundUserID = userID
        }
        guard boundUserID == userID,
              isEligible,
              let configuration = catalog.configuration(for: trigger)
        else {
            completion()
            return
        }

        if let activePresentation,
           activePresentation.campaignID == configuration.id,
           activePresentation.trigger == trigger {
            let previousCompletion = activeCompletion
            activeCompletion = {
                previousCompletion?()
                completion()
            }
            return
        }

        if let suspendedPresentation,
           suspendedPresentation.userID == userID,
           suspendedPresentation.presentation.campaignID == configuration.id,
           suspendedPresentation.presentation.trigger == trigger {
            let previousCompletion = suspendedPresentation.completion
            self.suspendedPresentation = SuspendedPresentation(
                presentation: suspendedPresentation.presentation,
                userID: suspendedPresentation.userID,
                completion: {
                    previousCompletion?()
                    completion()
                }
            )
            return
        }

        if let pendingIndex = pendingRequests.firstIndex(where: {
            $0.trigger == trigger && $0.userID == userID
        }) {
            let pendingRequest = pendingRequests[pendingIndex]
            let previousCompletion = pendingRequest.completion
            pendingRequests[pendingIndex] = PendingRequest(
                trigger: pendingRequest.trigger,
                userID: pendingRequest.userID,
                bypassesFrequencyCap: pendingRequest.bypassesFrequencyCap || bypassesFrequencyCap,
                completion: {
                    previousCompletion()
                    completion()
                }
            )
            return
        }

        guard bypassesFrequencyCap || (
                  impressionCount(for: configuration.id, userID: userID) < configuration.maxLifetimeImpressions
                      && impressionCount(for: trigger, campaignID: configuration.id, userID: userID)
                          < configuration.maxLifetimeImpressionsPerTrigger
              )
        else {
            completion()
            return
        }

        let request = PendingRequest(
            trigger: trigger,
            userID: userID,
            bypassesFrequencyCap: bypassesFrequencyCap,
            completion: completion
        )
        guard activePresentation == nil, suspendedPresentation == nil else {
            pendingRequests.append(request)
            return
        }
        guard canPresent else {
            pendingRequests.append(request)
            return
        }
        present(request, configuration: configuration)
    }

    func presentDeferredIfPossible(userID: String, isEligible: Bool, canPresent: Bool) {
        guard activePresentation == nil,
              canPresent
        else { return }
        if let suspendedPresentation {
            self.suspendedPresentation = nil
            guard suspendedPresentation.userID == userID, isEligible else {
                suspendedPresentation.completion?()
                presentDeferredIfPossible(
                    userID: userID,
                    isEligible: isEligible,
                    canPresent: canPresent
                )
                return
            }
            activeCompletion = suspendedPresentation.completion
            activePresentation = suspendedPresentation.presentation
            return
        }
        while activePresentation == nil, !pendingRequests.isEmpty {
            let pending = pendingRequests.removeFirst()
            guard pending.userID == userID else {
                pending.completion()
                continue
            }
            request(
                trigger: pending.trigger,
                userID: pending.userID,
                isEligible: isEligible,
                canPresent: true,
                bypassesFrequencyCap: pending.bypassesFrequencyCap,
                completion: pending.completion
            )
        }
    }

    func recordButtonClick(_ button: ProductUpsellButton, for presentationID: UUID) {
        guard let presentation = activePresentation,
              presentation.id == presentationID,
              presentation.userID == boundUserID else { return }
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.productUpsellButtonClicked,
            properties: presentation.analyticsProperties.merging(["button": button.rawValue]) { _, value in value }
        ))
    }

    func recordAction(
        _ action: ProductUpsellAction,
        for presentationID: UUID
    ) {
        let presentation: ProductUpsellPresentation?
        if activePresentation?.id == presentationID {
            presentation = activePresentation
        } else if suspendedPresentation?.presentation.id == presentationID {
            presentation = suspendedPresentation?.presentation
        } else {
            presentation = nil
        }
        guard let presentation else { return }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.productUpsellActioned,
                properties: presentation.analyticsProperties.merging(["action": action.rawValue]) { _, value in value }
            )
        )
    }

    func setPresentationBlocker(id: UUID, isActive: Bool) {
        if isActive {
            presentationBlockerIDs.insert(id)
        } else {
            presentationBlockerIDs.remove(id)
        }
        presentationBlockerCount = presentationBlockerIDs.count
        if isActive {
            suspendActivePresentation()
        }
    }

    func ownsPresentation(id: UUID) -> Bool {
        activePresentation?.id == id
            || suspendedPresentation?.presentation.id == id
    }

    @discardableResult
    func beginAction(for presentationID: UUID) -> Bool {
        guard ownsPresentation(id: presentationID),
              !actionInFlightPresentationIDs.contains(presentationID) else { return false }
        actionInFlightPresentationIDs.insert(presentationID)
        return true
    }

    func endAction(for presentationID: UUID) {
        actionInFlightPresentationIDs.remove(presentationID)
    }

    func suspendActivePresentation() {
        guard suspendedPresentation == nil,
              let activePresentation else { return }
        suspendedPresentation = SuspendedPresentation(
            presentation: activePresentation,
            userID: boundUserID ?? "",
            completion: activeCompletion
        )
        activeCompletion = nil
        self.activePresentation = nil
    }

    func completeCurrent(with action: ProductUpsellAction) {
        guard let presentationID = activePresentation?.id else { return }
        complete(presentationID: presentationID, with: action)
    }

    func complete(
        presentationID: UUID,
        with action: ProductUpsellAction
    ) {
        if activePresentation?.id == presentationID {
            recordAction(action, for: presentationID)
            endAction(for: presentationID)
            let completion = activeCompletion
            activeCompletion = nil
            activePresentation = nil
            completion?()
            return
        }
        guard suspendedPresentation?.presentation.id == presentationID else { return }
        recordAction(action, for: presentationID)
        endAction(for: presentationID)
        let completion = suspendedPresentation?.completion
        suspendedPresentation = nil
        completion?()
    }

    func impressionCount(for campaignID: ProductUpsellCampaignID, userID: String) -> Int {
        userDefaults.integer(forKey: impressionKey(campaignID: campaignID, userID: userID))
    }

    func impressionCount(
        for trigger: ProductUpsellTrigger,
        campaignID: ProductUpsellCampaignID,
        userID: String
    ) -> Int {
        userDefaults.integer(
            forKey: impressionKey(campaignID: campaignID, trigger: trigger, userID: userID)
        )
    }

    private func present(
        _ request: PendingRequest,
        configuration: ProductUpsellCampaignConfiguration
    ) {
        guard let content = configuration.content(for: request.trigger) else {
            request.completion()
            return
        }
        let previousCount = impressionCount(for: configuration.id, userID: request.userID)
        let impressionNumber = previousCount + 1
        if !request.bypassesFrequencyCap {
            userDefaults.set(
                impressionNumber,
                forKey: impressionKey(campaignID: configuration.id, userID: request.userID)
            )
            userDefaults.set(
                impressionCount(
                    for: request.trigger,
                    campaignID: configuration.id,
                    userID: request.userID
                ) + 1,
                forKey: impressionKey(
                    campaignID: configuration.id,
                    trigger: request.trigger,
                    userID: request.userID
                )
            )
        }
        activeCompletion = request.completion
        if registeredAppOpenIDs[request.userID] == appOpenID {
            presentedAppOpenIDs[request.userID] = appOpenID
        }
        let presentation = ProductUpsellPresentation(
            id: UUID(),
            userID: request.userID,
            campaignID: configuration.id,
            trigger: request.trigger,
            content: content,
            actionPolicy: configuration.actionPolicy,
            impressionNumber: impressionNumber
        )
        activePresentation = presentation
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.productUpsellShown,
                properties: presentation.analyticsProperties
            )
        )
    }

    private func cancelAllRequests() {
        activeCompletion = nil
        pendingRequests.removeAll()
        suspendedPresentation = nil
        activePresentation = nil
        actionInFlightPresentationIDs.removeAll()
    }

    private func impressionKey(campaignID: ProductUpsellCampaignID, userID: String) -> String {
        "recme.productUpsell.\(campaignID.rawValue).\(userID).impressionCount.v1"
    }

    private func impressionKey(
        campaignID: ProductUpsellCampaignID,
        trigger: ProductUpsellTrigger,
        userID: String
    ) -> String {
        "recme.productUpsell.\(campaignID.rawValue).\(trigger.rawValue).\(userID).impressionCount.v1"
    }
}
