import SwiftUI

/// One instance per root session keeps both entry points and their badges in sync.
struct NotificationInboxHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @ObservedObject var store: WanderStore
    @StateObject private var plans = PlacePlanInvitationInbox()
    @StateObject private var follows = FollowNotificationInbox()
    @StateObject private var badge = NotificationBadgeStore()
    @State private var refreshRevision = 0

    func body(content: Content) -> some View {
        content
            .environmentObject(plans)
            .environmentObject(follows)
            .environmentObject(badge)
            .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveRemoteNotification)) { _ in
                refreshRevision += 1
            }
            .task(id: "\(auth.isSignedIn)|\(store.currentUser.id)|\(auth.state.session?.userID ?? "")|\(scenePhase == .active)|\(refreshRevision)") {
                guard !Task.isCancelled else { return }
                let userID = auth.isSignedIn ? store.currentUser.id : nil
                if plans.userID != userID { badge.close() }
                plans.reset(for: userID)
                follows.reset(for: userID)
                guard let userID, scenePhase == .active else { badge.close(); return }
                // Foreground refresh also supports people who turn push off.
                // This task cancels when the app backgrounds or identity changes.
                repeat {
                    async let planRefresh: Void = refreshPlans(userID: userID)
                    async let followRefresh: Void = refreshFollows(userID: userID)
                    async let checkInRefresh = store.refreshSharedVisitInbox(backend: backend)
                    _ = await (planRefresh, followRefresh, checkInRefresh)
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled
            }
    }

    // Resolve non-Sendable repositories on their owning actor, rather than
    // evaluating those arguments inside an async-let child task.
    @MainActor private func refreshPlans(userID: String) async {
        await plans.refresh(userID: userID, repository: backend.placePlanInvitationRepository)
    }

    @MainActor private func refreshFollows(userID: String) async {
        await follows.refresh(userID: userID, repository: backend.followNotificationRepository)
    }
}

/// Both foreground polling and an open inbox update these same source states.
/// Derive the message live so an unchanged successful response still clears it.
enum NotificationInboxRefreshStatus {
    @MainActor static func errorMessage(
        userID: String,
        plans: PlacePlanInvitationInbox,
        follows: FollowNotificationInbox,
        checkInFailureUserID: String?
    ) -> String? {
        var sources: [String] = []
        if follows.userID == userID, follows.failed { sources.append("follower notifications") }
        if plans.userID == userID, plans.failed { sources.append("plan invitations") }
        if checkInFailureUserID == userID { sources.append("check-in invitations") }
        guard !sources.isEmpty else { return nil }
        if sources.count == 3 { return "Couldn’t refresh notifications" }
        return "Couldn’t refresh \(sources.joined(separator: " and "))"
    }
}

struct NotificationBellButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        AstirIconActionButton(systemImage: "bell", accessibilityLabel: "Notifications",
                              accessibilityIdentifier: "feed.notifications", action: action)
            .anchorPreference(key: NotificationBellAnchorKey.self, value: .bounds) { $0 }
            .accessibilityValue(ProfileInvitationBadgeState(pendingInvitationCount: count).accessibilityValue)
    }
}

struct NotificationBellAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct NotificationCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count))
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color(uiColor: .systemRed), in: Capsule())
        }
    }
}
