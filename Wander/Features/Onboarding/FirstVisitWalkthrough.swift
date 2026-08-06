import SwiftUI

enum WalkthroughSurface: String, CaseIterable, Codable, Sendable {
    case map
    case add
    case feed
    case feedSearch
    case lists
    case listDetail
    case listEditor
    case profile
}

enum WalkthroughTargetID: String, Codable, Sendable {
    case mapAdd
    case mapFilters
    case mapSearch
    case mapMarker
    case mapTabs
    case addSearch
    case addImport
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

struct WalkthroughStep: Identifiable, Equatable, Sendable {
    let surface: WalkthroughSurface
    let target: WalkthroughTargetID
    let title: String
    let message: String

    var id: String { "\(surface.rawValue).\(target.rawValue)" }
}

enum FirstVisitWalkthroughContent {
    static let version = 1

    static let stepsBySurface: [WalkthroughSurface: [WalkthroughStep]] = [
        .map: [
            step(.map, .mapAdd, "Save your first place", "Tap + to add somewhere you've been or want to try."),
            step(.map, .mapFilters, "Shape your map", "Use these filters to switch people, social circles, check-ins, and wanna places."),
            step(.map, .mapSearch, "Search your trusted map", "Try a place, neighborhood, or person."),
            step(.map, .mapMarker, "Open a place memory", "Tap a marker to see who saved it and why."),
            step(.map, .mapTabs, "Four ways back in", "Map, Feed, Lists, and Profile each remember where you left off.")
        ],
        .add: [
            step(.add, .addSearch, "Start with a place", "Search by name or use the camera menu to bring one in."),
            step(.add, .addImport, "Bring saves with you", "Import from a link, social app, or your notes.")
        ],
        .feed: [
            step(.feed, .feedActivity, "Why this place matters", "See who saved it, what they did, and the note they left."),
            step(.feed, .feedSurfaceSwitch, "Places and people", "Switch between trusted place activity and the people behind it."),
            step(.feed, .feedPeopleSearch, "Find people you trust", "Search by name or handle, then follow their place activity."),
            step(.feed, .feedInvite, "Build your trusted circle", "Invite the people whose taste you already rely on.")
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
            step(.listEditor, .listEditorTitle, "Name the plan", "Give this list a title you'll recognize when the moment comes."),
            step(.listEditor, .listEditorPrivacy, "Choose who can see it", "Keep it private or make it visible to the people who follow you."),
            step(.listEditor, .listEditorCollaborators, "Plan it together", "Add collaborators so everyone can keep the list current.")
        ],
        .profile: [
            step(.profile, .profileSettings, "Make rec.me yours", "Open settings for account, privacy, notifications, and app preferences."),
            step(.profile, .profileSocial, "Your trusted circle", "See who you follow and who follows your recommendations."),
            step(.profile, .profileActivity, "Your place history", "Filter recent activity to revisit saves, check-ins, and wanna places."),
            step(.profile, .profileShare, "Share your rec.me", "Send your profile to friends whose taste you trust.")
        ]
    ]

    static var allSteps: [WalkthroughStep] {
        WalkthroughSurface.allCases.flatMap { stepsBySurface[$0, default: []] }
    }

    private static func step(
        _ surface: WalkthroughSurface,
        _ target: WalkthroughTargetID,
        _ title: String,
        _ message: String
    ) -> WalkthroughStep {
        WalkthroughStep(surface: surface, target: target, title: title, message: message)
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
    }

    private func progressKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.v\(version).\(userID).\(surface.rawValue).progress"
    }

    private func completionKey(userID: String, surface: WalkthroughSurface) -> String {
        "wander.walkthrough.v\(version).\(userID).\(surface.rawValue).complete"
    }
}

@MainActor
final class FirstVisitWalkthroughCoordinator: ObservableObject {
    @Published private(set) var activeSurface: WalkthroughSurface?
    @Published private(set) var currentStepIndex = 0

    private(set) var userID: String
    private let store: FirstVisitWalkthroughStore
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

    func setUserID(_ userID: String) {
        guard self.userID != userID else { return }
        self.userID = userID
        activeSurface = nil
        currentStepIndex = 0
    }

