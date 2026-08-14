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
    case feedActivity
    case feedSurfaceSwitch
    case feedPeopleSearch
    case feedInvite
    case feedDiscoverSearch
    case feedSearchField
    case feedSmartSearch
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

    var id: String { "\(surface.rawValue).\(target.rawValue)" }
    var automaticallyRecoversWhenTargetIsMissing: Bool { advance == .action }
}

enum FirstVisitWalkthroughContent {
    static let version = 9
    static let suppressedSurfaces: Set<WalkthroughSurface> = [.listDetail, .listEditor]

    static let stepsBySurface: [WalkthroughSurface: [WalkthroughStep]] = [
        .map: [
            step(.map, .mapAdd, "Save your first place", "Tap + to add somewhere you've been or want to try."),
            step(.map, .mapAddAgain, "One more shortcut", "Tap + again and we’ll show you where imports live."),
            step(
                .map,
                .mapFeatured,
                "Featured shows you recommendations based on your taste",
                "",
                advance: .next,
                coachTheme: .map
            ),
            step(
                .map,
                .mapFriends,
                "All places from everyone you follow",
                "",
                advance: .next,
                coachTheme: .social
            ),
            step(
                .map,
                .mapMoreFilters,
                "Narrow in with More",
                "Category chooses the kind of place. People picks whose saves you see. Status switches between All, Check Ins, and Wanna.",
                advance: .next,
                coachTheme: .map
            ),
            step(
                .map,
                .mapSearch,
                "Search your trusted map",
                "Try a place, neighborhood, or person.",
                advance: .next,
                coachTheme: .map
            ),
            step(
                .map,
                .mapMemory,
                "Open a place memory",
                "A place card keeps the useful context together. Next, we’ll open it and show you what each part means.",
                advance: .next,
                nextButtonTitle: "Open place",
                coachTheme: .memory
            ),
            step(
                .map,
                .mapTabs,
                "Your places, all connected",
                "Map, Feed, Lists, and Profile work together to help you find, plan, and remember.",
                advance: .next,
                coachTheme: .map
            )
        ],
        .sendoff: [
            step(
                .sendoff,
                .mapSendoff,
                "Your map is yours now",
                "Save the places worth remembering. When you need the right spot, your people and your memories will be here.",
                advance: .next,
                nextButtonTitle: "Start exploring",
                coachTheme: .celebration
            )
        ],
        .add: [
            step(.add, .addSearch, "Find your first place", "Type a place name and submit the search.", coachTheme: .map),
            step(.add, .addPlace, "Choose the right place", "Review the options, choose the right result, then tap Save to start your memory.", coachTheme: .save),
            step(
                .add,
                .addImport,
                "Bring saves with you",
                "Import From is where links, shared posts, and notes become places to review.",
                advance: .next,
                coachTheme: .save
            ),
            step(.add, .addClose, "Back to your map", "Tap × to close Add a Place and keep exploring.")
        ],
        .saveFlow: [
            step(
                .saveFlow,
                .saveStatus,
                "Choose how to save it",
                "Pick Check In or Wanna Go. Either way, we’ll guide you through the useful details before you save."
            ),
            step(.saveFlow, .saveContinue, "Add what matters", "Continue to the details that will help future you choose."),
            step(
                .saveFlow,
                .saveDate,
                "When were you here?",
                "Today is selected automatically. Change the date for an older memory, or leave it as is.",
                advance: .next,
                allowsTargetInteraction: true
            ),
            step(
                .saveFlow,
                .saveDetails,
                "Confirm the place type",
                "Category and subcategory make this memory easier to find later. The suggested choices are fine to keep.",
                advance: .next,
                allowsTargetInteraction: true
            ),
            step(
                .saveFlow,
                .saveRating,
                "Rate it for future you",
                "A quick rating helps you compare places later. Keep the suggested score or adjust it.",
                advance: .next,
                allowsTargetInteraction: true,
                coachTheme: .rating
            ),
            step(
                .saveFlow,
                .saveFriends,
                "Friends and photos are optional",
                "Add who was there and a photo worth remembering—or leave both blank.",
                advance: .next,
                allowsTargetInteraction: true
            ),
            step(
                .saveFlow,
                .saveMoreOptions,
                "More options, whenever you need them",
                "Notes, fit questions, tags, and privacy live here. You can adjust them on any save.",
                advance: .next,
                coachTheme: .save
            ),
            step(.saveFlow, .saveSubmit, "Put it on your map", "Save the place to finish your first memory.")
        ],
        .feed: [
            step(
                .feed,
                .feedActivity,
                "See your friends’ check-ins here",
                "Like, comment, share, and add people to make your trusted feed more useful.",
                advance: .next
            ),
            step(
                .feed,
                .feedDiscoverSearch,
                "Ask your circle for a place",
                "Tap search to open Discover and find places through the context your people saved.",
                allowsBackNavigation: false,
                coachTheme: .map
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
                "Tap an example to turn a natural-language need into filters and trusted results.",
                coachTheme: .map
            )
        ],
        .lists: [
            step(
                .lists,
                .listsScope,
                "Keep plans together",
                "Save places into lists for trips, date nights, neighborhoods, and plans with friends.",
                advance: .next,
                coachTheme: .lists
            )
        ],
        .listDetail: [],
        .listEditor: [],
        .profile: [
            step(
                .profile,
                .profileSettings,
                "Make rec.me yours",
                "Open settings for account, privacy, notifications, and app preferences.",
                advance: .next
            ),
            step(
                .profile,
                .profileSocial,
                "Your trusted circle",
                "See who you follow and who follows your recommendations.",
                advance: .next,
                coachTheme: .social
            ),
            step(
                .profile,
                .profileActivity,
                "Your place history",
                "Filter recent activity to revisit saves, check-ins, and wanna places.",
                advance: .next,
                coachTheme: .memory
            ),
            step(
                .profile,
                .profileShare,
                "Share your rec.me",
                "Send your profile to friends whose taste you trust.",
                advance: .next
            )
        ],
        .placeDetail: [
            step(
                .placeDetail,
                .placeRatings,
                "Three ratings, three jobs",
                "Your rating is yours. Friends rating averages people you follow. Fit score predicts how well this place matches your taste.",
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
                "Check-in history keeps each date, rating, note, tag, photo, and companion together.",
                advance: .next,
                nextButtonTitle: "Keep going",
                coachTheme: .memory
            )
        ]
    ]

