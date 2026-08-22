import SwiftUI

enum WalkthroughSurface: String, CaseIterable, Codable, Sendable {
    case map
    case placeDetail
    case sendoff
    case add
    case saveFlow
    case feed
    case feedSearch
    case lists
    case listDetail
    case listEditor
    case profile
}

enum WalkthroughTargetID: String, Codable, Sendable {
    case mapAdd
    case mapAddAgain
    case mapFeatured
    case mapFriends
    case mapYou
    case mapMoreFilters
    case mapSearch
    case mapMemory
    case mapTabs
    case mapSendoff
    case addSearch
    case addPlace
    case addImport
    case addClose
    case saveStatus
    case saveContinue
    case saveDate
    case saveDetails
    case saveRating
    case saveFriends
    case savePhotos
    case saveMoreOptions
    case saveNote
    case saveQuestions
    case saveTags
    case savePrivacy
    case saveSubmit
    case saveReview
    case feedActivity
    case feedSurfaceSwitch
    case feedPeopleSearch
    case feedInvite
    case feedDiscoverSearch
    case feedSearchField
    case feedSmartSearch
    case feedSearchResultsBack
    case placeRatings
    case placeActions
    case placeHistory
    case listsCreate
    case listsScope
    case listsOpenPlan
    case listMap
    case listMapPlace
    case listEditorTitle
    case listEditorPrivacy
    case listEditorCollaborators
    case profileSettings
    case profileSocial
    case profileActivity
    case profileShare
    case profileCalendar
    case profileMap
}

enum WalkthroughAdvance: Equatable, Sendable {
    case action
    case next
}

enum WalkthroughCoachTheme: Equatable, Sendable {
    case standard
    case map
    case save
    case rating
    case tags
    case social
    case memory
    case lists
    case profile
    case celebration
}

enum WalkthroughSpotlightStyle: Equatable, Sendable {
    case focused
    case clearPage
}

enum WalkthroughPresentationStyle: Equatable, Sendable {
    case coach
    case delayedTargetOnly(milliseconds: Int)
    case finale
}

struct WalkthroughStep: Identifiable, Equatable, Sendable {
    let surface: WalkthroughSurface
    let target: WalkthroughTargetID
    let title: String
    let message: String
    let advance: WalkthroughAdvance
    let allowsTargetInteraction: Bool
    let allowsBackNavigation: Bool
    let nextButtonTitle: String
    let coachTheme: WalkthroughCoachTheme
    let spotlightStyle: WalkthroughSpotlightStyle
    let automaticallyAdvances: Bool
    let presentationStyle: WalkthroughPresentationStyle

    var id: String { "\(surface.rawValue).\(target.rawValue)" }
    var automaticallyRecoversWhenTargetIsMissing: Bool {
        // A temporarily late SwiftUI anchor must never skip an unskippable NUX
        // step. Domain views explicitly recover only genuinely inapplicable
        // targets (for example visited-only controls after Wanna Go).
        false
    }
}

enum FirstVisitWalkthroughContent {
    static let version = 13
    static let profileIntroAutoAdvanceDelayMilliseconds = 4_000
    static let profileAutoAdvanceDelayMilliseconds = 2_200
    static let reducedMotionProfileAutoAdvanceDelayMilliseconds = 1_900
    static let nextArrowNudgeDelayMilliseconds = 3_000
    static let discoverResultsPreviewMilliseconds = 4_000
    static let suppressedSurfaces: Set<WalkthroughSurface> = [
        .placeDetail,
        .feed,
        .feedSearch,
        .lists,
        .listDetail,
        .listEditor,
        .profile
    ]
    static let primaryJourneySurfaces: [WalkthroughSurface] = [
        .map, .add, .saveFlow, .sendoff
    ]

    static let stepsBySurface: [WalkthroughSurface: [WalkthroughStep]] = [
        .map: [
            step(.map, .mapAdd, "Saving a place", "Tap + and we’ll show you how a place becomes part of your map."),
            step(.map, .mapAddAgain, "One more shortcut", "Tap + again and we’ll show you where imports live.")
        ],
        .sendoff: [
            step(
                .sendoff,
                .mapSendoff,
                "Your map is yours now",
                "As you move through this life and this world you change things slightly. You leave marks behind, however small.",
                advance: .next,
                nextButtonTitle: "Finish",
                coachTheme: .celebration,
                spotlightStyle: .clearPage,
                presentationStyle: .finale
            )
        ],
        .add: [
            step(
                .add,
                .addSearch,
                "Finding a park near you",
                "We’ll choose a popular nearby park and show you how saving works.",
                allowsTargetInteraction: false,
                coachTheme: .map,
                automaticallyAdvances: true
            ),
            step(
                .add,
                .addImport,
                "Bring saves with you",
                "Import your places and lists from Google Maps, Instagram, Tiktok, and more here.",
                advance: .next,
                coachTheme: .save
            )
        ],
        .saveFlow: [
            step(
                .saveFlow,
                .saveStatus,
                "Have you been here before?",
                "If so, select Check In. If not, select Wanna Go."
            ),
            step(.saveFlow, .saveContinue, "Continue to the details", "We’ll fill in an example you can recognize on your map."),
            step(
                .saveFlow,
                .saveDate,
                "A date makes it a memory",
                "We’ll choose one for this demo.",
                allowsTargetInteraction: false,
                allowsBackNavigation: false,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveNote,
                "Leave a note for future you",
                "We’ll add one useful detail you’ll recognize later.",
                allowsTargetInteraction: false,
                coachTheme: .memory,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveRating,
                "A rating helps future you",
                "Watch how a quick score captures how this place felt.",
                allowsTargetInteraction: false,
                coachTheme: .rating,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveMoreOptions,
                "Add the detail you’ll remember",
                "A useful tag and short note make this place easier to rediscover.",
                allowsTargetInteraction: false,
                coachTheme: .tags,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveQuestions,
                "Why this place fits",
                "We’ll choose one useful answer in each section for this park.",
                allowsTargetInteraction: false,
                coachTheme: .tags,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveTags,
                "Tag it for later",
                "One accurate tag makes this park easier to rediscover.",
                allowsTargetInteraction: false,
                coachTheme: .tags,
                automaticallyAdvances: true
            ),
            step(
                .saveFlow,
                .saveSubmit,
                "Ready to save",
                "The highlighted button puts everything you just watched onto your map.",
                allowsTargetInteraction: false,
                coachTheme: .save,
                automaticallyAdvances: true
            )
        ],
        .feed: [
            step(
                .feed,
                .feedActivity,
                "See your friend's check-ins in real time",
                "Interact with your trusted feed with a like, comment, or share.",
                advance: .next
            ),
            step(
                .feed,
                .feedDiscoverSearch,
                "Ask your circle for a place",
                "Tap search to open Discover and find places through the context your people saved.",
                allowsBackNavigation: false,
                coachTheme: .map
            ),
            step(
                .feed,
                .feedPeopleSearch,
                "Find people you trust",
                "Search a name or @username to build the circle behind your map and feed.",
                advance: .next,
                allowsTargetInteraction: true,
                coachTheme: .social
            ),
            step(
                .feed,
                .feedInvite,
                "rec.me gets better with your circle",
                "Invite people whose taste you trust. The more people that join from your circle, the more useful your rec.me space becomes.",
                advance: .next,
                coachTheme: .social
            )
        ],
        .feedSearch: [
            step(
                .feedSearch,
                .feedSearchField,
                "Search with the details you remember",
                "Try a place name, category, neighborhood, person or @handle—or a saved tag like date night or work-friendly.",
                advance: .next,
                coachTheme: .map
            ),
            step(
                .feedSearch,
                .feedSmartSearch,
                "Search the way you think",
                "Tap an example or type your own search to turn a real-life need into trusted results.",
                allowsBackNavigation: false,
                coachTheme: .map
            ),
            step(
                .feedSearch,
                .feedSearchResultsBack,
                "",
                "",
                allowsBackNavigation: false,
                coachTheme: .map,
                presentationStyle: .delayedTargetOnly(
                    milliseconds: discoverResultsPreviewMilliseconds
                )
            )
        ],
        .lists: [
            step(
                .lists,
                .listsScope,
                "Every kind of plan, one tap away",
                "My Lists keeps your plans, Friends shows lists people share, and Collabs keeps shared planning together.",
                advance: .next,
                allowsBackNavigation: false,
                coachTheme: .lists,
                spotlightStyle: .clearPage,
                automaticallyAdvances: true
            ),
            step(
                .lists,
                .listsOpenPlan,
                "Turn saved places into a plan",
                "Keep trips, date nights, neighborhoods, and anything else you want to revisit together.",
                advance: .next,
                allowsBackNavigation: false,
                coachTheme: .lists,
                spotlightStyle: .clearPage,
                automaticallyAdvances: true
            )
        ],
        .listDetail: [],
        .listEditor: [],
        .profile: [],
        .placeDetail: [
            step(
                .placeDetail,
                .placeRatings,
                "Three ratings, three jobs",
                "Your rating is the average of your check-ins. rec.me rating averages your network's ratings. And fit score predicts how well this place matches your taste.",
                advance: .next,
                coachTheme: .rating
            ),
            step(
                .placeDetail,
                .placeActions,
                "Everything you need to go",
                "Directions, Call, Website, and Reservation appear here whenever a place supports them.",
                advance: .next,
                coachTheme: .map
            ),
            step(
                .placeDetail,
                .placeHistory,
                "Every visit stays useful",
                "Ever forget if that surf break you saved is left or right breaking? Check-in history captures that experience in memory with dates, ratings, notes, photos, friends, and tags.",
                advance: .next,
                nextButtonTitle: "Keep going",
                coachTheme: .memory
            )
        ]
    ]

    static var allSteps: [WalkthroughStep] {
        WalkthroughSurface.allCases.flatMap { stepsBySurface[$0, default: []] }
    }

    // Retained for a later re-enable. The current NUX intentionally ends after
    // Import, so these Map exploration lessons must not participate in routing.
    static let suppressedMapExplorationSteps: [WalkthroughStep] = [
        step(.map, .mapFeatured, MapSource.featured.subtitle, "", advance: .next, coachTheme: .map),
        step(.map, .mapFriends, MapSource.friends.subtitle, "", advance: .next, coachTheme: .social),
        step(.map, .mapYou, "Only your Check Ins and Wanna places", "", advance: .next, coachTheme: .map),
        step(
            .map,
            .mapMoreFilters,
            "Narrow in with More",
            "Filter by category, specific friends in your network, and distinguish between a check-in, wanna go, or both.",
            advance: .next,
            coachTheme: .map
        ),
        step(.map, .mapSearch, "Search your trusted map", "Try a place, neighborhood, or person.", advance: .next, coachTheme: .map),
        step(
            .map,
            .mapTabs,
            "Your places, all connected",
            "Map, Feed, Lists, and Profile work together to help you find, plan, and remember.",
            advance: .next,
            coachTheme: .map
        ),
        step(
            .map,
            .mapMemory,
            "Open the place memory",
            "Tap the highlighted place to revisit everything you just saved.",
            allowsTargetInteraction: true,
            allowsBackNavigation: false,
            coachTheme: .memory
        )
    ]

    /// Gives automatic demonstrations enough time for an average reader to
    /// understand the coach copy before the UI moves on.
    static func automaticReadingDelayMilliseconds(for target: WalkthroughTargetID) -> Int {
        guard let step = allSteps.first(where: { $0.target == target }) else { return 3_000 }
        let wordCount = (step.title + " " + step.message)
            .split(whereSeparator: { $0.isWhitespace })
            .count
        let readingMilliseconds = Int(ceil((Double(wordCount) / 220) * 60_000))
        return min(max(readingMilliseconds + 850, 2_800), 6_500)
    }

