import SwiftUI

enum WalkthroughSurface: String, CaseIterable, Codable, Sendable {
    case map
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
    case mapFilters
    case mapSearch
    case mapMemory
    case mapTabs
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
    case saveTags
    case savePrivacy
    case saveSubmit
    case feedActivity
    case feedSurfaceSwitch
    case feedPeopleSearch
    case feedInvite
    case feedSmartSearch
    case listsCreate
    case listsScope
    case listsOpenPlan
    case listMap
    case listActions
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

struct WalkthroughStep: Identifiable, Equatable, Sendable {
    let surface: WalkthroughSurface
    let target: WalkthroughTargetID
    let title: String
    let message: String
    let advance: WalkthroughAdvance

    var id: String { "\(surface.rawValue).\(target.rawValue)" }
}

enum FirstVisitWalkthroughContent {
    static let version = 4

    static let stepsBySurface: [WalkthroughSurface: [WalkthroughStep]] = [
        .map: [
            step(.map, .mapAdd, "Save your first place", "Tap + to add somewhere you've been or want to try."),
            step(.map, .mapAddAgain, "One more shortcut", "Tap + again and we’ll show you where imports live."),
            step(
                .map,
                .mapFilters,
                "Shape your map",
                "Filter to the people and moments you trust: your saves, check-ins, Wanna places, and friends.",
                advance: .next
            ),
            step(
                .map,
                .mapSearch,
                "Search your trusted map",
                "Try a place, neighborhood, or person.",
                advance: .next
            ),
            step(
                .map,
                .mapMemory,
                "This is a place memory",
                "Ratings, notes, tags, and the people behind a save stay together, so you can remember why the place matters.",
                advance: .next
            ),
            step(
                .map,
                .mapTabs,
                "Your places, all connected",
                "Map, Feed, Lists, and Profile work together to help you find, plan, and remember.",
                advance: .next
            )
        ],
        .add: [
            step(.add, .addSearch, "Find your first place", "Type a place name and submit the search."),
            step(.add, .addPlace, "Choose the right place", "Review the result, then tap Save to start your memory."),
            step(
                .add,
                .addImport,
                "Bring saves with you",
                "Import From is where links, shared posts, and notes become places to review.",
                advance: .next
            ),
            step(.add, .addClose, "Back to your map", "Tap × to close Add a Place and keep exploring.")
        ],
        .saveFlow: [
            step(.saveFlow, .saveStatus, "Start with a check-in", "Choose Check In so we can show you every part of a place memory."),
            step(.saveFlow, .saveContinue, "Add what matters", "Continue to the details that will help future you choose."),
            step(
                .saveFlow,
                .saveDate,
                "When were you here?",
                "Today is selected automatically. Change the date for an older memory, or leave it as is.",
                advance: .next
            ),
            step(
                .saveFlow,
                .saveDetails,
                "Confirm the place type",
                "Category and subcategory make this memory easier to find later. The suggested choices are fine to keep.",
                advance: .next
            ),
            step(
                .saveFlow,
                .saveRating,
                "Rate it for future you",
                "A quick rating helps you compare places later. Keep the suggested score or adjust it.",
                advance: .next
            ),
            step(
                .saveFlow,
                .saveFriends,
                "Remember who was there",
                "Add friends who shared the visit, or leave this empty when the memory is just yours.",
                advance: .next
            ),
            step(
                .saveFlow,
                .savePhotos,
                "Keep a photo with the visit",
                "Photos are optional. Add one now, or keep moving without it.",
                advance: .next
            ),
            step(
                .saveFlow,
                .saveMoreOptions,
                "Open more options",
                "Tap More Options to see the rest of the memory fields."
            ),
            step(
                .saveFlow,
                .saveNote,
                "Leave the useful detail",
                "Write what you’d want to know next time, or leave the note blank.",
                advance: .next
            ),
            step(
                .saveFlow,
                .saveTags,
                "Make it easy to rediscover",
                "Tags capture the mood, occasion, and details that make this place fit. They’re optional too.",
                advance: .next
            ),
            step(
                .saveFlow,
                .savePrivacy,
                "Choose who can see it",
                "Stealth mode keeps this memory to you. Leave it off to use your normal sharing setting.",
                advance: .next
            ),
            step(.saveFlow, .saveSubmit, "Put it on your map", "Save the place to finish your first memory.")
        ],
        .feed: [
            step(
                .feed,
                .feedActivity,
                "Why this place matters",
                "See who saved it, what they did, and the note they left.",
                advance: .next
            ),
            step(.feed, .feedSurfaceSwitch, "Places and people", "Switch between trusted place activity and the people behind it."),
            step(
                .feed,
                .feedPeopleSearch,
                "Find people you trust",
                "Search by name or handle, then follow their place activity.",
                advance: .next
            ),
            step(
                .feed,
                .feedInvite,
                "Build your trusted circle",
                "Invite the people whose taste you already rely on.",
                advance: .next
            )
        ],
        .feedSearch: [
            step(.feedSearch, .feedSmartSearch, "Search the way you think", "Try a moment, mood, or need—not just a place name.")
        ],
        .lists: [
            step(.lists, .listsCreate, "Make a list", "Tap + to turn saved places into a plan you can use."),
            step(.lists, .listsScope, "Plans from your people", "Switch between your own lists, friends' lists, and shared collabs."),
            step(.lists, .listsOpenPlan, "Open a plan", "Tap any list to see its places, map, privacy, and collaborators.")
        ],
        .listDetail: [
            step(.listDetail, .listMap, "See the whole plan", "Open the map to understand how every place fits together."),
            step(.listDetail, .listActions, "Keep the plan moving", "Add a place or edit the list whenever plans change.")
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
                .listEditorPrivacy,
                "Choose who can see it",
                "Keep it private or make it visible to the people who follow you.",
                advance: .next
            ),
            step(
                .listEditor,
                .listEditorCollaborators,
                "Plan it together",
                "Add collaborators so everyone can keep the list current.",
                advance: .next
            )
        ],
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
                advance: .next
            ),
            step(
                .profile,
                .profileActivity,
                "Your place history",
                "Filter recent activity to revisit saves, check-ins, and wanna places.",
                advance: .next
            ),
            step(
                .profile,
                .profileShare,
                "Share your rec.me",
                "Send your profile to friends whose taste you trust.",
                advance: .next
            )
        ]
    ]

    static var allSteps: [WalkthroughStep] {
        WalkthroughSurface.allCases.flatMap { stepsBySurface[$0, default: []] }
    }

    private static func step(
        _ surface: WalkthroughSurface,
        _ target: WalkthroughTargetID,
        _ title: String,
        _ message: String,
        advance: WalkthroughAdvance = .action
    ) -> WalkthroughStep {
        WalkthroughStep(
            surface: surface,
            target: target,
            title: title,
            message: message,
            advance: advance
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

    private(set) var userID: String
    private let store: FirstVisitWalkthroughStore
    private var registeredLaunchUserID: String?
    private var isImportLessonEligible = false
    private var isDeviceFeaturesLessonEligible = false
    let isEnabled: Bool

    init(
        userID: String = "local-user",
        store: FirstVisitWalkthroughStore = FirstVisitWalkthroughStore(),
        isEnabled: Bool = true
    ) {
        self.userID = userID
        self.store = store
        self.isEnabled = isEnabled
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
    }

    func registerLaunch(
        forceImportLesson: Bool = false,
        forceDeviceFeaturesLesson: Bool = false
    ) {
        guard isEnabled else { return }

        if registeredLaunchUserID != userID {
            registeredLaunchUserID = userID
            let launchCount = store.registerLaunch(for: userID)
            isImportLessonEligible = launchCount == 2
                && !store.hasCompletedImportLesson(for: userID)
            isDeviceFeaturesLessonEligible = launchCount >= 3
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
    }

    func activate(_ surface: WalkthroughSurface) {
        guard isEnabled else {
            activeSurface = nil
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
    }

    func completeDeviceFeaturesLesson() {
        guard isPresentingDeviceFeaturesLesson else { return }
        store.markDeviceFeaturesLessonComplete(for: userID)
        isDeviceFeaturesLessonEligible = false
        isPresentingDeviceFeaturesLesson = false
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
        } else {
            currentStepIndex = nextIndex
        }
    }

    private func destination(after surface: WalkthroughSurface) -> WalkthroughSurface? {
        switch surface {
        case .map:
            .feed
        case .add, .saveFlow:
            .map
        case .feed:
            .lists
        case .listEditor:
            .lists
        case .listDetail:
            .profile
        case .feedSearch:
            .feed
        case .lists, .profile:
            nil
        }
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
                Color.black.opacity(0.76)
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

private struct ImportWalkthroughOverlay: View {
    let onOpenImport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(width: 52, height: 52)
                    .background(WanderTheme.terracotta.color, in: Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text("Bring your saved places with you")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("Import links, shared posts, and place notes into one review queue. Nothing reaches your map until you approve it.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Open Import From", action: onOpenImport)
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
            Color.black.opacity(0.76)
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

    private let screenMargin: CGFloat = 16
    private let pointerHeight: CGFloat = 12
    private let spotlightInset: CGFloat = 5
    private let pointerCornerClearance: CGFloat = 28

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
    let onNext: () -> Void

    private var cardWidth: CGFloat {
        let preferred: CGFloat = step.title.count + step.message.count < 105 ? 286 : 326
        return min(preferred, max(240, containerSize.width - 32))
    }

    private var layout: WalkthroughCoachMarkLayout {
        WalkthroughCoachMarkLayout(
            targetFrame: targetFrame,
            containerSize: containerSize,
            cardSize: CGSize(width: cardWidth, height: max(measuredCardSize.height, 1))
        )
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
                allowsSpotlightInteraction: step.advance == .action
            )

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(step.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(step.message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)

                    if step.advance == .next {
                        Button("Next", action: onNext)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.textOnAction.color)
                            .frame(minWidth: 88, minHeight: 44)
                            .padding(.horizontal, WanderTheme.spacing2)
                            .background(WanderTheme.terracotta.color)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .frame(width: cardWidth, alignment: .leading)
                .background(WanderTheme.surfaceBone.color, in: RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
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
        WalkthroughScrimShape(
            spotlightFrame: spotlightFrame,
            cornerRadius: cornerRadius
        )
            .fill(Color.black.opacity(0.76), style: FillStyle(eoFill: true))
            .frame(width: containerSize.width, height: containerSize.height)
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