    static var allSteps: [WalkthroughStep] {
        WalkthroughSurface.allCases.flatMap { stepsBySurface[$0, default: []] }
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
        coachTheme: WalkthroughCoachTheme = .standard
    ) -> WalkthroughStep {
        WalkthroughStep(
            surface: surface,
            target: target,
            title: title,
            message: message,
            advance: advance,
            allowsTargetInteraction: allowsTargetInteraction ?? (advance == .action),
            allowsBackNavigation: allowsBackNavigation,
            nextButtonTitle: nextButtonTitle,
            coachTheme: coachTheme
        )
    }
}

struct FirstVisitWalkthroughStore {
    let defaults: UserDefaults
    let version: Int

    init(defaults: UserDefaults = .standard, version: Int = FirstVisitWalkthroughContent.version) {
        self.defaults = defaults
        self.version = version
    }

    func progress(for userID: String, surface: WalkthroughSurface) -> Int {
        defaults.integer(forKey: progressKey(userID: userID, surface: surface))
    }

    func setProgress(_ progress: Int, for userID: String, surface: WalkthroughSurface) {
        defaults.set(progress, forKey: progressKey(userID: userID, surface: surface))
    }

    func isComplete(for userID: String, surface: WalkthroughSurface) -> Bool {
        defaults.bool(forKey: completionKey(userID: userID, surface: surface))
    }

    func markComplete(for userID: String, surface: WalkthroughSurface) {
        defaults.set(true, forKey: completionKey(userID: userID, surface: surface))
    }