    // Retained for a later Lists NUX re-enable. These lessons stay compiled and their
    // target anchors remain in the Lists UI, but suppressedSurfaces keeps them dormant.
    static let suppressedListsStepsBySurface: [WalkthroughSurface: [WalkthroughStep]] = [
        .lists: [
            step(.lists, .listsCreate, "Make a list", "Tap + to turn saved places into a plan you can use."),
            step(.lists, .listsScope, "Plans from your people", "Switch between your own lists, friends' lists, and shared collabs."),
            step(.lists, .listsOpenPlan, "Open a plan", "Tap any list to see its places, map, privacy, and collaborators.")
        ],
        .listDetail: [
            step(.listDetail, .listMap, "See the whole plan", "Open the map to understand how every place fits together."),
            step(
                .listDetail,
                .listMapPlace,
                "A place card at a glance",
                "The focused card keeps the place type, who saved it, and whether it’s a Check In or Wanna Go together.",
                advance: .next,
                coachTheme: .lists
            )
        ],
        .listEditor: [
            step(
                .listEditor,
                .listEditorTitle,
                "Name the plan",
                "Give this list a title you'll recognize when the moment comes.",
                advance: .next
            ),
            step(
                .listEditor,
                .listEditorCollaborators,
                "Plan it together",
                "Add collaborators so everyone can keep the list current.",
                advance: .next
            ),
            step(
                .listEditor,
                .listEditorPrivacy,
                "Choose who can see it",
                "Stealth is the final choice: keep the list private or share it with people who follow you.",
                advance: .next
            )
        ]
    ]

    private static func step(
        _ surface: WalkthroughSurface,
        _ target: WalkthroughTargetID,
        _ title: String,
        _ message: String,
        advance: WalkthroughAdvance = .action,
        allowsTargetInteraction: Bool? = nil,
        allowsBackNavigation: Bool = true,
        nextButtonTitle: String = "Next",
        coachTheme: WalkthroughCoachTheme = .standard,
        spotlightStyle: WalkthroughSpotlightStyle = .focused,
        automaticallyAdvances: Bool = false,
        presentationStyle: WalkthroughPresentationStyle = .coach
    ) -> WalkthroughStep {
        WalkthroughStep(
            surface: surface,
            target: target,
            title: title,
            message: removingTerminalPeriods(from: message),
            advance: advance,
            allowsTargetInteraction: allowsTargetInteraction ?? (advance == .action),
            allowsBackNavigation: allowsBackNavigation,
            nextButtonTitle: nextButtonTitle,
            coachTheme: coachTheme,
            spotlightStyle: spotlightStyle,
            automaticallyAdvances: automaticallyAdvances,
            presentationStyle: presentationStyle
        )
    }

    private static func removingTerminalPeriods(from message: String) -> String {
        var result = message
        while result.last == "." {
            result.removeLast()
        }
        return result
    }
}

enum FirstVisitWalkthroughFeatureFlag {
#if DEBUG
    static let allowsLaunchArgumentOverride = true
#else
    static let allowsLaunchArgumentOverride = false
#endif

    static func isEnabled(
        isEligible: Bool,
        isUsingLiveData: Bool,
        launchArguments: [String],
        resolvedValue: Bool?,
        entitledDebugOverride: Bool? = nil,
        isEntitledDebugReplayRequested: Bool = false,
        isExplicitlyDisabledForAccount: Bool = false,
        allowsLaunchOverride: Bool = allowsLaunchArgumentOverride
    ) -> Bool {
        let hasDebugLaunchDisable = allowsLaunchOverride
            && launchArguments.contains("-WanderDisableWalkthroughs")
        if hasDebugLaunchDisable {
            return false
        }
        let hasDebugLaunchOverride = allowsLaunchOverride
            && launchArguments.contains("-WanderEnableWalkthroughs")
        if isExplicitlyDisabledForAccount && !hasDebugLaunchOverride {
            return false
        }
        let effectiveResolvedValue = entitledDebugOverride ?? resolvedValue
        return isEntitledDebugReplayRequested
            || hasDebugLaunchOverride
            || (effectiveResolvedValue == true && isEligible && isUsingLiveData)
    }
}

struct FirstVisitWalkthroughDebugPreferences {
    let defaults: UserDefaults
    private var featureFlagOverrides: FeatureFlagOverrideStore {
        FeatureFlagOverrideStore(defaults: defaults)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func nuxOverride(for userID: String) -> Bool? {
        featureFlagOverrides.override(for: .firstVisitNUX, userID: userID)?.booleanValue
    }

    func isReplayRequested(for userID: String) -> Bool {
        defaults.bool(forKey: replayKey(userID: userID))
    }

    @MainActor
    func setNUXEnabled(
        _ isEnabled: Bool,
        for userID: String,
        launchRegistry: FirstVisitWalkthroughLaunchRegistry = .process
    ) {
        featureFlagOverrides.setOverride(.boolean(isEnabled), for: .firstVisitNUX, userID: userID)
        if isEnabled {
            FirstVisitWalkthroughStore(defaults: defaults).reset(for: userID)
            launchRegistry.reset(for: userID)
            defaults.set(true, forKey: replayKey(userID: userID))
        } else {
            clearReplayRequest(for: userID)
        }
    }

    func clearReplayRequest(for userID: String) {
        defaults.removeObject(forKey: replayKey(userID: userID))
    }

    func clearNUXOverride(for userID: String) {
        featureFlagOverrides.clearOverride(for: .firstVisitNUX, userID: userID)
        clearReplayRequest(for: userID)
    }

    private func replayKey(userID: String) -> String {
        "wander.debugSettings.\(userID).firstVisitNUX.replayRequested"
    }
}

struct FirstVisitTutorialMemorySnapshot: Codable, Equatable, Sendable {
    let candidate: PlaceCandidate
    let status: PlaceStatus
    let date: Date
    let ratingScore: Double?
    let note: String
    let tag: String
}

enum FirstVisitWalkthroughCheckpointPresentation: String, Codable, Equatable, Sendable {
    case importLesson
    case awaitingDeviceFeaturesLesson
    case deviceFeaturesLesson
    case contactInvite
}

struct FirstVisitWalkthroughCheckpoint: Codable, Equatable, Sendable {
    let target: WalkthroughTargetID
    let updatedAt: Date
    let tutorialCandidate: PlaceCandidate?
    let tutorialUserPlaceID: String?
    let tutorialMemorySnapshot: FirstVisitTutorialMemorySnapshot?
    let tutorialSelectedStatus: PlaceStatus?
    let tutorialDiscoverQuery: String?
    let tutorialInvitedContactIDs: Set<String>?
    let presentation: FirstVisitWalkthroughCheckpointPresentation?

    init(
        target: WalkthroughTargetID,
        updatedAt: Date,
        tutorialCandidate: PlaceCandidate?,
        tutorialUserPlaceID: String?,
        tutorialMemorySnapshot: FirstVisitTutorialMemorySnapshot?,
        tutorialSelectedStatus: PlaceStatus? = nil,
        tutorialDiscoverQuery: String? = nil,
        tutorialInvitedContactIDs: Set<String>? = nil,
        presentation: FirstVisitWalkthroughCheckpointPresentation? = nil
    ) {
        self.target = target
        self.updatedAt = updatedAt
        self.tutorialCandidate = tutorialCandidate
        self.tutorialUserPlaceID = tutorialUserPlaceID
        self.tutorialMemorySnapshot = tutorialMemorySnapshot
        self.tutorialSelectedStatus = tutorialSelectedStatus
        self.tutorialDiscoverQuery = tutorialDiscoverQuery
        self.tutorialInvitedContactIDs = tutorialInvitedContactIDs
        self.presentation = presentation
    }
}

enum FirstVisitWalkthroughResumeDisposition: Equatable, Sendable {
    case none
    case resumed(WalkthroughSurface)
    case expired
}

struct FirstVisitWalkthroughStore {
    static let resumeWindow: TimeInterval = 12 * 60 * 60

    let defaults: UserDefaults
    let version: Int

    init(defaults: UserDefaults = .standard, version: Int = FirstVisitWalkthroughContent.version) {
        self.defaults = defaults
        self.version = version
    }

    func progress(for userID: String, surface: WalkthroughSurface) -> Int {
        let key = progressKey(userID: userID, surface: surface)
        if defaults.object(forKey: key) != nil {
            return defaults.integer(forKey: key)
        }

        let legacyKeys = legacyVersionedKeys(
            for: userID,
            suffix: "\(surface.rawValue).progress"
        )
        let migrated = legacyKeys.map(defaults.integer(forKey:)).max() ?? 0
        if !legacyKeys.isEmpty {
            defaults.set(migrated, forKey: key)
            legacyKeys.forEach(defaults.removeObject(forKey:))
        }
        return migrated
    }

    func setProgress(_ progress: Int, for userID: String, surface: WalkthroughSurface) {
        defaults.set(progress, forKey: progressKey(userID: userID, surface: surface))
        legacyVersionedKeys(
            for: userID,
            suffix: "\(surface.rawValue).progress"
        ).forEach(defaults.removeObject(forKey:))
    }

    func isComplete(for userID: String, surface: WalkthroughSurface) -> Bool {
        let key = completionKey(userID: userID, surface: surface)
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }

        let legacyKeys = legacyVersionedKeys(
            for: userID,
            suffix: "\(surface.rawValue).complete"
        )
        let migrated = legacyKeys.contains { defaults.bool(forKey: $0) }
        if !legacyKeys.isEmpty {
            defaults.set(migrated, forKey: key)
            legacyKeys.forEach(defaults.removeObject(forKey:))
        }
        return migrated
    }

    func markComplete(for userID: String, surface: WalkthroughSurface) {
        defaults.set(true, forKey: completionKey(userID: userID, surface: surface))
        legacyVersionedKeys(
            for: userID,
            suffix: "\(surface.rawValue).complete"
        ).forEach(defaults.removeObject(forKey:))
    }

    func reset(for userID: String) {
        for surface in WalkthroughSurface.allCases {
            defaults.removeObject(forKey: progressKey(userID: userID, surface: surface))
            defaults.removeObject(forKey: completionKey(userID: userID, surface: surface))
            legacyVersionedKeys(
                for: userID,
                suffix: "\(surface.rawValue).progress"
            ).forEach(defaults.removeObject(forKey:))
            legacyVersionedKeys(
                for: userID,
                suffix: "\(surface.rawValue).complete"
            ).forEach(defaults.removeObject(forKey:))
        }
        defaults.removeObject(forKey: launchCountKey(userID: userID))
        defaults.removeObject(forKey: importLessonCompletionKey(userID: userID))
        defaults.removeObject(forKey: deviceFeaturesCompletionKey(userID: userID))
        legacyVersionedKeys(
            for: userID,
            suffix: "authenticatedLaunchCount"
        ).forEach(defaults.removeObject(forKey:))
        legacyVersionedKeys(
            for: userID,
            suffix: "importLesson.complete"
        ).forEach(defaults.removeObject(forKey:))
        legacyVersionedKeys(
            for: userID,
            suffix: "deviceFeatures.complete"
        ).forEach(defaults.removeObject(forKey:))
        defaults.removeObject(forKey: legacyRetirementKey(userID: userID))
        clearCheckpoint(for: userID)
    }

