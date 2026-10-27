import Foundation

/// Separate presentation history: showing Live never completes or resets NUX.
struct LiveIntroductionStore {
    static let currentVersion = 1
    let defaults: UserDefaults
    let version: Int

    init(defaults: UserDefaults = .standard, version: Int = Self.currentVersion) {
        self.defaults = defaults
        self.version = version
    }

    func hasPresented(for userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        return defaults.bool(forKey: key(userID, suffix: "presented"))
            || defaults.bool(forKey: key(userID, suffix: "acknowledged"))
            // Preserve dismissals from the initial integrated review card.
            || (version == 1 && defaults.bool(forKey: "astir.live.introduction.v1.\(userID)"))
    }

    /// Call only after the eligible card has actually appeared, not at launch.
    func markPresented(for userID: String) {
        guard !userID.isEmpty else { return }
        defaults.set(true, forKey: key(userID, suffix: "presented"))
    }

    func acknowledge(for userID: String) {
        guard !userID.isEmpty else { return }
        markPresented(for: userID)
        defaults.set(true, forKey: key(userID, suffix: "acknowledged"))
    }

    private func key(_ userID: String, suffix: String) -> String {
        "astir.live.introduction.v\(version).\(userID).\(suffix)"
    }
}

enum LiveIntroductionAudience: Equatable, Sendable {
    case returning, firstVisit
}

struct LiveIntroductionContext: Equatable, Sendable {
    let userID: String?
    let isLiveActive: Bool
    let isSessionValidated: Bool
    let hasFinishedAccountSetup: Bool
    /// Includes explicit destination/auth/permission/founders welcome and any
    /// presented editor, invitation or modal. A hidden card must not be consumed.
    let hasPriorityPresentation: Bool
    let hasPendingLegacyCheckpoint: Bool
    let isFirstVisitEligible: Bool
}

enum LiveIntroductionPolicy {
    static func audience(for context: LiveIntroductionContext, hasPresented: Bool) -> LiveIntroductionAudience? {
        guard let userID = context.userID, !userID.isEmpty,
              context.isLiveActive, context.isSessionValidated, context.hasFinishedAccountSetup,
              !context.hasPriorityPresentation, !context.hasPendingLegacyCheckpoint,
              !hasPresented else { return nil }
        return context.isFirstVisitEligible ? .firstVisit : .returning
    }
}

enum LiveIntroductionStep: String, CaseIterable, Identifiable, Sendable {
    case mapAndFeed, drawArea, activity, searchAndPeople, addPlace, yourMap
    var id: Self { self }

    var title: String {
        switch self {
        case .mapAndFeed: "Your Feed has a map"
        case .drawArea: "Choose your filters and area"
        case .activity: "The same Feed, within reach"
        case .searchAndPeople: "Find a place or a person"
        case .addPlace: "Keep a place for later"
        case .yourMap: "Your Map stays in Profile"
        }
    }

    var message: String {
        switch self {
        case .mapAndFeed: "Drag the activity drawer up to read your Feed, or down to explore its map. Pins show shared activity, not someone’s live location."
        case .drawArea: "Filters lets you choose your existing Feed audience, Check-ins or Wannas, and a time range. Apply commits your choices; Cancel keeps the previous ones. Draw area adds a boundary, or use the visible area. Your Map’s other tools stay in Profile."
        case .activity: "Your activity cards and their Like, Comment, Save and Share actions are still here. Check-ins and outlined Wanna bookmarks describe different actions. Counts show what’s loaded."
        case .searchAndPeople: "Search from Live to find places and people. Your existing Feed audience choices still control whose activity you see. Invite people from the person-plus icon beside the activity count. People worth following remain in the Feed."
        case .addPlace: "Use + in Live to add a Check-in or Wanna, search for a place, or open your existing import flow. You choose what to share."
        case .yourMap: "Open Profile, then Your Map, for your full place history, Patterns, filters, Snapshot and sharing. Your calendar, streak and recent activity stay in Profile too."
        }
    }

