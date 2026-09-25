import Foundation

struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]
}

protocol AnalyticsClient {
    func track(_ event: AnalyticsEvent)
    func identify(userID: String)
    func identify(userID: String, person: AnalyticsPerson)
    func resetIdentity()
}

/// Explicitly approved profile fields for recognizable replay labels (REC-626).
/// Keep the stable account ID separate from the mutable display label.
struct AnalyticsPerson: Equatable {
    let displayName: String?
    let username: String?

    init(displayName: String?, username: String?) {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return String(value.prefix(128))
        }
        self.displayName = clean(displayName)
        self.username = clean(username)?.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    func properties(userID: String) -> [String: String] {
        let handle = username.flatMap { $0.isEmpty ? nil : "@\($0)" }
        let label: String
        if let displayName, let handle {
            label = "\(displayName) (\(handle))"
        } else {
            label = displayName ?? handle ?? userID
        }
        return [
            "name": label.isEmpty ? userID : label,
            "display_name": displayName ?? "",
            "username": username ?? ""
        ]
    }
}

extension AnalyticsClient {
    func identify(userID: String, person: AnalyticsPerson) {
        identify(userID: userID)
    }
}

struct NoopAnalyticsClient: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {}
    func identify(userID: String) {}
    func resetIdentity() {}
}

enum WanderAnalyticsSchema {
    static let version = "3"

    static let forbiddenPropertyKeys: Set<String> = [
        "address",
        "body",
        "canonical_name",
        "contact_id",
        "coordinates",
        "display_name",
        "email",
        "error",
        "handle",
        "latitude",
        "longitude",
        "message",
        "note",
        "phone",
        "phone_number",
        "place_name",
        "query",
        "raw_query",
        "search_text",
        "error_message",
        "access_token",
        "device_token",
        "invite_token",
        "recipient_id",
        "actor_id",
        "notification_id",
        "recipient",
        "text",
        "token",
        "url"
    ]

    static func sanitized(_ event: AnalyticsEvent) -> AnalyticsEvent {
        AnalyticsEvent(
            name: event.name,
            properties: event.properties.reduce(into: [:]) { result, item in
                guard !forbiddenPropertyKeys.contains(item.key.lowercased()) else { return }
                result[item.key] = String(item.value.prefix(128))
            }
        )
    }
}

struct ContextualAnalyticsClient: AnalyticsClient {
    private let client: AnalyticsClient
    private let commonProperties: [String: String]

    init(
        client: AnalyticsClient,
        bundle: Bundle = .main,
        platform: String = "ios",
        environment: AnalyticsEnvironment = .current
    ) {
        self.client = client
        commonProperties = [
            "analytics_schema_version": WanderAnalyticsSchema.version,
            "app_version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build_number": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "platform": platform,
            "analytics_environment": environment.rawValue
        ]
    }

    func track(_ event: AnalyticsEvent) {
        let contextualEvent = AnalyticsEvent(
            name: event.name,
            properties: event.properties.merging(commonProperties) { _, commonValue in commonValue }
        )
        client.track(WanderAnalyticsSchema.sanitized(contextualEvent))
        if let coreAction = AnalyticsEvent.coreAction(for: event) {
            client.track(WanderAnalyticsSchema.sanitized(AnalyticsEvent(
                name: coreAction.name,
                properties: coreAction.properties.merging(commonProperties) { _, commonValue in commonValue }
            )))
        }
    }

    func identify(userID: String) {
        client.identify(userID: userID)
    }

    func identify(userID: String, person: AnalyticsPerson) {
        client.identify(userID: userID, person: person)
    }

    func resetIdentity() {
        client.resetIdentity()
    }
}

/// Release device traffic includes TestFlight. Simulator and Debug traffic are never
/// silently mixed into launch metrics. Legacy events without this property stay unclassified.
enum AnalyticsEnvironment: String {
    case development, production
    static var current: Self {
        #if DEBUG || targetEnvironment(simulator)
        .development
        #else
        .production
        #endif
    }
}