    func registerLaunch(for userID: String) -> Int {
        let hadLegacyV10State = !legacyVersion10Keys(for: userID).isEmpty
        let hasResumableCheckpoint = checkpoint(for: userID) != nil
        if hadLegacyV10State && !hasResumableCheckpoint {
            defaults.set(true, forKey: legacyRetirementKey(userID: userID))
        }
        let key = launchCountKey(userID: userID)
        let legacyKeys = legacyVersionedKeys(
            for: userID,
            suffix: "authenticatedLaunchCount"
        )
        let priorCount: Int
        if defaults.object(forKey: key) != nil {
            priorCount = defaults.integer(forKey: key)
        } else {
            priorCount = legacyKeys.map(defaults.integer(forKey:)).max() ?? 0
        }
        let nextCount = priorCount + 1
        defaults.set(nextCount, forKey: key)
        legacyKeys.forEach(defaults.removeObject(forKey:))
        return nextCount
    }

    func hasCompletedDeviceFeaturesLesson(for userID: String) -> Bool {
        migratedBoolean(
            stableKey: deviceFeaturesCompletionKey(userID: userID),
            legacyKeys: legacyVersionedKeys(
                for: userID,
                suffix: "deviceFeatures.complete"
            )
        )
    }

    func hasCompletedImportLesson(for userID: String) -> Bool {
        migratedBoolean(
            stableKey: importLessonCompletionKey(userID: userID),
            legacyKeys: legacyVersionedKeys(
                for: userID,
                suffix: "importLesson.complete"
            )
        )
    }

    func markImportLessonComplete(for userID: String) {
        defaults.set(true, forKey: importLessonCompletionKey(userID: userID))
        legacyVersionedKeys(
            for: userID,
            suffix: "importLesson.complete"
        ).forEach(defaults.removeObject(forKey:))
    }

    func markDeviceFeaturesLessonComplete(for userID: String) {
        defaults.set(true, forKey: deviceFeaturesCompletionKey(userID: userID))
        legacyVersionedKeys(
            for: userID,
            suffix: "deviceFeatures.complete"
        ).forEach(defaults.removeObject(forKey:))
    }

    func markEntireWalkthroughComplete(for userID: String) {
        for surface in WalkthroughSurface.allCases {
            markComplete(for: userID, surface: surface)
        }
        markImportLessonComplete(for: userID)
        markDeviceFeaturesLessonComplete(for: userID)
        clearCheckpoint(for: userID)
        defaults.removeObject(forKey: legacyRetirementKey(userID: userID))
        legacyVersion10Keys(for: userID).forEach(defaults.removeObject(forKey:))
    }

    /// Normalizes a corrupted or partially migrated primary journey without
    /// consuming the independent second- and third-launch lessons.
    func markPrimaryJourneyComplete(for userID: String) {
        for surface in FirstVisitWalkthroughContent.primaryJourneySurfaces {
            markComplete(for: userID, surface: surface)
        }
        clearCheckpoint(for: userID)
    }

    func hasCheckpointRecord(for userID: String) -> Bool {
        defaults.object(forKey: checkpointKey(userID: userID)) != nil
            || !legacyCheckpointKeys(for: userID).isEmpty
    }

    func requiresLegacySessionRetirement(for userID: String) -> Bool {
        defaults.bool(forKey: legacyRetirementKey(userID: userID))
            || (!legacyVersion10Keys(for: userID).isEmpty && checkpoint(for: userID) == nil)
    }

    func checkpoint(for userID: String) -> FirstVisitWalkthroughCheckpoint? {
        if let data = defaults.data(forKey: checkpointKey(userID: userID)),
           let checkpoint = try? JSONDecoder().decode(
               FirstVisitWalkthroughCheckpoint.self,
               from: data
           ) {
            return checkpoint
        }

        // Journey age must survive a content-version bump. Migrate the newest
        // legacy checkpoint so an abandoned old NUX retires instead of being
        // treated as a brand-new walkthrough.
        let legacyCheckpoint = legacyCheckpointKeys(for: userID)
            .compactMap { key -> (String, FirstVisitWalkthroughCheckpoint)? in
                guard let data = defaults.data(forKey: key),
                      let checkpoint = try? JSONDecoder().decode(
                          FirstVisitWalkthroughCheckpoint.self,
                          from: data
                      )
                else { return nil }
                return (key, checkpoint)
            }
            .max { $0.1.updatedAt < $1.1.updatedAt }
        guard let legacyCheckpoint else { return nil }
        setCheckpoint(legacyCheckpoint.1, for: userID)
        return legacyCheckpoint.1
    }

    func setCheckpoint(_ checkpoint: FirstVisitWalkthroughCheckpoint, for userID: String) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: checkpointKey(userID: userID))
        for key in legacyCheckpointKeys(for: userID) {
            defaults.removeObject(forKey: key)
        }
    }

    func clearCheckpoint(for userID: String) {
        defaults.removeObject(forKey: checkpointKey(userID: userID))
        for key in legacyCheckpointKeys(for: userID) {
            defaults.removeObject(forKey: key)
        }
    }

    func hasCompletedEntireWalkthrough(for userID: String) -> Bool {
        WalkthroughSurface.allCases
            .filter { !FirstVisitWalkthroughContent.suppressedSurfaces.contains($0) }
            .allSatisfy { isComplete(for: userID, surface: $0) }
            && hasCompletedImportLesson(for: userID)
            && hasCompletedDeviceFeaturesLesson(for: userID)
    }

    private func progressKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.\(userID).\(surface.rawValue).progress"
    }

    private func completionKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.\(userID).\(surface.rawValue).complete"
    }

    private func launchCountKey(userID: String) -> String {
        "wander.walkthrough.\(userID).authenticatedLaunchCount"
    }

    private func deviceFeaturesCompletionKey(userID: String) -> String {
        "wander.walkthrough.\(userID).deviceFeatures.complete"
    }

    private func importLessonCompletionKey(userID: String) -> String {
        "wander.walkthrough.\(userID).importLesson.complete"
    }

    private func checkpointKey(userID: String) -> String {
        "wander.walkthrough.\(userID).journeyCheckpoint"
    }

    private func legacyCheckpointKeys(for userID: String) -> [String] {
        let prefix = "wander.walkthrough.v"
        let suffix = ".\(userID).journeyCheckpoint"
        return defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(prefix) && $0.hasSuffix(suffix)
        }
    }

    private func legacyVersion10Keys(for userID: String) -> [String] {
        let prefix = "wander.walkthrough.v10.\(userID)."
        return defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
    }

    private func legacyRetirementKey(userID: String) -> String {
        "wander.walkthrough.\(userID).legacySessionRequiresRetirement"
    }

    private func legacyVersionedKeys(for userID: String, suffix: String) -> [String] {
        let prefix = "wander.walkthrough.v"
        let keySuffix = ".\(userID).\(suffix)"
        return defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(prefix) && $0.hasSuffix(keySuffix)
        }
    }

    private func migratedBoolean(stableKey: String, legacyKeys: [String]) -> Bool {
        if defaults.object(forKey: stableKey) != nil {
            return defaults.bool(forKey: stableKey)
        }
        let migrated = legacyKeys.contains { defaults.bool(forKey: $0) }
        if !legacyKeys.isEmpty {
            defaults.set(migrated, forKey: stableKey)
            legacyKeys.forEach(defaults.removeObject(forKey:))
        }
        return migrated
    }
}

/// Registers an authenticated launch once per account for the lifetime of the
/// app process, even when SwiftUI reconstructs the walkthrough coordinator.
/// Tests can inject a fresh registry to model a separate physical launch.
@MainActor
final class FirstVisitWalkthroughLaunchRegistry {
    static let process = FirstVisitWalkthroughLaunchRegistry()

    private var launchCountsByUserID: [String: Int] = [:]

    func launchCount(
        for userID: String,
        store: FirstVisitWalkthroughStore
    ) -> Int {
        if let registeredLaunchCount = launchCountsByUserID[userID] {
            return registeredLaunchCount
        }

        let launchCount = store.registerLaunch(for: userID)
        launchCountsByUserID[userID] = launchCount
        return launchCount
    }

    func reset(for userID: String) {
        launchCountsByUserID.removeValue(forKey: userID)
    }
}

@MainActor
final class FirstVisitWalkthroughCoordinator: ObservableObject {
    @Published private(set) var activeSurface: WalkthroughSurface?
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var requestedSurface: WalkthroughSurface?
    @Published private(set) var isPresentingImportLesson = false
    @Published private(set) var isPresentingDeviceFeaturesLesson = false
    @Published private(set) var tutorialCandidate: PlaceCandidate?
    @Published private(set) var tutorialUserPlaceID: String?
    @Published private(set) var tutorialMemorySnapshot: FirstVisitTutorialMemorySnapshot?
    @Published private(set) var tutorialSelectedStatus: PlaceStatus?
    @Published private(set) var tutorialDiscoverQuery: String?
    @Published private(set) var tutorialInvitedContactIDs: Set<String> = []
    @Published private(set) var isRequestingContactInvite = false
    @Published private(set) var userActivityGeneration = 0
    @Published private(set) var isAwaitingEligibilityResolution = false

    private(set) var userID: String
    private let store: FirstVisitWalkthroughStore
    private let launchRegistry: FirstVisitWalkthroughLaunchRegistry
    private var isImportLessonEligible = false
    private var isDeviceFeaturesLessonEligible = false
    private var didNotifyCompletion = false
    private var didAttemptCheckpointRestore = false
    private let onCompleted: (String) -> Void
    @Published private(set) var isEnabled: Bool

    init(
        userID: String = "local-user",
        store: FirstVisitWalkthroughStore = FirstVisitWalkthroughStore(),
        launchRegistry: FirstVisitWalkthroughLaunchRegistry = .process,
        isEnabled: Bool = true,
        onCompleted: @escaping (String) -> Void = { _ in }
    ) {
        self.userID = userID
        self.store = store
        self.launchRegistry = launchRegistry
        self.isEnabled = isEnabled
        self.onCompleted = onCompleted
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
        guard !isEnabled else {
            didAttemptCheckpointRestore = false
            return
        }

        activeSurface = nil
        currentStepIndex = 0
        requestedSurface = nil
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialCandidate = nil
        tutorialUserPlaceID = nil
        tutorialMemorySnapshot = nil
        tutorialSelectedStatus = nil
        tutorialDiscoverQuery = nil
        tutorialInvitedContactIDs = []
        isRequestingContactInvite = false
    }

    func setEligibilityResolutionPending(_ isPending: Bool) {
        guard isAwaitingEligibilityResolution != isPending else { return }
        isAwaitingEligibilityResolution = isPending
    }

    var currentStep: WalkthroughStep? {
        guard
            let activeSurface,
            let steps = FirstVisitWalkthroughContent.stepsBySurface[activeSurface],
            steps.indices.contains(currentStepIndex)
        else {
            return nil
        }
        return steps[currentStepIndex]
    }

    var isPresentingLaunchLesson: Bool {
        isPresentingImportLesson || isPresentingDeviceFeaturesLesson
    }

    var hasActivePresentation: Bool {
        activeSurface != nil
            || requestedSurface != nil
            || isPresentingLaunchLesson
            || isRequestingContactInvite
    }

    var hasActivePrimaryJourney: Bool {
        activeSurface.map(FirstVisitWalkthroughContent.primaryJourneySurfaces.contains) == true
            || requestedSurface.map(FirstVisitWalkthroughContent.primaryJourneySurfaces.contains) == true
            || store.checkpoint(for: userID) != nil
    }

