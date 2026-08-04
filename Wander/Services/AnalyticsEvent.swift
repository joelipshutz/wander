import Foundation

struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]
}

protocol AnalyticsClient {
    func track(_ event: AnalyticsEvent)
    func identify(userID: String)
    func resetIdentity()
}

struct NoopAnalyticsClient: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {}
    func identify(userID: String) {}
    func resetIdentity() {}
}

enum WanderAnalyticsEvents {
    static let onboardingStarted = "onboarding_started"
    static let onboardingCarouselViewed = "onboarding_carousel_viewed"
    static let onboardingCarouselAdvanced = "onboarding_carousel_advanced"
    static let onboardingAuthStarted = "onboarding_auth_started"
    static let onboardingAuthCompleted = "onboarding_auth_completed"
    static let onboardingIdentitySubmitted = "onboarding_identity_submitted"
    static let onboardingIdentityFailed = "onboarding_identity_failed"
    static let onboardingPermissionResult = "onboarding_permission_result"
    static let onboardingFriendSuggestionsCompleted = "onboarding_friend_suggestions_completed"
    static let onboardingCompleted = "onboarding_completed"
    static let locationPermissionResult = "location_permission_result"
    static let firstPlaceStarted = "first_place_started"
    static let placeCandidateShown = "place_candidate_shown"
    static let placeSaved = "place_saved"
    static let checkInStarted = "check_in_started"
    static let checkInCreated = "check_in_created"
    static let checkInEdited = "check_in_edited"
    static let checkInDeleted = "check_in_deleted"
    static let checkInSyncRetried = "check_in_sync_retried"
    static let saveStreakAdvanced = "save_streak_advanced"
    static let saveStreakSameDaySave = "save_streak_same_day_save"
    static let saveStreakReminderScheduled = "save_streak_reminder_scheduled"
    static let saveStreakReminderCancelledBySave = "save_streak_reminder_cancelled_by_save"
    static let saveStreakReminderOpened = "save_streak_reminder_opened"
    static let saveStreakReminderCompletedSaveAfterOpen = "save_streak_reminder_completed_save_after_open"
    static let visibilityChanged = "visibility_changed"
    static let followCreated = "follow_created"
    static let followRemoved = "follow_removed"
    static let blockCreated = "block_created"
    static let discoverFilterUsed = "discover_filter_used"
    static let discoverQueryParsed = "discover_query_parsed"
    static let discoverParseFailed = "discover_parse_failed"
    static let discoverSearchOpened = "discover_search_opened"
    static let discoverSearchExampleSelected = "discover_search_example_selected"
    static let discoverSearchSubmitted = "discover_search_submitted"
    static let discoverSearchResults = "discover_search_results"
    static let discoverSearchExited = "discover_search_exited"
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