    func reset(for userID: String) {
        for surface in WalkthroughSurface.allCases {
            defaults.removeObject(forKey: progressKey(userID: userID, surface: surface))
            defaults.removeObject(forKey: completionKey(userID: userID, surface: surface))
        }
        defaults.removeObject(forKey: launchCountKey(userID: userID))
        defaults.removeObject(forKey: importLessonCompletionKey(userID: userID))
        defaults.removeObject(forKey: deviceFeaturesCompletionKey(userID: userID))
    }

    func registerLaunch(for userID: String) -> Int {
        let nextCount = defaults.integer(forKey: launchCountKey(userID: userID)) + 1
        defaults.set(nextCount, forKey: launchCountKey(userID: userID))
        return nextCount
    }

    func hasCompletedDeviceFeaturesLesson(for userID: String) -> Bool {
        defaults.bool(forKey: deviceFeaturesCompletionKey(userID: userID))
    }

    func hasCompletedImportLesson(for userID: String) -> Bool {
        defaults.bool(forKey: importLessonCompletionKey(userID: userID))
    }

    func markImportLessonComplete(for userID: String) {
        defaults.set(true, forKey: importLessonCompletionKey(userID: userID))
    }

    func markDeviceFeaturesLessonComplete(for userID: String) {
        defaults.set(true, forKey: deviceFeaturesCompletionKey(userID: userID))
    }

    func hasCompletedEntireWalkthrough(for userID: String) -> Bool {
        WalkthroughSurface.allCases
            .filter { !FirstVisitWalkthroughContent.suppressedSurfaces.contains($0) }
            .allSatisfy { isComplete(for: userID, surface: $0) }
            && hasCompletedImportLesson(for: userID)
            && hasCompletedDeviceFeaturesLesson(for: userID)
    }

    private func progressKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.v\(version).\(userID).\(surface.rawValue).progress"
    }

    private func completionKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.v\(version).\(userID).\(surface.rawValue).complete"
    }

    private func launchCountKey(userID: String) -> String {
        "wander.walkthrough.v\(version).\(userID).authenticatedLaunchCount"
    }

    private func deviceFeaturesCompletionKey(userID: String) -> String {
        "wander.walkthrough.v\(version).\(userID).deviceFeatures.complete"
    }

    private func importLessonCompletionKey(userID: String) -> String {
        "wander.walkthrough.v\(version).\(userID).importLesson.complete"
    }
}

@MainActor
final class FirstVisitWalkthroughCoordinator: ObservableObject {
    @Published private(set) var activeSurface: WalkthroughSurface?
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var requestedSurface: WalkthroughSurface?
    @Published private(set) var isPresentingImportLesson = false
    @Published private(set) var isPresentingDeviceFeaturesLesson = false
    @Published private(set) var tutorialUserPlaceID: String?
    @Published private(set) var isRequestingContactInvite = false

    private(set) var userID: String
    private let store: FirstVisitWalkthroughStore
    private var registeredLaunchUserID: String?
    private var isImportLessonEligible = false
    private var isDeviceFeaturesLessonEligible = false
    private var didNotifyCompletion = false
    private let onCompleted: () -> Void
    let isEnabled: Bool

    init(
        userID: String = "local-user",
        store: FirstVisitWalkthroughStore = FirstVisitWalkthroughStore(),
        isEnabled: Bool = true,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.userID = userID
        self.store = store
        self.isEnabled = isEnabled
        self.onCompleted = onCompleted
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
        registeredLaunchUserID = nil
        requestedSurface = nil
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialUserPlaceID = nil
        isRequestingContactInvite = false
        didNotifyCompletion = false
    }

    func registerLaunch(
        forceImportLesson: Bool = false,
        forceDeviceFeaturesLesson: Bool = false
    ) {
        guard isEnabled else { return }

        if registeredLaunchUserID != userID {
            registeredLaunchUserID = userID
            let launchCount = store.registerLaunch(for: userID)
            let hasCompletedImportLesson = store.hasCompletedImportLesson(for: userID)
            isImportLessonEligible = launchCount >= 2
                && !hasCompletedImportLesson
            isDeviceFeaturesLessonEligible = launchCount >= 3
                && hasCompletedImportLesson
                && !store.hasCompletedDeviceFeaturesLesson(for: userID)
        }

        if forceImportLesson {
            isImportLessonEligible = true
            activeSurface = nil
            currentStepIndex = 0
            isPresentingImportLesson = true
        }

        if forceDeviceFeaturesLesson {
            isDeviceFeaturesLessonEligible = true
            activeSurface = nil
            currentStepIndex = 0
            isPresentingImportLesson = false
            isPresentingDeviceFeaturesLesson = true
        }
        notifyCompletionIfNeeded()
    }