    var hasCompletedPrimaryJourney: Bool {
        FirstVisitWalkthroughContent.primaryJourneySurfaces.allSatisfy {
            store.isComplete(for: userID, surface: $0)
        }
    }

    var canGoBack: Bool {
        guard
            let activeSurface,
            currentStepIndex > 0,
            let steps = FirstVisitWalkthroughContent.stepsBySurface[activeSurface],
            steps.indices.contains(currentStepIndex - 1)
        else { return false }

        return steps[currentStepIndex - 1].advance == .next
    }

    func setUserID(_ userID: String) {
        guard self.userID != userID else { return }
        self.userID = userID
        activeSurface = nil
        currentStepIndex = 0
        requestedSurface = nil
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialCandidate = nil
        tutorialUserPlaceID = nil
        tutorialMemorySnapshot = nil
        tutorialSelectedStatus = nil
        tutorialDiscoverQuery = nil
        tutorialInvitedContactIDs = []
        isRequestingContactInvite = false
        isAwaitingEligibilityResolution = false
        didNotifyCompletion = false
        didAttemptCheckpointRestore = false
    }

    func registerLaunch(
        forceImportLesson: Bool = false,
        forceDeviceFeaturesLesson: Bool = false
    ) {
        guard isEnabled else { return }

        let launchCount = launchRegistry.launchCount(for: userID, store: store)
        isImportLessonEligible = launchCount >= 2
            && !store.hasCompletedImportLesson(for: userID)
        isDeviceFeaturesLessonEligible = launchCount >= 3
            && !store.hasCompletedDeviceFeaturesLesson(for: userID)

        if forceImportLesson {
            isImportLessonEligible = true
            activeSurface = nil
            currentStepIndex = 0
            isPresentingImportLesson = true
            persistLaunchLessonCheckpoint(.importLesson)
        }

        if forceDeviceFeaturesLesson {
            isDeviceFeaturesLessonEligible = true
            activeSurface = nil
            currentStepIndex = 0
            isPresentingImportLesson = false
            isPresentingDeviceFeaturesLesson = true
            persistLaunchLessonCheckpoint(.deviceFeaturesLesson)
        }
        notifyCompletionIfNeeded()
    }

    @discardableResult
    func restoreJourneyIfNeeded(now: Date = .now) -> FirstVisitWalkthroughResumeDisposition {
        guard isEnabled else { return .none }
        if didAttemptCheckpointRestore {
            if let checkpoint = store.checkpoint(for: userID),
               now.timeIntervalSince(checkpoint.updatedAt) >= FirstVisitWalkthroughStore.resumeWindow {
                store.markEntireWalkthroughComplete(for: userID)
                clearTransientJourneyState()
                notifyCompletionIfNeeded()
                return .expired
            }
            return (activeSurface ?? requestedSurface)
                .map(FirstVisitWalkthroughResumeDisposition.resumed) ?? .none
        }
        didAttemptCheckpointRestore = true

        let hadCheckpointRecord = store.hasCheckpointRecord(for: userID)
        let checkpoint = store.checkpoint(for: userID)
        let requiresLegacyRetirement = store.requiresLegacySessionRetirement(for: userID)
        guard let checkpoint else {
            guard hadCheckpointRecord || requiresLegacyRetirement else { return .none }
            store.markEntireWalkthroughComplete(for: userID)
            clearTransientJourneyState()
            notifyCompletionIfNeeded()
            return .expired
        }
        let elapsed = now.timeIntervalSince(checkpoint.updatedAt)
        guard elapsed >= 0, elapsed < FirstVisitWalkthroughStore.resumeWindow else {
            store.markEntireWalkthroughComplete(for: userID)
            clearTransientJourneyState()
            notifyCompletionIfNeeded()
            return .expired
        }
        guard let surface = surface(containing: checkpoint.target),
              !FirstVisitWalkthroughContent.suppressedSurfaces.contains(surface),
              let checkpointIndex = FirstVisitWalkthroughContent.stepsBySurface[surface]?.firstIndex(where: {
                  $0.target == checkpoint.target
              })
        else {
            store.markEntireWalkthroughComplete(for: userID)
            clearTransientJourneyState()
            notifyCompletionIfNeeded()
            return .expired
        }

        tutorialCandidate = checkpoint.tutorialCandidate
        tutorialUserPlaceID = checkpoint.tutorialUserPlaceID
        tutorialMemorySnapshot = checkpoint.tutorialMemorySnapshot
        tutorialSelectedStatus = checkpoint.tutorialSelectedStatus
        tutorialDiscoverQuery = checkpoint.tutorialDiscoverQuery
        tutorialInvitedContactIDs = checkpoint.tutorialInvitedContactIDs ?? []
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        requestedSurface = nil

        switch checkpoint.presentation {
        case .importLesson:
            activeSurface = nil
            currentStepIndex = 0
            isPresentingImportLesson = true
            return .resumed(.map)
        case .deviceFeaturesLesson:
            activeSurface = nil
            currentStepIndex = 0
            isPresentingDeviceFeaturesLesson = true
            return .resumed(.map)
        case .awaitingDeviceFeaturesLesson:
            activeSurface = nil
            currentStepIndex = 0
            if isDeviceFeaturesLessonEligible {
                isPresentingDeviceFeaturesLesson = true
            }
            return .resumed(.map)
        case .contactInvite:
            guard let index = FirstVisitWalkthroughContent.stepsBySurface[.feed]?.firstIndex(
                where: { $0.target == .feedInvite }
            ) else {
                store.clearCheckpoint(for: userID)
                return .none
            }
            store.setProgress(index, for: userID, surface: .feed)
            activeSurface = .feed
            currentStepIndex = index
            isRequestingContactInvite = true
            return .resumed(.feed)
        case nil:
            break
        }

        let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
        let storedProgress = min(store.progress(for: userID, surface: surface), steps.count)
        guard !store.isComplete(for: userID, surface: surface),
              storedProgress < steps.count
        else {
            if !steps.isEmpty, storedProgress >= steps.count {
                store.markComplete(for: userID, surface: surface)
            }
            activeSurface = nil
            currentStepIndex = 0
            requestNextIncompleteDestination(after: surface)
            return requestedSurface
                .map(FirstVisitWalkthroughResumeDisposition.resumed) ?? .none
        }

        // The checkpoint is the durable record of what was visible when the
        // app suspended. A separately persisted progress value may be newer,
        // but it must never rewind behind that exact target.
        let resumeIndex = max(checkpointIndex, storedProgress)
        store.setProgress(resumeIndex, for: userID, surface: surface)
        activeSurface = surface
        currentStepIndex = resumeIndex
        return .resumed(surface)
    }

    func recordSuspension(at date: Date = .now) {
        if let presentation = activeCheckpointPresentation {
            if let target = currentStep?.target {
                persistCheckpoint(target: target, at: date, presentation: presentation)
            } else {
                persistLaunchLessonCheckpoint(presentation, at: date)
            }
        } else {
            persistCheckpoint(at: date)
        }
    }

    func activate(_ surface: WalkthroughSurface) {
        if let activeSurface,
           activeSurface != surface,
           FirstVisitWalkthroughContent.primaryJourneySurfaces.contains(activeSurface),
           FirstVisitWalkthroughContent.primaryJourneySurfaces.contains(surface),
           requestedSurface != surface {
            return
        }
        activate(surface, replacingActiveJourney: false)
    }

    func transition(to surface: WalkthroughSurface) {
        activate(surface, replacingActiveJourney: true)
    }

    private func activate(
        _ surface: WalkthroughSurface,
        replacingActiveJourney _: Bool
    ) {
        guard isEnabled else {
            activeSurface = nil
            return
        }
        guard !FirstVisitWalkthroughContent.suppressedSurfaces.contains(surface) else {
            if activeSurface == surface { activeSurface = nil }
            return
        }
        guard !isPresentingImportLesson, !isPresentingDeviceFeaturesLesson else { return }
        guard !store.isComplete(for: userID, surface: surface) else {
            if activeSurface == surface { activeSurface = nil }
            return
        }
        let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
        let progress = min(store.progress(for: userID, surface: surface), steps.count)
        guard progress < steps.count else {
            store.markComplete(for: userID, surface: surface)
            if activeSurface == surface { activeSurface = nil }
            return
        }
        activeSurface = surface
        currentStepIndex = progress
        persistCheckpoint()
    }

    func forceActivate(_ target: WalkthroughTargetID) {
        guard
            isEnabled,
            let surface = WalkthroughSurface.allCases.first(where: { surface in
                FirstVisitWalkthroughContent.stepsBySurface[surface]?.contains(where: {
                    $0.target == target
                }) == true
            }),
            !FirstVisitWalkthroughContent.suppressedSurfaces.contains(surface),
            let index = FirstVisitWalkthroughContent.stepsBySurface[surface]?.firstIndex(where: {
                $0.target == target
            })
        else { return }

        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        requestedSurface = nil
        store.setProgress(index, for: userID, surface: surface)
        activeSurface = surface
        currentStepIndex = index
        persistCheckpoint()
    }

    /// Starts a deterministic debug replay without carrying completion from a
    /// previous device run into later parts of the journey.
    func prepareDebugReplay(at target: WalkthroughTargetID) {
        guard isEnabled else { return }
        resetCurrentUser()
        forceActivate(target)
    }

    func perform(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target, currentStep?.advance == .action else { return }
        if target == .feedSearchResultsBack {
            completeAction(target, transitioningImmediatelyTo: .feed)
            return
        }
        advance()
    }

    /// Discover is presented above Feed. Returning through a transient
    /// `requestedSurface` left a timing window where cover dismissal consumed
    /// the handoff before Feed remounted its walkthrough presenter.
    private func completeAction(
        _ target: WalkthroughTargetID,
        transitioningImmediatelyTo destination: WalkthroughSurface
    ) {
        guard currentStep?.target == target,
              currentStep?.advance == .action,
              let source = activeSurface
        else { return }

        let sourceSteps = FirstVisitWalkthroughContent.stepsBySurface[source, default: []]
        let sourceNextIndex = currentStepIndex + 1
        store.setProgress(sourceNextIndex, for: userID, surface: source)
        if sourceNextIndex >= sourceSteps.count {
            store.markComplete(for: userID, surface: source)
        }

        guard let destinationTarget = nextIncompleteTarget(for: destination),
              let destinationIndex = FirstVisitWalkthroughContent.stepsBySurface[destination]?
                .firstIndex(where: { $0.target == destinationTarget })
        else {
            activeSurface = nil
            currentStepIndex = 0
            requestedSurface = nil
            requestNextIncompleteDestination(after: destination)
            return
        }

        requestedSurface = nil
        activeSurface = destination
        currentStepIndex = destinationIndex
        persistCheckpoint()
    }

    func perform(
        _ target: WalkthroughTargetID,
        transitioningTo destination: WalkthroughSurface
    ) {
        guard currentStep?.target == target,
              currentStep?.advance == .action,
              let source = activeSurface
        else { return }

        let sourceSteps = FirstVisitWalkthroughContent.stepsBySurface[source, default: []]
        let sourceNextIndex = currentStepIndex + 1
        store.setProgress(sourceNextIndex, for: userID, surface: source)
        if sourceNextIndex >= sourceSteps.count {
            store.markComplete(for: userID, surface: source)
        }

        let destinationSteps = FirstVisitWalkthroughContent.stepsBySurface[destination, default: []]
        let destinationIndex = min(
            store.progress(for: userID, surface: destination),
            destinationSteps.count
        )
        guard destinationSteps.indices.contains(destinationIndex) else { return }

        requestedSurface = nil
        activeSurface = destination
        currentStepIndex = destinationIndex
        persistCheckpoint()
    }

