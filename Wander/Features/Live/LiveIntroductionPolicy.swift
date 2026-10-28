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
        case .mapAndFeed: "Your Feed Has A Map"
        case .drawArea: "Choose Your Filters And Area"
        case .activity: "The Same Feed, Within Reach"
        case .searchAndPeople: "Find A Place Or A Person"
        case .addPlace: "Keep A Place For Later"
        case .yourMap: "Your Map Stays In Profile"
        }
    }

    var message: String {
        switch self {
        case .mapAndFeed: "Drag The Activity Drawer Up To Read Your Feed, Or Down To Explore Its Map. Pins Show Shared Activity, Not Someone’s Live Location."
        case .drawArea: "Filters Lets You Choose Your Existing Feed Audience, Check-Ins Or Wannas, And A Time Range. Apply Commits Your Choices; Cancel Keeps The Previous Ones. Draw Area Adds A Boundary, Or Use The Visible Area. Your Map’s Other Tools Stay In Profile."
        case .activity: "Your Activity Cards And Their Like, Comment, Save And Share Actions Are Still Here. Check-Ins And Outlined Wanna Bookmarks Describe Different Actions. Counts Show What’s Loaded."
        case .searchAndPeople: "Search From Live To Find Places And People. Your Existing Feed Audience Choices Still Control Whose Activity You See. Invite People From The Person-Plus Icon Beside The Activity Count. People Worth Following Remain In The Feed."
        case .addPlace: "Use + In Live To Add A Check-In Or Wanna, Search For A Place, Or Open Your Existing Import Flow. You Choose What To Share."
        case .yourMap: "Open Profile, Then Your Map, For Your Full Place History, Patterns, Filters, Snapshot And Sharing. Your Calendar, Streak And Recent Activity Stay In Profile Too."
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