extension AnalyticsEvent {
    /// A first check-in also emits place_saved(been). Count it only once here.
    /// Keep the original events unchanged for historical consumers.
    static func coreAction(for event: AnalyticsEvent) -> AnalyticsEvent? {
        let action: String
        switch event.name {
        case WanderAnalyticsEvents.placeSaved where event.properties["status"] == "wanna_go":
            action = "wanna_saved"
        case WanderAnalyticsEvents.checkInCreated:
            action = "check_in_created"
        default:
            return nil
        }
        return AnalyticsEvent(name: WanderAnalyticsEvents.coreActionPerformed,
                              properties: ["action": action, "completion": "local"])
    }
}

enum AnalyticsSaveMode: String { case add, edit, repeatCheckIn = "repeat_check_in", sharedVisit = "shared_visit" }
enum AnalyticsSaveOutcome: String { case synced, pending, failed }

/// One editor exposure even if SwiftUI rebuilds or presents a child picker.
struct SaveFlowAnalyticsTracker {
    private var didOpen = false
    mutating func opened(mode: AnalyticsSaveMode, status: String) -> AnalyticsEvent? {
        guard !didOpen else { return nil }
        didOpen = true
        return Self.event(WanderAnalyticsEvents.saveFlowOpened, mode: mode, status: status)
    }
    static func event(_ name: String, mode: AnalyticsSaveMode, status: String,
                      outcome: AnalyticsSaveOutcome? = nil) -> AnalyticsEvent {
        var properties = ["mode": mode.rawValue, "status": status == "been" ? "been" : "wanna_go"]
        if let outcome { properties["outcome"] = outcome.rawValue }
        return AnalyticsEvent(name: name, properties: properties)
    }
}

enum AnalyticsHumanNeed: String, CaseIterable {
    case connect
    case expression
    case status
}

enum AnalyticsEngagementAction: String {
    case activityCommented = "activity_commented"
    case activityLiked = "activity_liked"
    case activityCommentLiked = "activity_comment_liked"
    case checkInCreated = "check_in_created"
    case contactInviteSent = "contact_invite_sent"
    case followCreated = "follow_created"
    case listCreated = "list_created"
    case listPlaceAdded = "list_place_added"
    case ownProfileViewed = "own_profile_viewed"
    case placeSaved = "place_saved"
    case placePlanShared = "place_plan_shared"
    case recommendationShared = "recommendation_shared"
    case saveStreakAdvanced = "save_streak_advanced"
    case sharedVisitAccepted = "shared_visit_accepted"
    case sharedVisitInvitesQueued = "shared_visit_invites_queued"
    case trustedProfileViewed = "trusted_profile_viewed"
}

extension AnalyticsEvent {
    static func engagement(
        need: AnalyticsHumanNeed,
        action: AnalyticsEngagementAction,
        surface: String,
        properties: [String: String] = [:]
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: WanderAnalyticsEvents.engagementActionPerformed,
            properties: [
                "need": need.rawValue,
                "action": action.rawValue,
                "surface": surface
            ].merging(properties) { _, eventValue in eventValue }
        )
    }
}

@MainActor
final class AppAnalyticsLifecycleTracker {
    private static let firstOpenKey = "recme.analytics.first-open.v1"

    private let analytics: AnalyticsClient
    private let defaults: UserDefaults
    private var didRecordLaunch = false

    init(analytics: AnalyticsClient, defaults: UserDefaults = .standard) {
        self.analytics = analytics
        self.defaults = defaults
    }