    func activate(_ surface: WalkthroughSurface) {
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
    }

    func forceActivate(_ target: WalkthroughTargetID) {
        guard
            isEnabled,
            let surface = WalkthroughSurface.allCases.first(where: { surface in
                FirstVisitWalkthroughContent.stepsBySurface[surface]?.contains(where: {
                    $0.target == target
                }) == true
            }),
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
    }

    func perform(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target, currentStep?.advance == .action else { return }
        advance()
    }

    func advancePassiveStep() {
        guard currentStep?.advance == .next else { return }
        if currentStep?.target == .feedInvite {
            isRequestingContactInvite = true
            return
        }
        advance()
    }

    func goBack() {
        guard canGoBack, let surface = activeSurface else { return }
        let previousIndex = currentStepIndex - 1
        isRequestingContactInvite = false
        store.setProgress(previousIndex, for: userID, surface: surface)
        currentStepIndex = previousIndex
    }

    func completeContactInviteRequest() {
        guard isRequestingContactInvite, currentStep?.target == .feedInvite else { return }
        isRequestingContactInvite = false
        advance()
    }

    func recoverUnavailableTarget(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target else { return }
        advance()
    }

    func recordTutorialSave(userPlaceID: String) {
        guard activeSurface == .saveFlow else { return }
        tutorialUserPlaceID = userPlaceID
    }

    func resetCurrentUser() {
        store.reset(for: userID)
        activeSurface = nil
        currentStepIndex = 0
        registeredLaunchUserID = nil
        requestedSurface = nil
        isImportLessonEligible = false
        isDeviceFeaturesLessonEligible = false
        isPresentingImportLesson = false
        isPresentingDeviceFeaturesLesson = false
        tutorialUserPlaceID = nil
        isRequestingContactInvite = false
        didNotifyCompletion = false
    }

    func presentLaunchLessonIfEligible() {
        guard
            isEnabled,
            activeSurface == nil,
            !isPresentingImportLesson,
            !isPresentingDeviceFeaturesLesson
        else { return }

        if isImportLessonEligible {
            isPresentingImportLesson = true
        } else if isDeviceFeaturesLessonEligible {
            isPresentingDeviceFeaturesLesson = true
        }
    }

    func completeImportLesson() {
        guard isPresentingImportLesson else { return }
        store.markImportLessonComplete(for: userID)
        isImportLessonEligible = false
        isPresentingImportLesson = false
        notifyCompletionIfNeeded()
    }

    func completeDeviceFeaturesLesson() {
        guard isPresentingDeviceFeaturesLesson else { return }
        store.markDeviceFeaturesLessonComplete(for: userID)
        isDeviceFeaturesLessonEligible = false
        isPresentingDeviceFeaturesLesson = false
        notifyCompletionIfNeeded()
    }

    func consumeRequestedSurface(_ surface: WalkthroughSurface) {
        guard requestedSurface == surface else { return }
        requestedSurface = nil
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
            requestedSurface = destination(after: surface)
            notifyCompletionIfNeeded()
        } else {
            currentStepIndex = nextIndex
        }
    }

    private func destination(after surface: WalkthroughSurface) -> WalkthroughSurface? {
        switch surface {
        case .map:
            .feed
        case .placeDetail:
            .map
        case .sendoff:
            nil
        case .add, .saveFlow:
            .map
        case .feed:
            .feedSearch
        case .listEditor:
            .lists
        case .listDetail:
            .profile
        case .feedSearch:
            .lists
        case .lists:
            .profile
        case .profile:
            .sendoff
        }
    }

    private func notifyCompletionIfNeeded() {
        guard !didNotifyCompletion,
              store.hasCompletedEntireWalkthrough(for: userID)
        else { return }
        didNotifyCompletion = true
        onCompleted()
    }
}