    func activate(_ surface: WalkthroughSurface) {
        guard isEnabled else {
            activeSurface = nil
            return
        }
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

    func perform(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target else { return }
        advance()
    }

    func recoverUnavailableTarget(_ target: WalkthroughTargetID) {
        guard currentStep?.target == target else { return }
        advance()
    }

    func resetCurrentUser() {
        store.reset(for: userID)
        activeSurface = nil
        currentStepIndex = 0
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
        } else {
            currentStepIndex = nextIndex
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
                                containerSize: proxy.size
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
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                coordinator.recoverUnavailableTarget(step.target)
            }
    }
}

private struct FirstVisitWalkthroughOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let step: WalkthroughStep
    let targetFrame: CGRect
    let containerSize: CGSize

    private var spotlightFrame: CGRect {
        targetFrame
            .insetBy(dx: -8, dy: -8)
            .intersection(CGRect(origin: .zero, size: containerSize))
    }

    private var cardWidth: CGFloat { min(326, max(240, containerSize.width - 32)) }
    private var cardHeight: CGFloat { 126 }
    private var cardAboveTarget: Bool { spotlightFrame.midY > containerSize.height * 0.48 }

    private var cardCenter: CGPoint {
        let proposedY = cardAboveTarget
            ? spotlightFrame.minY - cardHeight / 2 - 24
            : spotlightFrame.maxY + cardHeight / 2 + 24
        return CGPoint(
            x: min(max(spotlightFrame.midX, cardWidth / 2 + 16), containerSize.width - cardWidth / 2 - 16),
            y: min(max(proposedY, cardHeight / 2 + 16), containerSize.height - cardHeight / 2 - 16)
        )
    }

    var body: some View {
        ZStack {
            WalkthroughScrim(spotlightFrame: spotlightFrame)
                .allowsHitTesting(false)

            WalkthroughOutsideTouchBlocker(frame: spotlightFrame, containerSize: containerSize)

            VStack(spacing: 0) {
                if !cardAboveTarget {
                    WalkthroughPointer()
                        .fill(WanderTheme.surfaceBone.color)
                        .frame(width: 24, height: 12)
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(step.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(step.message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: cardWidth, alignment: .leading)
                .frame(minHeight: cardHeight, alignment: .leading)
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color, in: RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                        .stroke(WanderTheme.textInk.color.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 18, y: 8)

                if cardAboveTarget {
                    WalkthroughPointer()
                        .fill(WanderTheme.surfaceBone.color)
                        .frame(width: 24, height: 12)
                        .rotationEffect(.degrees(180))
                }
            }
            .position(cardCenter)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(step.title). \(step.message)")
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: step.id)
    }
}

private struct WalkthroughScrim: View {
    let spotlightFrame: CGRect

    var body: some View {
        Color.black.opacity(0.72)
            .reverseMask {
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                    .frame(width: spotlightFrame.width, height: spotlightFrame.height)
                    .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
            }
    }
}

private struct WalkthroughOutsideTouchBlocker: View {
    let frame: CGRect
    let containerSize: CGSize

    var body: some View {
        ZStack {
            blocker(CGRect(x: 0, y: 0, width: containerSize.width, height: max(0, frame.minY)))
            blocker(CGRect(x: 0, y: frame.maxY, width: containerSize.width, height: max(0, containerSize.height - frame.maxY)))
            blocker(CGRect(x: 0, y: frame.minY, width: max(0, frame.minX), height: max(0, frame.height)))
            blocker(CGRect(x: frame.maxX, y: frame.minY, width: max(0, containerSize.width - frame.maxX), height: max(0, frame.height)))
        }
        .accessibilityHidden(true)
    }

    private func blocker(_ rect: CGRect) -> some View {
        Color.black.opacity(0.001)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture { }
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

private extension View {
    func reverseMask<MaskContent: View>(@ViewBuilder _ maskContent: () -> MaskContent) -> some View {
        self.mask {
            Rectangle()
                .overlay(maskContent().blendMode(.destinationOut))
                .compositingGroup()
        }
    }
}