    func recordLaunch() {
        guard !didRecordLaunch else { return }
        didRecordLaunch = true

        if !defaults.bool(forKey: Self.firstOpenKey) {
            defaults.set(true, forKey: Self.firstOpenKey)
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.appFirstOpened,
                    properties: ["acquisition_source": "direct_or_unknown"]
                )
            )
        }

        recordSession(source: "cold_launch")
    }

    func recordForegroundSession() {
        guard didRecordLaunch else { return }
        recordSession(source: "foreground_return")
    }

    private func recordSession(source: String) {
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.appSessionStarted,
                properties: ["session_source": source]
            )
        )
    }
}

struct AcquisitionAttribution: Equatable {
    let properties: [String: String]

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let allowedKeys = Set(["utm_source", "utm_medium", "utm_campaign", "utm_content"])
        var properties = components.queryItems?.reduce(into: [String: String]()) { result, item in
            guard allowedKeys.contains(item.name),
                  let value = Self.normalized(item.value)
            else { return }
            result[item.name] = value
        } ?? [:]
        properties["route"] = Self.route(for: components)
        properties["has_campaign"] = properties["utm_campaign"] == nil ? "false" : "true"
        self.properties = properties
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let normalized = value.unicodeScalars
            .filter { allowed.contains($0) }
            .prefix(80)
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func route(for components: URLComponents) -> String {
        if components.path.hasPrefix("/cards/"), let url = components.url,
           let target = WanderDeepLinkRoute.parse(url)?.url,
           let canonical = URLComponents(url: target, resolvingAgainstBaseURL: false) {
            return route(for: canonical)
        }
        let path = components.path.lowercased()
        if path.hasPrefix("/invite/") || path.hasPrefix("/lists/invite/") { return "invite" }
        if path.hasPrefix("/import/") { return "import" }
        if path.hasPrefix("/places/") || path.hasPrefix("/p/") { return "place" }
        if path.hasPrefix("/people/") || path.hasPrefix("/u/") { return "profile" }
        if path.hasPrefix("/activity/") { return "activity" }
        return "other"
    }
}