private struct WalkthroughTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [WalkthroughTargetID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [WalkthroughTargetID: Anchor<CGRect>],
        nextValue: () -> [WalkthroughTargetID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func walkthroughTarget(_ target: WalkthroughTargetID?) -> some View {
        anchorPreference(key: WalkthroughTargetPreferenceKey.self, value: .bounds) { anchor in
            guard let target else { return [:] }
            return [target: anchor]
        }
    }

    func firstVisitWalkthroughOverlay(
        _ coordinator: FirstVisitWalkthroughCoordinator,
        surface: WalkthroughSurface
    ) -> some View {
        modifier(FirstVisitWalkthroughModifier(coordinator: coordinator, surface: surface))
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
                ImportWalkthroughOverlay {
                    coordinator.completeImportLesson()
                    onOpenImport()
                }
                .transition(.opacity)
                .zIndex(2_000)
            } else if coordinator.isPresentingDeviceFeaturesLesson {
                DeviceFeaturesWalkthroughOverlay {
                    coordinator.completeDeviceFeaturesLesson()
                }
                .transition(.opacity)
                .zIndex(2_000)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.isPresentingImportLesson)
        .animation(.easeInOut(duration: 0.2), value: coordinator.isPresentingDeviceFeaturesLesson)
    }
}

enum WalkthroughHelpDestination {
    static let extensions = URL(string: "https://getrec.me/extensions")!
}

enum ImportWalkthroughContent {
    static let title = "Bring every saved place with you"
    static let message = "Paste one place, a few links, or a whole list from Maps, Instagram, TikTok, or Notes. Choose what to keep and mark each Check In or Wanna before anything reaches your map."
    static let actionTitle = "Open import form"
    static let helpURL = ImportHelpDestination.url
}

private struct ImportWalkthroughOverlay: View {
    @Environment(\.openURL) private var openURL

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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.importLesson")
    }
}

private struct DeviceFeaturesWalkthroughOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            WalkthroughFullScreenScrim()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    ZStack {
                        Circle()
                            .fill(WanderTheme.terracotta.color)
                            .frame(width: 52, height: 52)
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WanderTheme.textOnAction.color)
                    }

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("Keep rec.me one press away")
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text("Set these up once, then save or find a place without hunting for the app.")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DeviceFeatureInstruction(
                        systemImage: "button.programmable",
                        title: "Action Button & Control Center",
                        instruction: "Open Settings → Action Button → Controls, then choose rec.me Check In. You can add the same control from Control Center."
                    )

                    DeviceFeatureInstruction(
                        systemImage: "square.grid.2x2.fill",
                        title: "Home & Lock Screen widgets",
                        instruction: "Long-press your screen, tap Edit or +, search rec.me, then choose Quick Add, Search, Activity, or Nearby."
                    )

                    DeviceFeatureInstruction(
                        systemImage: "square.and.arrow.up.fill",
                        title: "Share into rec.me",
                        instruction: "From Maps, Instagram, TikTok, or Safari, tap Share → rec.me. Your captures open in a private review where you choose what to keep."
                    )

                    Link(destination: WalkthroughHelpDestination.extensions) {
                        Label("See the extensions guide", systemImage: "safari")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens getrec.me/extensions")
                    .accessibilityIdentifier("walkthrough.deviceFeatures.extensionsGuide")

                    Button("Got it", action: onComplete)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(WanderTheme.terracotta.color)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("walkthrough.deviceFeatures.complete")
                }
                .padding(WanderTheme.spacing4)
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
                .padding(.vertical, WanderTheme.spacing8)
                .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.015 : 0.985))
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.deviceFeatures")
        .onAppear {
            guard !reduceMotion else { return }
            isBreathing = true
        }
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
            value: isBreathing
        )
    }
}