    func advancePassiveStep() {
        guard currentStep?.advance == .next else { return }
        if currentStep?.target == .feedInvite {
            isRequestingContactInvite = true
            persistCheckpoint()
            return
        }
        advance()
    }

    func recordUserActivity() {
        guard isEnabled, currentStep?.advance == .next else { return }
        userActivityGeneration &+= 1
    }

    func goBack() {
        guard canGoBack, let surface = activeSurface else { return }
        let previousIndex = currentStepIndex - 1
        isRequestingContactInvite = false
        store.setProgress(previousIndex, for: userID, surface: surface)
        currentStepIndex = previousIndex
        persistCheckpoint()
    }

    func completeContactInviteRequest() {
        guard isRequestingContactInvite, currentStep?.target == .feedInvite else { return }
        isRequestingContactInvite = false
        tutorialInvitedContactIDs = []
        advance()
    }

    func recordTutorialInvitedContactIDs(_ contactIDs: Set<String>) {
        guard isRequestingContactInvite, currentStep?.target == .feedInvite else { return }
        tutorialInvitedContactIDs = contactIDs
        persistCheckpoint()
    }

    func recoverUnavailableTarget(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target else { return }
        advance()
    }

    func recordTutorialCandidate(_ candidate: PlaceCandidate) {
        tutorialCandidate = candidate
        persistCheckpoint()
    }

    func recordTutorialSelectedStatus(_ status: PlaceStatus) {
        tutorialSelectedStatus = status
        persistCheckpoint()
    }

    func rewindTutorialSaveStatusSelection() {
        guard activeSurface == .saveFlow,
              let index = FirstVisitWalkthroughContent.stepsBySurface[.saveFlow]?
                .firstIndex(where: { $0.target == .saveStatus })
        else { return }
        tutorialSelectedStatus = nil
        store.setProgress(index, for: userID, surface: .saveFlow)
        currentStepIndex = index
        persistCheckpoint()
    }

    func recordTutorialDiscoverQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        tutorialDiscoverQuery = trimmed.isEmpty ? nil : trimmed
        persistCheckpoint()
    }

    func recordTutorialSave(userPlaceID: String) {
        guard activeSurface == .saveFlow else { return }
        tutorialUserPlaceID = userPlaceID
        persistCheckpoint()
    }

    func recordTutorialMemorySnapshot(_ snapshot: FirstVisitTutorialMemorySnapshot) {
        tutorialCandidate = snapshot.candidate
        tutorialMemorySnapshot = snapshot
        persistCheckpoint()
    }

    func resetCurrentUser() {
        store.reset(for: userID)
        activeSurface = nil
        currentStepIndex = 0
        launchRegistry.reset(for: userID)
        requestedSurface = nil
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialCandidate = nil
        tutorialUserPlaceID = nil
        tutorialMemorySnapshot = nil
        tutorialSelectedStatus = nil
        tutorialDiscoverQuery = nil
        tutorialInvitedContactIDs = []
        isRequestingContactInvite = false
        isAwaitingEligibilityResolution = false
        didNotifyCompletion = false
        didAttemptCheckpointRestore = false
    }

    func presentLaunchLessonIfEligible() {
        guard
            isEnabled,
            store.checkpoint(for: userID) == nil,
            activeSurface == nil,
            !isPresentingImportLesson,
            !isPresentingDeviceFeaturesLesson
        else { return }

        if isDeviceFeaturesLessonEligible {
            isPresentingDeviceFeaturesLesson = true
            persistLaunchLessonCheckpoint(.deviceFeaturesLesson)
        } else if isImportLessonEligible {
            isPresentingImportLesson = true
            persistLaunchLessonCheckpoint(.importLesson)
        }
    }

    func completeImportLesson() {
        guard isPresentingImportLesson else { return }
        store.markImportLessonComplete(for: userID)
        isImportLessonEligible = false
        isPresentingImportLesson = false
        // Keep the 12-hour abandonment clock alive while this new user waits
        // for the third-launch device-features lesson.
        persistLaunchLessonCheckpoint(.awaitingDeviceFeaturesLesson)
        notifyCompletionIfNeeded()
    }

    func completeDeviceFeaturesLesson() {
        guard isPresentingDeviceFeaturesLesson else { return }
        store.markDeviceFeaturesLessonComplete(for: userID)
        isDeviceFeaturesLessonEligible = false
        isPresentingDeviceFeaturesLesson = false
        store.clearCheckpoint(for: userID)
        notifyCompletionIfNeeded()
    }

    func dismissEntireWalkthrough() {
        guard isEnabled else { return }
        store.markEntireWalkthroughComplete(for: userID)
        clearTransientJourneyState()
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        notifyCompletionIfNeeded()
    }

    /// Clears stale local NUX state for an account that is definitively not
    /// eligible. This deliberately does not call the completion callback:
    /// enrollment retirement is owned by AppEntry and may already be complete.
    func retireJourneyForDisabledExperience() {
        store.markEntireWalkthroughComplete(for: userID)
        clearTransientJourneyState()
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        didAttemptCheckpointRestore = true
        didNotifyCompletion = true
    }

    func consumeRequestedSurface(_ surface: WalkthroughSurface) {
        guard requestedSurface == surface else { return }
        requestedSurface = nil
        // A normal handoff activates `surface` immediately after consuming it.
        // If old persisted state already completed that destination—or reached
        // terminal progress without writing its completion bit—reroute now so
        // the activation no-op cannot strand the journey.
        guard nextIncompleteTarget(for: surface) == nil else { return }
        requestNextIncompleteDestination(after: surface)
    }

    private func advance() {
        guard let surface = activeSurface else { return }
        let nextIndex = currentStepIndex + 1
        let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
        store.setProgress(nextIndex, for: userID, surface: surface)
        if nextIndex >= steps.count {
            store.markComplete(for: userID, surface: surface)
            activeSurface = nil
            currentStepIndex = 0
            requestedSurface = nil
            if surface == .sendoff {
                store.clearCheckpoint(for: userID)
            } else {
                // Resolve and persist the next usable destination now. This
                // prevents a force-quit between completion and tab routing from
                // saving a checkpoint for an already-completed surface.
                requestNextIncompleteDestination(after: surface)
            }
            notifyCompletionIfNeeded()
        } else {
            currentStepIndex = nextIndex
            persistCheckpoint()
        }
    }

    private func destination(after surface: WalkthroughSurface) -> WalkthroughSurface? {
        switch surface {
        case .map:
            // The Map chapter ends on "One more shortcut". Its destination is
            // the already-open Add sheet so the remaining Import lesson can
            // attach before the finale.
            .add
        case .placeDetail:
            .feed
        case .sendoff:
            nil
        case .add:
            .sendoff
        case .saveFlow:
            .map
        case .feed:
            .lists
        case .listEditor:
            .lists
        case .listDetail:
            .lists
        case .feedSearch:
            .feed
        case .lists:
            .sendoff
        case .profile:
            .sendoff
        }
    }

    /// A requested handoff can encounter completion saved by an older replay
    /// or interrupted build. Keep moving through the intended journey instead
    /// of consuming the request and leaving the user with no active lesson.
    private func requestNextIncompleteDestination(after surface: WalkthroughSurface) {
        var visited: Set<WalkthroughSurface> = [surface]
        var candidate = destination(after: surface)

        while let nextSurface = candidate, visited.insert(nextSurface).inserted {
            if let nextTarget = nextIncompleteTarget(for: nextSurface) {
                requestedSurface = nextSurface
                persistCheckpoint(target: nextTarget)
                return
            }
            candidate = destination(after: nextSurface)
        }

        // There is nowhere valid to move forward. Normalize only the primary
        // walkthrough so the user enters the clean app instead of restarting
        // at Map; launch-two Import and launch-three device tips remain intact.
        store.markPrimaryJourneyComplete(for: userID)
        notifyCompletionIfNeeded()
    }

    private func surface(containing target: WalkthroughTargetID) -> WalkthroughSurface? {
        WalkthroughSurface.allCases.first { surface in
            FirstVisitWalkthroughContent.stepsBySurface[surface]?.contains(where: {
                $0.target == target
            }) == true
        }
    }

    private func nextIncompleteTarget(for surface: WalkthroughSurface) -> WalkthroughTargetID? {
        guard !FirstVisitWalkthroughContent.suppressedSurfaces.contains(surface),
              !store.isComplete(for: userID, surface: surface)
        else { return nil }

        let steps = FirstVisitWalkthroughContent.stepsBySurface[surface, default: []]
        guard !steps.isEmpty else { return nil }
        let progress = min(store.progress(for: userID, surface: surface), steps.count)
        guard progress < steps.count else {
            store.markComplete(for: userID, surface: surface)
            return nil
        }
        return steps[progress].target
    }

    private func persistCheckpoint(at date: Date = .now) {
        guard let target = currentStep?.target else { return }
        persistCheckpoint(target: target, at: date)
    }

    private func persistCheckpoint(
        target: WalkthroughTargetID,
        at date: Date = .now,
        presentation: FirstVisitWalkthroughCheckpointPresentation? = nil
    ) {
        guard FirstVisitWalkthroughContent.primaryJourneySurfaces.contains(where: { surface in
            FirstVisitWalkthroughContent.stepsBySurface[surface]?.contains(where: {
                $0.target == target
            }) == true
        }) else { return }

        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: target,
                updatedAt: date,
                tutorialCandidate: tutorialCandidate,
                tutorialUserPlaceID: tutorialUserPlaceID,
                tutorialMemorySnapshot: tutorialMemorySnapshot,
                tutorialSelectedStatus: tutorialSelectedStatus,
                tutorialDiscoverQuery: tutorialDiscoverQuery,
                tutorialInvitedContactIDs: tutorialInvitedContactIDs.isEmpty
                    ? nil
                    : tutorialInvitedContactIDs,
                presentation: presentation ?? activeCheckpointPresentation
            ),
            for: userID
        )
    }

    private var activeCheckpointPresentation: FirstVisitWalkthroughCheckpointPresentation? {
        if isPresentingImportLesson { return .importLesson }
        if isPresentingDeviceFeaturesLesson { return .deviceFeaturesLesson }
        if isRequestingContactInvite { return .contactInvite }
        return nil
    }

    private func persistLaunchLessonCheckpoint(
        _ presentation: FirstVisitWalkthroughCheckpointPresentation,
        at date: Date = .now
    ) {
        store.setCheckpoint(
            FirstVisitWalkthroughCheckpoint(
                target: .mapAdd,
                updatedAt: date,
                tutorialCandidate: tutorialCandidate,
                tutorialUserPlaceID: tutorialUserPlaceID,
                tutorialMemorySnapshot: tutorialMemorySnapshot,
                tutorialSelectedStatus: tutorialSelectedStatus,
                tutorialDiscoverQuery: tutorialDiscoverQuery,
                tutorialInvitedContactIDs: tutorialInvitedContactIDs.isEmpty
                    ? nil
                    : tutorialInvitedContactIDs,
                presentation: presentation
            ),
            for: userID
        )
    }

    private func clearTransientJourneyState() {
        activeSurface = nil
        currentStepIndex = 0
        requestedSurface = nil
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialCandidate = nil
        tutorialUserPlaceID = nil
        tutorialMemorySnapshot = nil
        tutorialSelectedStatus = nil
        tutorialDiscoverQuery = nil
        tutorialInvitedContactIDs = []
        isRequestingContactInvite = false
    }

    private func notifyCompletionIfNeeded() {
        guard !didNotifyCompletion,
              store.hasCompletedEntireWalkthrough(for: userID)
        else { return }
        didNotifyCompletion = true
        onCompleted(userID)
    }
}