    var symbol: String {
        switch self {
        case .mapAndFeed: "map"
        case .drawArea: "pencil.and.outline"
        case .activity: "rectangle.stack"
        case .searchAndPeople: "magnifyingglass"
        case .addPlace: "plus"
        case .yourMap: "person.crop.circle"
        }
    }
}

/// A non-destructive semantic mapping. The original checkpoint, including any
/// save/import draft and invite state, is retained unchanged for the host.
struct LiveIntroductionResumePlan: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        case deferred
        case alreadyCompleted
        case guide(LiveIntroductionStep)
        case retained(WalkthroughSurface, WalkthroughTargetID)
        case retainedLesson(FirstVisitWalkthroughCheckpointPresentation)
    }
    let checkpoint: FirstVisitWalkthroughCheckpoint
    let destination: Destination
}

enum LiveIntroductionCheckpointAdapter {
    static func plan(
        for checkpoint: FirstVisitWalkthroughCheckpoint,
        completedSurfaces: Set<WalkthroughSurface>,
        hasPriorityPresentation: Bool
    ) -> LiveIntroductionResumePlan {
        let destination: LiveIntroductionResumePlan.Destination
        if hasPriorityPresentation {
            destination = .deferred
        } else if let presentation = checkpoint.presentation {
            destination = .retainedLesson(presentation)
        } else {
            let surface = legacySurface(for: checkpoint.target)
            if completedSurfaces.contains(surface) {
                destination = .alreadyCompleted
            } else {
                destination = mappedDestination(for: checkpoint.target, surface: surface)
            }
        }
        return LiveIntroductionResumePlan(checkpoint: checkpoint, destination: destination)
    }

    static func legacySurface(for target: WalkthroughTargetID) -> WalkthroughSurface {
        switch target {
        case .mapAdd, .mapAddAgain, .mapFeatured, .mapFriends, .mapYou, .mapMoreFilters,
             .mapSearch, .mapMemory, .mapTabs, .mapSendoff, .mapPinLegend: .map
        case .addSearch, .addPlace, .addImport, .addNearby, .addNearbySection, .addClose: .add
        case .saveStatus, .saveContinue, .saveDate, .saveDetails, .saveRating, .saveFriends,
             .savePhotos, .saveMoreOptions, .saveNote, .saveQuestions, .saveTags, .savePrivacy,
             .saveSubmit, .saveReview: .saveFlow
        case .feedActivity, .feedCircle, .feedRecent, .feedSurfaceSwitch,
             .feedPeopleSearch, .feedInvite, .feedDiscoverSearch: .feed
        case .feedSearchField, .feedSmartSearch, .feedSearchResultsBack: .feedSearch
        case .placeRatings, .placeActions, .placeSaveActions, .placeCheckIn, .placeWanna, .placeHistory: .placeDetail
        case .listsCreate, .listsScope, .listsOpenPlan: .lists
        case .listMap, .listMapPlace: .listDetail
        case .listEditorTitle, .listEditorPrivacy, .listEditorCollaborators: .listEditor
        case .profileSettings, .profileSocial, .profileActivity, .profileShare, .profileCalendar, .profileMap: .profile
        }
    }

    private static func mappedDestination(for target: WalkthroughTargetID, surface: WalkthroughSurface) -> LiveIntroductionResumePlan.Destination {
        switch target {
        case .mapFeatured, .mapTabs, .feedSurfaceSwitch: .guide(.mapAndFeed)
        case .mapFriends, .feedCircle, .feedPeopleSearch, .feedInvite: .guide(.searchAndPeople)
        case .mapMoreFilters: .guide(.drawArea)
        case .mapSearch, .feedDiscoverSearch: .guide(.searchAndPeople)
        case .mapAdd: .guide(.addPlace)
        case .mapYou: .guide(.yourMap)
        case .mapSendoff, .mapPinLegend, .feedActivity, .feedRecent: .guide(.activity)
        // These may contain a tutorial memory, import or unfinished user action.
        // Reading a guide is not completion of the retained flow.
        default: .retained(surface, target)
        }
    }
}
