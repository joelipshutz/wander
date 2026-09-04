import Combine
import Foundation

enum ProductUpsellTrigger: String, CaseIterable, Codable, Equatable, Hashable {
    case onboardingNotifications = "onboarding_notifications"
    case placeSaved = "place_saved"
    case followCreated = "follow_created"
}

enum ProductUpsellCampaignID: String, Codable, Equatable, Hashable {
    case notifications
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
                        title: "See when your friends check in",
                        message: "Get a heads-up when people you follow save a place or check in somewhere worth knowing.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    ),
                    .placeSaved: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "See when your friends check in",
                        message: "Get a heads-up when people you follow save a place or check in somewhere worth knowing.",
                        systemImage: "bell.and.waves.left.and.right.fill",
                        palette: .sun
                    ),
                    .followCreated: ProductUpsellContent(
                        eyebrow: "STAY IN THE LOOP",
                        title: "Keep up with people you follow",
                        message: "Get a heads-up when they save a place or check in somewhere worth knowing.",
                        systemImage: "person.crop.circle.badge.checkmark",
                        palette: .sun
                    )
                ],
                actionPolicy: .notifications,
                maxLifetimeImpressionsPerTrigger: 1,
                maxLifetimeImpressions: 3
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
    var hasTransientBanner = false

    var isBlocked: Bool {
        isPresentingAdd
            || isPresentingImportHub
            || isPresentingAuth
            || isPresentingDeepLink
            || isPresentingSaveFlow
            || isPresentingWalkthrough
            || isPresentingSaveStreak
            || isPresentingAlert
            || hasTransientBanner
    }
}

enum ProductUpsellDebugPolicy {
    static let triggerArgument = "-WanderProductUpsellTrigger"
    static let frequencyBypassArgument = "-WanderBypassProductUpsellFrequencyCap"

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
                properties: [
                    "campaign": presentation.campaignID.rawValue,
                    "trigger": presentation.trigger.rawValue,
                    "action": action.rawValue,
                    "impression_number": "\(presentation.impressionNumber)"
                ]
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
        activePresentation = ProductUpsellPresentation(
            id: UUID(),
            userID: request.userID,
            campaignID: configuration.id,
            trigger: request.trigger,
            content: content,
            actionPolicy: configuration.actionPolicy,
            impressionNumber: impressionNumber
        )
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.productUpsellShown,
                properties: [
                    "campaign": configuration.id.rawValue,
                    "trigger": request.trigger.rawValue,
                    "impression_number": "\(impressionNumber)"
                ]
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