private struct WalkthroughTargetAnchors {
    var spotlights: [WalkthroughTargetID: [Anchor<CGRect>]] = [:]
    var emphases: [WalkthroughTargetID: [Anchor<CGRect>]] = [:]
}

private struct WalkthroughTargetPreferenceKey: PreferenceKey {
    static let defaultValue = WalkthroughTargetAnchors()

    static func reduce(
        value: inout WalkthroughTargetAnchors,
        nextValue: () -> WalkthroughTargetAnchors
    ) {
        let next = nextValue()
        for (target, anchors) in next.spotlights {
            value.spotlights[target, default: []].append(contentsOf: anchors)
        }
        for (target, anchors) in next.emphases {
            value.emphases[target, default: []].append(contentsOf: anchors)
        }
    }
}

extension View {
    func walkthroughTarget(_ target: WalkthroughTargetID?) -> some View {
        transformAnchorPreference(key: WalkthroughTargetPreferenceKey.self, value: .bounds) { value, anchor in
            guard let target else { return }
            value.spotlights[target, default: []].append(anchor)
        }
    }

    func walkthroughTargets(_ targets: [WalkthroughTargetID]) -> some View {
        transformAnchorPreference(key: WalkthroughTargetPreferenceKey.self, value: .bounds) { value, anchor in
            for target in targets {
                value.spotlights[target, default: []].append(anchor)
            }
        }
    }

    func walkthroughEmphasis(_ target: WalkthroughTargetID?) -> some View {
        transformAnchorPreference(key: WalkthroughTargetPreferenceKey.self, value: .bounds) { value, anchor in
            guard let target else { return }
            value.emphases[target, default: []].append(anchor)
        }
    }

    func walkthroughTargetAndEmphasis(_ target: WalkthroughTargetID?) -> some View {
        transformAnchorPreference(key: WalkthroughTargetPreferenceKey.self, value: .bounds) { value, anchor in
            guard let target else { return }
            value.spotlights[target, default: []].append(anchor)
            value.emphases[target, default: []].append(anchor)
        }
    }

    func firstVisitWalkthroughOverlay(
        _ coordinator: FirstVisitWalkthroughCoordinator,
        surface: WalkthroughSurface,
        externalTargetFrames: [WalkthroughTargetID: CGRect] = [:]
    ) -> some View {
        modifier(
            FirstVisitWalkthroughModifier(
                coordinator: coordinator,
                surface: surface,
                externalTargetFrames: externalTargetFrames
            )
        )
    }

    func walkthroughPresenterScrim(isPresented: Bool) -> some View {
        overlay {
            if isPresented {
                WalkthroughFullScreenScrim()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }

    func walkthroughLaunchLessonOverlay(
        _ coordinator: FirstVisitWalkthroughCoordinator,
        onOpenImport: @escaping () -> Void
    ) -> some View {
        overlay {
            if coordinator.isPresentingImportLesson {
                ImportWalkthroughOverlay(
                    onDismiss: coordinator.dismissEntireWalkthrough,
                    onOpenImport: {
                        coordinator.completeImportLesson()
                        onOpenImport()
                    }
                )
                .transition(.opacity)
                .zIndex(2_000)
            } else if coordinator.isPresentingDeviceFeaturesLesson {
                DeviceFeaturesWalkthroughOverlay(
                    onDismiss: coordinator.dismissEntireWalkthrough,
                    onComplete: coordinator.completeDeviceFeaturesLesson
                )
                .transition(.opacity)
                .zIndex(2_000)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.isPresentingImportLesson)
    }
}

enum WalkthroughHelpDestination {
    static let extensions = URL(string: "https://getrec.me/extensions")!
}

enum ImportWalkthroughContent {
    static let title = "Bring every saved place with you"
    static let message = "Paste one place, a few links, or a whole list from Maps, Instagram, TikTok, or Notes. Choose what to keep and mark each Check In or Wanna before anything reaches your map"
    static let actionTitle = "Open import form"
    static let helpURL = ImportHelpDestination.url
}

private struct ImportWalkthroughOverlay: View {
    @Environment(\.openURL) private var openURL

    let onDismiss: () -> Void
    let onOpenImport: () -> Void

    var body: some View {
        ZStack {
            WalkthroughFullScreenScrim()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                HStack(alignment: .center) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 23, weight: .black))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .frame(width: 52, height: 52)
                        .background(WanderTheme.terracotta.color, in: Circle())

                    Spacer()

                    Button {
                        openURL(ImportWalkthroughContent.helpURL)
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .frame(width: 44, height: 44)
                            .background(WanderTheme.surfaceSand.color, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Import help")
                    .accessibilityHint("Opens import help on getrec.me")

                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(ImportWalkthroughContent.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(ImportWalkthroughContent.message)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(ImportWalkthroughContent.actionTitle, action: onOpenImport)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
            }
            .padding(WanderTheme.spacing4)
            .frame(maxWidth: 360)
            .background(
                WanderTheme.surfaceBone.color,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(WanderTheme.textInk.color.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
            .padding(.horizontal, WanderTheme.spacing4)
            .walkthroughEntranceBounce()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.importLesson")
    }
}

private struct DeviceFeaturesWalkthroughOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActionButtonPulsing = false
    let onDismiss: () -> Void
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            WalkthroughFullScreenScrim()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    ZStack {
                        Circle()
                            .fill(WanderTheme.terracotta.color.opacity(0.18))
                            .frame(width: 42, height: 42)
                            .scaleEffect(
                                reduceMotion ? 1 : (isActionButtonPulsing ? 1.12 : 0.88)
                            )
                            .opacity(
                                reduceMotion ? 1 : (isActionButtonPulsing ? 0.42 : 0.12)
                            )
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                                value: isActionButtonPulsing
                            )

                        Circle()
                            .fill(WanderTheme.terracotta.color)
                            .frame(width: 36, height: 36)

                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(WanderTheme.textOnAction.color)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("rec.me, one press away")
                            .font(WanderTypography.editorialCardTitle)
                            .foregroundStyle(WanderTheme.textInk.color)

                        Text("Set these up once for faster saves")
                            .font(WanderTypography.metadata)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                }
                .padding(.bottom, WanderTheme.spacing3)

                Divider()
                    .overlay(WanderTheme.borderHairline.color)

                VStack(spacing: 0) {
                    DeviceFeatureInstruction(
                        systemImage: "button.programmable",
                        title: "Action Button + Controls",
                        instruction: "Choose rec.me Check In for a one-press save",
                        accessibilityIdentifier: "walkthrough.deviceFeatures.actionButton"
                    )

                    Divider()
                        .padding(.leading, 40)
                        .overlay(WanderTheme.borderHairline.color)

                    DeviceFeatureInstruction(
                        systemImage: "square.grid.2x2.fill",
                        title: "Home + Lock Screen widgets",
                        instruction: "Keep Quick Add, Search, Activity, or Nearby in view",
                        accessibilityIdentifier: "walkthrough.deviceFeatures.widgets"
                    )

                    Divider()
                        .padding(.leading, 40)
                        .overlay(WanderTheme.borderHairline.color)

                    DeviceFeatureInstruction(
                        systemImage: "square.and.arrow.up.fill",
                        title: "Share extension",
                        instruction: "Send places from Maps, Instagram, TikTok, or Safari",
                        accessibilityIdentifier: "walkthrough.deviceFeatures.shareExtension"
                    )
                }

                HStack(spacing: WanderTheme.spacing2) {
                    Link(destination: WalkthroughHelpDestination.extensions) {
                        Label("Setup guide", systemImage: "arrow.up.right")
                            .font(WanderTypography.label)
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens getrec.me/extensions")
                    .accessibilityIdentifier("walkthrough.deviceFeatures.extensionsGuide")

                    Spacer(minLength: WanderTheme.spacing2)

                    Button(action: onComplete) {
                        HStack(spacing: 6) {
                            Text("Got it")
                            Image(systemName: "arrow.right")
                        }
                        .font(WanderTypography.control)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minWidth: 104, minHeight: 44)
                        .contentShape(Capsule())
                        .wanderGlassCapsule(tone: .accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("walkthrough.deviceFeatures.complete")
                }
                .padding(.top, WanderTheme.spacing2)
            }
            .padding(WanderTheme.spacing4)
            .frame(maxWidth: 344)
            .background(
                WanderTheme.surfaceBone.color,
                in: RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous)
                    .stroke(WanderTheme.terracotta.color.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            .padding(.horizontal, WanderTheme.spacing4)
            .walkthroughEntranceBounce()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("walkthrough.deviceFeatures.card")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.deviceFeatures")
        .onAppear {
            guard !reduceMotion else { return }
            isActionButtonPulsing = true
        }
    }
}

private struct DeviceFeatureInstruction: View {
    let systemImage: String
    let title: String
    let instruction: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(width: 28, height: 28)
                .background(WanderTheme.terracotta.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WanderTypography.editorialCompactTitle)
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(instruction)
                    .font(WanderTypography.metadata)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct WalkthroughEntranceBounceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    let isPresented: Bool
    let trigger: String

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.92)
            .task(id: "\(trigger).\(isPresented)") {
                guard isPresented else {
                    hasAppeared = false
                    return
                }
                hasAppeared = false
                await Task.yield()
                guard !Task.isCancelled else { return }
                reveal()
            }
    }

    private func reveal() {
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.32)) {
            hasAppeared = true
        }
    }
}

private extension View {
    func walkthroughEntranceBounce(
        isPresented: Bool = true,
        trigger: String = "appearance"
    ) -> some View {
        modifier(
            WalkthroughEntranceBounceModifier(
                isPresented: isPresented,
                trigger: trigger
            )
        )
    }
}

private struct WalkthroughSlowPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                reduceMotion || !isActive
                    ? 1
                    : (isExpanded ? 1.06 : 1)
            )
            .onAppear { updatePulse() }
            .onChange(of: isActive) { _, _ in updatePulse() }
            .animation(
                reduceMotion || !isActive
                    ? nil
                    : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: isExpanded
            )
    }

    private func updatePulse() {
        isExpanded = isActive && !reduceMotion
    }
}

extension View {
    func walkthroughSlowPulse(isActive: Bool) -> some View {
        modifier(WalkthroughSlowPulseModifier(isActive: isActive))
    }
}