private struct DeviceFeatureInstruction: View {
    let systemImage: String
    let title: String
    let instruction: String

    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .frame(width: 32, height: 32)
                .background(WanderTheme.terracotta.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text(instruction)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
    }
}

private struct FirstVisitWalkthroughModifier: ViewModifier {
    @ObservedObject var coordinator: FirstVisitWalkthroughCoordinator
    let surface: WalkthroughSurface

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.activate(surface) }
            .onChange(of: surface) { _, newSurface in coordinator.activate(newSurface) }
            .walkthroughPresenterScrim(
                isPresented: coordinator.isRequestingContactInvite
                    && coordinator.activeSurface == surface
            )
            .overlayPreferenceValue(WalkthroughTargetPreferenceKey.self) { targets in
                GeometryReader { proxy in
                    if
                        coordinator.activeSurface == surface,
                        let step = coordinator.currentStep,
                        let anchor = targets[step.target]
                    {
                        let targetFrame = proxy[anchor]
                        if targetFrame.intersects(CGRect(origin: .zero, size: proxy.size)),
                           targetFrame.width > 0,
                           targetFrame.height > 0 {
                            FirstVisitWalkthroughOverlay(
                                step: step,
                                targetFrame: targetFrame,
                                containerSize: proxy.size,
                                onBack: step.allowsBackNavigation && coordinator.canGoBack
                                    ? { coordinator.goBack() }
                                    : nil,
                                onNext: coordinator.advancePassiveStep
                            )
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

    let step: WalkthroughStep
    let targetFrame: CGRect
    let containerSize: CGSize
    let onBack: (() -> Void)?
    let onNext: () -> Void

    private var cardWidth: CGFloat {
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
            targetFrame: targetFrame,
            containerSize: containerSize,
            cardSize: CGSize(width: cardWidth, height: max(measuredCardSize.height, 1)),
            spotlightInset: spotlightInset
        )
    }

    private var spotlightInset: CGFloat {
        switch step.target {
        case .addSearch:
            18
        case .addPlace, .addImport:
            12
        default:
            8
        }
    }

    var body: some View {
        ZStack {
            WalkthroughScrim(
                spotlightFrame: layout.spotlightFrame,
                containerSize: containerSize,
                cornerRadius: step.target == .mapTabs ? 34 : WanderTheme.radiusLarge
            )
                .allowsHitTesting(false)

            WalkthroughTouchShield(
                containerSize: containerSize,
                spotlightFrame: layout.spotlightFrame,
                allowsSpotlightInteraction: step.allowsTargetInteraction
            )

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                        if step.coachTheme != .standard {
                            WalkthroughCoachThemeBadge(theme: step.coachTheme)
                        }

                        Text(step.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !step.message.isEmpty {
                        Text(step.message)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if onBack != nil || step.advance == .next {
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

                            if step.advance == .next {
                                Button(action: onNext) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(WanderTheme.terracottaDark.color)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                        .wanderGlassCapsule(tone: .accent)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(step.nextButtonTitle)
                                .accessibilityIdentifier("walkthrough.next.\(step.id)")
                            }
                        }
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .frame(width: cardWidth, alignment: .leading)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                            .fill(WanderTheme.surfaceBone.color)

                        if step.coachTheme != .standard {
                            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            step.coachTheme.accentColor.opacity(0.13),
                                            .clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                        .stroke(
                            step.coachTheme == .standard
                                ? WanderTheme.textInk.color.opacity(0.08)
                                : step.coachTheme.accentColor.opacity(0.3),
                            lineWidth: 1
                        )
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
            .onPreferenceChange(WalkthroughCardSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                measuredCardSize = size
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(step.title). \(step.message)")
            .accessibilityIdentifier("walkthrough.\(step.id)")
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: step.id)
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
        case .social, .memory, .celebration:
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
                .opacity(0.68)

            WalkthroughScrimShape(
                spotlightFrame: spotlightFrame,
                cornerRadius: cornerRadius
            )
                .fill(Color.black.opacity(0.22), style: FillStyle(eoFill: true))
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
    let spotlightFrame: CGRect
    var cornerRadius = WanderTheme.radiusLarge

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