enum WanderAnalyticsEvents {
    static let coreActionPerformed = "core_action_performed"
    static let saveFlowOpened = "save_flow_opened"
    static let saveFlowSubmitted = "save_flow_submitted"
    static let saveFlowCompleted = "save_flow_completed"
    static let placeProfileViewed = "place_profile_viewed"
    static let eventsInterestSubmitted = "events_interest_submitted"
    static let eventsInterestResult = "events_interest_result"
    static let placePlanCreated = "place_plan_created"
    static let placePlanShareCompleted = "place_plan_share_completed"
    static let placePlanOpened = "place_plan_opened"
    static let feedbackSubmitted = "feedback_submitted"
    static let appFirstOpened = "app_first_opened"
    static let appSessionStarted = "app_session_started"
    static let acquisitionLinkOpened = "acquisition_link_opened"
    static let onboardingStarted = "onboarding_started"
    static let onboardingStepViewed = "onboarding_step_viewed"
    static let onboardingStepCompleted = "onboarding_step_completed"
    static let onboardingCarouselViewed = "onboarding_carousel_viewed"
    static let onboardingCarouselAdvanced = "onboarding_carousel_advanced"
    static let onboardingAuthStarted = "onboarding_auth_started"
    static let onboardingAuthCompleted = "onboarding_auth_completed"
    static let nativeSocialAuthResult = "native_social_auth_result"
    static let onboardingIdentitySubmitted = "onboarding_identity_submitted"
    static let onboardingIdentityFailed = "onboarding_identity_failed"
    static let onboardingPermissionResult = "onboarding_permission_result"
    static let onboardingFriendSuggestionsCompleted = "onboarding_friend_suggestions_completed"
    static let onboardingCompleted = "onboarding_completed"
    static let productUpsellShown = "product_upsell_shown"
    static let productUpsellButtonClicked = "product_upsell_button_clicked"
    static let productUpsellActioned = "product_upsell_actioned"
    static let appSurfaceViewed = "app_surface_viewed"
    static let engagementActionPerformed = "engagement_action_performed"
    static let locationPermissionResult = "location_permission_result"
    static let firstPlaceStarted = "first_place_started"
    static let placeCandidateShown = "place_candidate_shown"
    static let placeImportStarted = "place_import_started"
    static let placeImportMatchingCompleted = "place_import_matching_completed"
    static let placeSaved = "place_saved"
    static let checkInStarted = "check_in_started"
    static let checkInCreated = "check_in_created"
    static let checkInEdited = "check_in_edited"
    static let checkInDeleted = "check_in_deleted"
    static let checkInSyncRetried = "check_in_sync_retried"
    static let saveStreakAdvanced = "save_streak_advanced"
    static let saveStreakSameDaySave = "save_streak_same_day_save"
    static let saveStreakRecovered = "save_streak_recovered"
    static let saveStreakReminderScheduled = "save_streak_reminder_scheduled"
    static let saveStreakReminderCancelledBySave = "save_streak_reminder_cancelled_by_save"
    static let saveStreakReminderOpened = "save_streak_reminder_opened"
    static let saveStreakReminderCompletedSaveAfterOpen = "save_streak_reminder_completed_save_after_open"
    static let calendarReservationSyncCompleted = "calendar_reservation_sync_completed"
    static let visibilityChanged = "visibility_changed"
    static let followCreated = "follow_created"
    static let followRemoved = "follow_removed"
    static let blockCreated = "block_created"
    static let activityLikeChanged = "activity_like_changed"
    static let activityCommentLikeChanged = "activity_comment_like_changed"
    static let activityCommentCreated = "activity_comment_created"
    static let activityShareOpened = "activity_share_opened"
    static let activityShareCompleted = "activity_share_completed"
    static let placeShareCompleted = "place_share_completed"
    static let contactInviteSheetOpened = "contact_invite_sheet_opened"
    static let contactInviteDeliveryStarted = "contact_invite_delivery_started"
    static let contactInviteCompleted = "contact_invite_completed"
    static let notificationOpened = "notification_opened"
    static let sharedVisitInvitesQueued = "shared_visit_invites_queued"
    static let sharedVisitAccepted = "shared_visit_accepted"
    static let placeListCreated = "place_list_created"
    static let placeListItemAdded = "place_list_item_added"
    static let discoverFilterUsed = "discover_filter_used"
    static let discoverQueryParsed = "discover_query_parsed"
    static let discoverParseFailed = "discover_parse_failed"
    static let discoverSearchOpened = "discover_search_opened"
    static let discoverSearchExampleSelected = "discover_search_example_selected"
    static let discoverSearchSubmitted = "discover_search_submitted"
    static let discoverSearchResults = "discover_search_results"
    static let discoverSearchExited = "discover_search_exited"
    static let trustedPlaceSearchLocalResults = "trusted_place_search_local_results"
    static let trustedPlaceSearchRefinedResults = "trusted_place_search_refined_results"
    static let trustedPlaceSearchRemoteResults = "trusted_place_search_remote_results"
    static let trustedPlaceSearchResultSelected = "trusted_place_search_result_selected"
    static let socialPlaceSaved = "social_place_saved"
    static let ownPlaceSyncAttempted = "own_place_sync_attempted"
    static let ownPlaceSyncSucceeded = "own_place_sync_succeeded"
    static let ownPlaceSyncFailed = "own_place_sync_failed"
    static let ownPlaceSyncSkipped = "own_place_sync_skipped"
    static let ownPlaceSyncBatchStarted = "own_place_sync_batch_started"
    static let ownPlaceSyncBatchCompleted = "own_place_sync_batch_completed"
    static let ownPlaceSyncBatchSkipped = "own_place_sync_batch_skipped"
    static let syncFailed = "sync_failed"
    static let extractionJobStarted = "extraction_job_started"
    static let extractionJobCompleted = "extraction_job_completed"
    static let extractionJobFailed = "extraction_job_failed"
}