private struct FirstVisitWalkthroughModifier: ViewModifier {
    @ObservedObject var coordinator: FirstVisitWalkthroughCoordinator
    let surface: WalkthroughSurface
    let externalTargetFrames: [WalkthroughTargetID: CGRect]

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.activate(surface) }
            .onChange(of: surface) { _, newSurface in coordinator.activate(newSurface) }
            .walkthroughPresenterScrim(
                isPresented: coordinator.isRequestingContactInvite
                    && coordinator.activeSurface == surface
            )
            .overlayPreferenceValue(WalkthroughTargetPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    let anchoredTargetFrames = coordinator.currentStep.map { step in
                        resolvedWalkthroughFrames(anchors.spotlights[step.target], in: proxy)
                    } ?? []
                    let externalTargetFrame = coordinator.currentStep.flatMap { step in
                        resolvedExternalTargetFrame(for: step.target, in: proxy)
                    }
                    let targetFrames = externalTargetFrame.map { [$0] }
                        ?? anchoredTargetFrames
                    let targetFrame = resolvedWalkthroughFrame(targetFrames)
                    if
                        coordinator.activeSurface == surface,
                        let step = coordinator.currentStep,
                        let targetFrame
                    {
                        if targetFrame.intersects(CGRect(origin: .zero, size: proxy.size)),
                           targetFrame.width > 0,
                           targetFrame.height > 0 {
                            FirstVisitWalkthroughOverlay(
                                step: step,
                                targetFrame: targetFrame,
                                targetFrames: targetFrames,
                                emphasisFrames: resolvedWalkthroughFrames(
                                    anchors.emphases[step.target],
                                    in: proxy
                                ),
                                containerSize: proxy.size,
                                userActivityGeneration: coordinator.userActivityGeneration,
                                onDismiss: coordinator.dismissEntireWalkthrough,
                                onBack: step.allowsBackNavigation && coordinator.canGoBack
                                    ? { coordinator.goBack() }
                                    : nil,
                                onNext: coordinator.advancePassiveStep
                            )
                            .id(step.id)
                            .transition(.opacity)
                        } else {
                            MissingWalkthroughTargetResolver(coordinator: coordinator, step: step)
                        }
                    } else if coordinator.activeSurface == surface, let step = coordinator.currentStep {
                        MissingWalkthroughTargetResolver(coordinator: coordinator, step: step)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: coordinator.currentStep?.id)
                .ignoresSafeArea()
                .zIndex(1_000)
            }
    }

    private func resolvedWalkthroughFrame(_ frames: [CGRect]) -> CGRect? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    private func resolvedExternalTargetFrame(
        for target: WalkthroughTargetID,
        in proxy: GeometryProxy
    ) -> CGRect? {
        guard let windowFrame = externalTargetFrames[target] else { return nil }
        let proxyFrame = proxy.frame(in: .global)
        let localFrame = windowFrame.offsetBy(dx: -proxyFrame.minX, dy: -proxyFrame.minY)
        let bounds = CGRect(origin: .zero, size: proxy.size)
        guard localFrame.width > 0,
              localFrame.height > 0,
              localFrame.intersects(bounds)
        else { return nil }
        return localFrame.intersection(bounds)
    }

    private func resolvedWalkthroughFrames(
        _ anchors: [Anchor<CGRect>]?,
        in proxy: GeometryProxy
    ) -> [CGRect] {
        guard let anchors, !anchors.isEmpty else { return [] }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        return anchors
            .map { proxy[$0] }
            .filter { $0.width > 0 && $0.height > 0 && $0.intersects(bounds) }
    }
}

private struct MissingWalkthroughTargetResolver: View {
    @ObservedObject var coordinator: FirstVisitWalkthroughCoordinator
    let step: WalkthroughStep

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .task(id: step.id) {
                guard step.automaticallyRecoversWhenTargetIsMissing else { return }
                try? await Task.sleep(for: .milliseconds(2_500))
                guard !Task.isCancelled else { return }
                coordinator.recoverUnavailableTarget(step.target)
            }
    }
}

struct WalkthroughCoachMarkLayout: Equatable {
    let targetFrame: CGRect
    let containerSize: CGSize
    let cardSize: CGSize
    let spotlightInset: CGFloat

    private let screenMargin: CGFloat = 16
    private let pointerHeight: CGFloat = 12
    private let pointerCornerClearance: CGFloat = 28

    init(
        targetFrame: CGRect,
        containerSize: CGSize,
        cardSize: CGSize,
        spotlightInset: CGFloat = 8
    ) {
        self.targetFrame = targetFrame
        self.containerSize = containerSize
        self.cardSize = cardSize
        self.spotlightInset = spotlightInset
    }

    var spotlightFrame: CGRect {
        targetFrame
            .insetBy(dx: -spotlightInset, dy: -spotlightInset)
            .intersection(CGRect(origin: .zero, size: containerSize))
    }

    var cardAboveTarget: Bool {
        let requiredSpace = cardSize.height + pointerHeight
        let spaceAbove = spotlightFrame.minY - screenMargin
        let spaceBelow = containerSize.height - spotlightFrame.maxY - screenMargin
        if spaceAbove >= requiredSpace, spaceBelow < requiredSpace { return true }
        if spaceBelow >= requiredSpace, spaceAbove < requiredSpace { return false }
        return spaceAbove > spaceBelow
    }

    var cardFrame: CGRect {
        let minY = cardAboveTarget
            ? spotlightFrame.minY - pointerHeight - cardSize.height
            : spotlightFrame.maxY + pointerHeight
        let desiredMinX = spotlightFrame.midX - cardSize.width / 2
        let minX = min(
            max(desiredMinX, screenMargin),
            containerSize.width - cardSize.width - screenMargin
        )
        return CGRect(origin: CGPoint(x: minX, y: minY), size: cardSize)
    }

    var pointerX: CGFloat {
        min(
            max(spotlightFrame.midX - cardFrame.minX, pointerCornerClearance),
            cardSize.width - pointerCornerClearance
        )
    }

    var pointerTip: CGPoint {
        CGPoint(
            x: cardFrame.minX + pointerX,
            y: cardAboveTarget ? cardFrame.maxY + pointerHeight : cardFrame.minY - pointerHeight
        )
    }
}

private struct FirstVisitWalkthroughOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredCardSize = CGSize(width: 280, height: 104)
    @State private var hasNarrowedFeaturedSpotlight = false
    @State private var isFeaturedCoachVisible = false
    @State private var hasRevealedDelayedTarget = false
    @State private var isNextArrowNudging = false

    let step: WalkthroughStep
    let targetFrame: CGRect
    let targetFrames: [CGRect]
    let emphasisFrames: [CGRect]
    let containerSize: CGSize
    let userActivityGeneration: Int
    let onDismiss: () -> Void
    let onBack: (() -> Void)?
    let onNext: () -> Void

    private var cardWidth: CGFloat {
        if step.target == .mapFeatured {
            return min(270, max(244, containerSize.width - 32))
        }
        if step.target == .mapFriends || step.target == .mapYou {
            return min(264, max(244, containerSize.width - 32))
        }
        let characterCount = step.title.count + step.message.count
        let preferred: CGFloat
        if characterCount < 80 {
            preferred = 272
        } else if characterCount < 132 {
            preferred = 306
        } else {
            preferred = 326
        }
        return min(preferred, max(240, containerSize.width - 32))
    }

    private var layout: WalkthroughCoachMarkLayout {
        WalkthroughCoachMarkLayout(
            targetFrame: activeTargetFrame,
            containerSize: containerSize,
            cardSize: CGSize(width: cardWidth, height: max(measuredCardSize.height, 1)),
            spotlightInset: spotlightInset
        )
    }

    private var spotlightInset: CGFloat {
        switch step.target {
        case .addSearch:
            6
        case .addPlace, .addImport:
            12
        case .mapTabs:
            3
        default:
            8
        }
    }

    private var activeTargetFrame: CGRect {
        guard step.target == .mapFeatured,
              reduceMotion || hasNarrowedFeaturedSpotlight,
              let featuredFrame = targetFrames.min(by: { lhs, rhs in
                  lhs.width * lhs.height < rhs.width * rhs.height
              })
        else { return targetFrame }
        return featuredFrame
    }

    private var isCoachVisible: Bool {
        step.presentationStyle == .coach
            && (step.target != .mapFeatured || reduceMotion || isFeaturedCoachVisible)
    }

    private var isCompactFilterCoach: Bool {
        step.target == .mapFeatured || step.target == .mapFriends || step.target == .mapYou
    }

    private var visibleEmphasisFrames: [CGRect] {
        guard step.allowsTargetInteraction else { return [] }
        if step.target == .mapFeatured {
            return []
        }
        if delayedTargetMilliseconds != nil, !hasRevealedDelayedTarget {
            return []
        }
        if step.spotlightStyle == .clearPage {
            return emphasisFrames.isEmpty ? targetFrames : emphasisFrames
        }
        return emphasisFrames
    }

    private var delayedTargetMilliseconds: Int? {
        guard case .delayedTargetOnly(let milliseconds) = step.presentationStyle else {
            return nil
        }
        return milliseconds
    }

    private var shouldShowScrim: Bool {
        guard step.spotlightStyle == .focused else { return false }
        return delayedTargetMilliseconds == nil || hasRevealedDelayedTarget
    }

    private var allowsSpotlightInteraction: Bool {
        step.allowsTargetInteraction
            && (delayedTargetMilliseconds == nil || hasRevealedDelayedTarget)
    }

    var body: some View {
        ZStack {
            if step.presentationStyle == .finale {
                WalkthroughFinaleView(
                    step: step,
                    containerSize: containerSize,
                    onDismiss: onDismiss,
                    onFinish: onNext
                )
            } else {
                if shouldShowScrim {
                    WalkthroughScrim(
                        spotlightFrame: layout.spotlightFrame,
                        containerSize: containerSize,
                        cornerRadius: step.target == .mapTabs ? 34 : WanderTheme.radiusLarge
                    )
                    .allowsHitTesting(false)
                }

                WalkthroughTouchShield(
                    containerSize: containerSize,
                    spotlightFrame: layout.spotlightFrame,
                    allowsSpotlightInteraction: allowsSpotlightInteraction
                )

                ForEach(Array(visibleEmphasisFrames.enumerated()), id: \.offset) { _, frame in
                    WalkthroughEmphasisRing(
                        frame: frame,
                        cornerRadius: emphasisCornerRadius(for: frame)
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }

                if step.presentationStyle == .coach {
                    coachMark
                }

                if delayedTargetMilliseconds != nil, hasRevealedDelayedTarget {
                    Text("Highlighted walkthrough action is ready")
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .position(x: 1, y: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("walkthrough.\(step.id)")
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: step.id)
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68),
            value: activeTargetFrame
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78),
            value: isFeaturedCoachVisible
        )
        .task(id: "featured-\(step.id)") {
            hasNarrowedFeaturedSpotlight = false
            isFeaturedCoachVisible = false
            guard step.target == .mapFeatured else { return }
            guard !reduceMotion else {
                hasNarrowedFeaturedSpotlight = true
                isFeaturedCoachVisible = true
                return
            }
            try? await Task.sleep(for: .milliseconds(820))
            guard !Task.isCancelled else { return }
            hasNarrowedFeaturedSpotlight = true
            try? await Task.sleep(for: .milliseconds(430))
            guard !Task.isCancelled else { return }
            isFeaturedCoachVisible = true
        }
        .task(id: "delayed-target-\(step.id)") {
            hasRevealedDelayedTarget = delayedTargetMilliseconds == nil
            guard let delayedTargetMilliseconds else { return }
            try? await Task.sleep(for: .milliseconds(delayedTargetMilliseconds))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                hasRevealedDelayedTarget = true
            }
        }
        .task(id: "next-nudge-\(step.id)-\(userActivityGeneration)") {
            isNextArrowNudging = false
            guard step.presentationStyle == .coach,
                  step.advance == .next,
                  !step.automaticallyAdvances,
                  !reduceMotion
            else { return }
            try? await Task.sleep(
                for: .milliseconds(FirstVisitWalkthroughContent.nextArrowNudgeDelayMilliseconds)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.48)) {
                isNextArrowNudging = true
            }
            try? await Task.sleep(for: .milliseconds(210))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                isNextArrowNudging = false
            }
        }
        .task(id: "automatic-advance-\(step.id)") {
            guard step.surface == .profile,
                  step.automaticallyAdvances
            else { return }
            let delay: Int
            if reduceMotion {
                delay = FirstVisitWalkthroughContent.reducedMotionProfileAutoAdvanceDelayMilliseconds
            } else if step.target == .profileShare {
                // The first chapter can render during the app's launch transition.
                // Give it a full beat so the demo never starts halfway through.
                delay = FirstVisitWalkthroughContent.profileIntroAutoAdvanceDelayMilliseconds
            } else {
                delay = FirstVisitWalkthroughContent.profileAutoAdvanceDelayMilliseconds
            }
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            onNext()
        }
    }

    private var coachMark: some View {
        ZStack(alignment: .topLeading) {
            VStack(
                alignment: .leading,
                spacing: isCompactFilterCoach ? WanderTheme.spacing1 : WanderTheme.spacing2
            ) {
                HStack(alignment: isCompactFilterCoach ? .center : .top, spacing: WanderTheme.spacing2) {
                    if step.coachTheme != .standard {
                        WalkthroughCoachThemeBadge(theme: step.coachTheme)
                            .padding(.top, isCompactFilterCoach ? 0 : 1)
                    }

                    Text(step.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                if !step.message.isEmpty {
                    Text(step.message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if onBack != nil || (step.advance == .next && !step.automaticallyAdvances) {
                    WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing2) {
                        HStack(spacing: WanderTheme.spacing2) {
                            Spacer(minLength: 0)

                            if let onBack {
                                Button(action: onBack) {
                                    Image(systemName: "arrow.left")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(WanderTheme.textInk.color)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                        .wanderGlassCapsule(tone: .neutral)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Previous walkthrough step")
                                .accessibilityIdentifier("walkthrough.back.\(step.id)")
                            }

                            if step.advance == .next && !step.automaticallyAdvances {
                                Button(action: onNext) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(WanderTheme.terracottaDark.color)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                        .wanderGlassCapsule(tone: .accent)
                                }
                                .buttonStyle(.plain)
                                .offset(y: isNextArrowNudging ? -5 : 0)
                                .accessibilityLabel(step.nextButtonTitle)
                                .accessibilityIdentifier("walkthrough.next.\(step.id)")
                            }
                        }
                    }
                    .padding(.top, isCompactFilterCoach ? -WanderTheme.spacing1 : 0)
                }
            }
            .padding(.horizontal, isCompactFilterCoach ? WanderTheme.spacing3 : WanderTheme.spacing4)
            .padding(.vertical, isCompactFilterCoach ? 8 : WanderTheme.spacing3)
            .frame(width: cardWidth, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .fill(WanderTheme.surfaceBone.color)
            }
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .stroke(WanderTheme.textInk.color.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WalkthroughCardSizePreferenceKey.self,
                        value: proxy.size
                    )
                }
            }

            WalkthroughPointer()
                .fill(WanderTheme.surfaceBone.color)
                .frame(width: 24, height: 12)
                .rotationEffect(.degrees(layout.cardAboveTarget ? 180 : 0))
                .position(
                    x: layout.pointerX,
                    y: layout.cardAboveTarget ? layout.cardSize.height + 6 : -6
                )
        }
        .frame(
            width: layout.cardSize.width,
            height: layout.cardSize.height,
            alignment: .topLeading
        )
        .position(x: layout.cardFrame.midX, y: layout.cardFrame.midY)
        .opacity(isCoachVisible ? 1 : 0)
        .offset(y: isCoachVisible ? 0 : -10)
        .walkthroughEntranceBounce(isPresented: isCoachVisible, trigger: step.id)
        .allowsHitTesting(isCoachVisible)
        .accessibilityHidden(!isCoachVisible)
        .onPreferenceChange(WalkthroughCardSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            measuredCardSize = size
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title). \(step.message)")
        .accessibilityIdentifier("walkthrough.\(step.id)")
    }

    private func emphasisCornerRadius(for frame: CGRect) -> CGFloat {
        switch step.target {
        case .addSearch, .saveStatus, .saveMoreOptions, .mapFeatured:
            frame.height / 2
        default:
            WanderTheme.radiusLarge
        }
    }
}

