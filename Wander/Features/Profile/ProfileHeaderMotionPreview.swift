#if DEBUG
import SwiftUI
import UIKit

/// Runs the real shared profile component with in-memory, non-account fixtures.
struct ProfileHeaderMotionPreview: View {
    let variant: ProfileHeaderMotionVariant
    @StateObject private var store: WanderStore
    @StateObject private var walkthroughs = FirstVisitWalkthroughCoordinator(isEnabled: false)
    @State private var selectedMonth = Date(timeIntervalSince1970: 1_788_998_400)
    @State private var tab = WanderTab.profile
    private let member: Bool
    private let profile: LocalProfile

    init(variant: ProfileHeaderMotionVariant) {
        self.variant = variant
        if ProcessInfo.processInfo.arguments.contains("-ProfileMotionCapture") {
            for name in ["profile-motion-ready", "profile-motion-start"] {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(name))
            }
        }
        member = ProcessInfo.processInfo.arguments.contains("-ProfileMotionMember")
        let fixtures = WanderFixtures.seed()
        let profile = member ? fixtures.profiles.first(where: { $0.handle == "maya" })! : fixtures.currentUser
        profile.displayName = member ? "Maya Chen" : "Alex Morgan"
        profile.handle = member ? "mayachen" : "alexmorgan"
        profile.homeArea = "Los Angeles, CA"
        profile.bio = "Good coffee. Long dinners. Places worth going back to."
        profile.createdAt = Date(timeIntervalSince1970: 1_750_032_000)
        profile.avatarURL = Self.demoAvatar(tile: member ? 1 : 0)
        self.profile = profile
        _store = StateObject(wrappedValue: WanderStore(fixtures: fixtures))
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(WanderTab.allCases.filter { $0 != .add }, id: \.self) { item in
                NavigationStack { home }
                    .tabItem { Label(item.title, systemImage: item.systemImage) }
                    .tag(item)
            }
        }
        .environmentObject(store)
        .environmentObject(walkthroughs)
        .environment(\.profileHeaderMotion, variant)
        .astirAdaptiveBrandMode()
        .tint(AstirBrandMode.editorialLight.accent)
    }

    private var home: some View {
        let presentation = ProfilePresentationCache().present(store: store, profileID: profile.id)
        let insights = ProfileInsightsPresenter.present(
            ownerID: profile.id, userPlaces: store.userPlaces, visits: store.placeVisits,
            places: store.places, month: selectedMonth
        )
        return ProfileOwnerHome(
            profile: profile, viewerProfile: store.currentUser,
            mode: member ? .member(relationship: .mutual, inCommonCount: 12) : .owner,
            stats: presentation.stats, saveStreak: nil,
            followerCount: 128, followingCount: 96, sharedVisitInvitationCount: 0,
            insights: insights, selectedMonth: $selectedMonth,
            avatarAction: {}, editAction: {}, settingsAction: {}, shareAction: {}, relationshipAction: {},
            backAction: member ? {} : nil,
            memberActions: member ? ProfileMemberActions(canUnfollow: true, isMuted: false, unfollowAction: {}, toggleMuteAction: {}, reportAction: {}, blockAction: {}) : nil,
            graphAction: { _ in }, sharedVisitInvitationsAction: {}, recentActivity: presentation.activityItems,
            recentActivityAction: { _ in }, allActivityAction: { _ in }, inCommonAction: {},
            calendarDateAction: { _ in }, mapSummaryAction: { _, _ in }, yourMapAction: {},
            calendarScrollRequestID: nil, onCalendarScrollRequestHandled: { _ in }
        )
        .background(ProfileMotionScrollDriver())
    }

    // Reuse the existing bundled demo contact sheet, with its existing 2x2 tile
    // convention. The image is written inside the preview app's temp container.
    private static func demoAvatar(tile: Int) -> String? {
        guard let source = UIImage(named: "PlaceCarouselAvatars")?.cgImage else { return nil }
        let w = source.width / 2, h = source.height / 2
        guard let image = source.cropping(to: CGRect(x: tile % 2 * w, y: tile / 2 * h, width: w, height: h)),
              let data = UIImage(cgImage: image).pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-motion-avatar-\(tile).png")
        try? data.write(to: url)
        return url.absoluteString
    }
}

/// A fixed scroll gesture timeline makes every option and appearance directly comparable.
/// Without -ProfileMotionAutoplay the same native ScrollView is fully interactive.
private struct ProfileMotionScrollDriver: UIViewRepresentable {
    func makeUIView(context: Context) -> Driver { Driver() }
    func updateUIView(_ uiView: Driver, context: Context) {}
    static func dismantleUIView(_ uiView: Driver, coordinator: ()) { uiView.stop() }

    final class Driver: UIView {
        private var link: CADisplayLink?
        private var started: CFTimeInterval?
        private weak var scroll: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, link == nil,
                  ProcessInfo.processInfo.arguments.contains("-ProfileMotionAutoplay") else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            self.link = link
            link.add(to: .main, forMode: .common)
        }

        func stop() { link?.invalidate(); link = nil }

        @objc private func tick(_ link: CADisplayLink) {
            if scroll == nil {
                guard let root = superview else { return }
                scroll = findScroll(root)
                if scroll == nil, let root = root.superview { scroll = findScroll(root) }
                guard scroll != nil else { return }
                if ProcessInfo.processInfo.arguments.contains("-ProfileMotionCapture") {
                    try? Data().write(to: URL.documentsDirectory.appendingPathComponent("profile-motion-ready"))
                } else {
                    started = link.timestamp
                }
            }
            if started == nil, scroll != nil,
               FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("profile-motion-start").path) {
                started = link.timestamp
            }
            guard let scroll, let started else { return }
            let t = link.timestamp - started
            let keyframes: [(Double, CGFloat)] = [(0, 0), (2, 0), (5, 370), (6, 370), (8, 750), (9, 750), (13, 0), (15, 0)]
            var offset: CGFloat = 0
            for index in 1..<keyframes.count where t >= keyframes[index - 1].0 && t <= keyframes[index].0 {
                let a = keyframes[index - 1], b = keyframes[index]
                let p = CGFloat((t - a.0) / (b.0 - a.0))
                let smooth = p * p * (3 - 2 * p)
                offset = a.1 + (b.1 - a.1) * smooth
            }
            let maxOffset = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: min(offset, maxOffset) - scroll.adjustedContentInset.top), animated: false)
            if t >= 15 { stop() }
        }

        private func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 100 { return scroll }
            for child in view.subviews {
                if let found = findScroll(child) { return found }
            }
            return nil
        }
    }
}
#endif