private struct WalkthroughFinaleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCelebrating = false

    let step: WalkthroughStep
    let containerSize: CGSize
    let onDismiss: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            ZStack {
                Circle()
                    .fill(WanderTheme.stateSuccess.color.opacity(0.13))
                    .frame(width: 180, height: 180)
                    .scaleEffect(reduceMotion ? 1 : (isCelebrating ? 1.08 : 0.9))

                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .offset(y: reduceMotion ? 0 : (isCelebrating ? -7 : 4))

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.categorySun.color)
                    .offset(x: -76, y: -54)
                    .scaleEffect(reduceMotion ? 1 : (isCelebrating ? 1.14 : 0.82))

                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.pinSocial.color)
                    .offset(x: 72, y: -36)
                    .scaleEffect(reduceMotion ? 1 : (isCelebrating ? 0.84 : 1.12))
            }
            .offset(y: -190)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(step.title)
                        .font(WanderTypography.editorialMasthead)
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("A thought for the road")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Text("“\(step.message)”")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .italic()
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)

                Text("— Anthony Bourdain")
                    .font(WanderTypography.label)
                    .foregroundStyle(WanderTheme.terracottaDark.color)

                Text("Keep the places that move you. Your map will remember the rest")
                    .font(WanderTypography.body)
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer(minLength: 0)
                    Button(action: onFinish) {
                        HStack(spacing: WanderTheme.spacing1) {
                            Text(step.nextButtonTitle)
                            Image(systemName: "arrow.right")
                        }
                        .font(WanderTypography.control)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minHeight: 48)
                        .wanderGlassCapsule(tone: .accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.nextButtonTitle)
                    .accessibilityIdentifier("walkthrough.next.\(step.id)")
                }
            }
            .padding(WanderTheme.spacing4)
            .frame(maxWidth: min(356, containerSize.width - 32), alignment: .leading)
            .background(
                WanderTheme.surfaceBone.color,
                in: RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusSheet, style: .continuous)
                    .stroke(WanderTheme.stateSuccess.color.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: 22, y: 10)
            .offset(y: 92)
            .walkthroughEntranceBounce()
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.\(step.id)")
        .onAppear {
            guard !reduceMotion else { return }
            isCelebrating = true
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
            value: isCelebrating
        )
    }
}

private extension WalkthroughCoachTheme {
    var systemImage: String {
        switch self {
        case .standard: "info.circle.fill"
        case .map: "map.fill"
        case .save: "square.and.arrow.down.fill"
        case .rating: "star.fill"
        case .tags: "tag.fill"
        case .social: "person.2.fill"
        case .memory: "ticket.fill"
        case .lists: "bookmark.fill"
        case .profile: "person.crop.circle.fill"
        case .celebration: "sparkles"
        }
    }

    var accentColor: Color {
        switch self {
        case .social:
            WanderTheme.pinSocial.color
        case .lists:
            WanderTheme.categorySun.color
        case .celebration:
            WanderTheme.stateSuccess.color
        case .map, .save, .rating, .tags, .memory, .profile:
            WanderTheme.terracotta.color
        case .standard:
            WanderTheme.surfaceBone.color
        }
    }

    var animates: Bool {
        switch self {
        case .social, .celebration:
            true
        default:
            false
        }
    }
}

private struct WalkthroughCoachThemeBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    let theme: WalkthroughCoachTheme

    var body: some View {
        Image(systemName: theme.systemImage)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(theme.accentColor)
            .frame(width: 30, height: 30)
            .background(theme.accentColor.opacity(0.14), in: Circle())
            .scaleEffect(
                reduceMotion || !theme.animates
                    ? 1
                    : (isBreathing ? 1.06 : 0.96)
            )
            .onAppear {
                guard theme.animates, !reduceMotion else { return }
                isBreathing = true
            }
            .animation(
                reduceMotion || !theme.animates
                    ? nil
                    : .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .accessibilityHidden(true)
    }
}

private struct WalkthroughCardSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct WalkthroughEmphasisRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let frame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(WanderTheme.categorySun.color, lineWidth: 3)
            .frame(width: frame.width + 8, height: frame.height + 8)
            .position(x: frame.midX, y: frame.midY)
            .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.018 : 0.992))
            .shadow(
                color: WanderTheme.categorySun.color.opacity(isPulsing ? 0.72 : 0.32),
                radius: isPulsing ? 11 : 5
            )
            .onAppear {
                guard !reduceMotion else { return }
                isPulsing = true
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .accessibilityHidden(true)
    }
}

struct WalkthroughScrim: View {
    let spotlightFrame: CGRect
    let containerSize: CGSize
    var cornerRadius = WanderTheme.radiusLarge

    var body: some View {
        ZStack {
            WalkthroughScrimShape(
                spotlightFrame: spotlightFrame,
                cornerRadius: cornerRadius
            )
                .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                .opacity(0.54)

            WalkthroughScrimShape(
                spotlightFrame: spotlightFrame,
                cornerRadius: cornerRadius
            )
                .fill(Color.black.opacity(0.15), style: FillStyle(eoFill: true))
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }
}

private struct WalkthroughFullScreenScrim: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(0.62)
            .overlay(Color.black.opacity(0.18))
            .accessibilityHidden(true)
    }
}

struct WalkthroughScrimShape: Shape {
    var spotlightFrame: CGRect
    var cornerRadius = WanderTheme.radiusLarge

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(spotlightFrame.origin.x, spotlightFrame.origin.y),
                AnimatablePair(spotlightFrame.size.width, spotlightFrame.size.height)
            )
        }
        set {
            spotlightFrame = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: spotlightFrame.intersection(rect),
            cornerSize: CGSize(
                width: cornerRadius,
                height: cornerRadius
            )
        )
        return path
    }
}

private struct WalkthroughTouchShield: View {
    let containerSize: CGSize
    let spotlightFrame: CGRect
    let allowsSpotlightInteraction: Bool

    var body: some View {
        if allowsSpotlightInteraction {
            ZStack(alignment: .topLeading) {
                blocker(
                    CGRect(
                        x: 0,
                        y: 0,
                        width: containerSize.width,
                        height: max(spotlightFrame.minY, 0)
                    )
                )
                blocker(
                    CGRect(
                        x: 0,
                        y: spotlightFrame.maxY,
                        width: containerSize.width,
                        height: max(containerSize.height - spotlightFrame.maxY, 0)
                    )
                )
                blocker(
                    CGRect(
                        x: 0,
                        y: spotlightFrame.minY,
                        width: max(spotlightFrame.minX, 0),
                        height: max(spotlightFrame.height, 0)
                    )
                )
                blocker(
                    CGRect(
                        x: spotlightFrame.maxX,
                        y: spotlightFrame.minY,
                        width: max(containerSize.width - spotlightFrame.maxX, 0),
                        height: max(spotlightFrame.height, 0)
                    )
                )
            }
            .frame(width: containerSize.width, height: containerSize.height)
        } else {
            blocker(CGRect(origin: .zero, size: containerSize))
        }
    }

    private func blocker(_ frame: CGRect) -> some View {
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .frame(width: max(frame.width, 0), height: max(frame.height, 0))
            .position(x: frame.midX, y: frame.midY)
            .onTapGesture {}
            .accessibilityHidden(true)
    }
}

private struct WalkthroughPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
