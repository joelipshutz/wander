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
                let userID = auth.isSignedIn ? store.currentUser.id : nil
                if plans.userID != userID { badge.close() }
                plans.reset(for: userID)
                follows.reset(for: userID)
                guard let userID, scenePhase == .active else { badge.close(); return }
                // Foreground refresh also supports people who turn push off.
                // This task cancels when the app backgrounds or identity changes.
                repeat {
                    async let planRefresh: Void = plans.refresh(userID: userID, repository: backend.placePlanInvitationRepository)
                    async let followRefresh: Void = follows.refresh(userID: userID, repository: backend.followNotificationRepository)
                    async let checkInRefresh = store.refreshSharedVisitInbox(backend: backend)
                    _ = await (planRefresh, followRefresh, checkInRefresh)
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled
            }
    }
}

struct NotificationBellButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        AstirIconActionButton(systemImage: "bell", accessibilityLabel: "Notifications",
                              accessibilityIdentifier: "feed.notifications", action: action)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : String(count))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color(uiColor: .systemRed), in: Capsule())
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(ProfileInvitationBadgeState(pendingInvitationCount: count).accessibilityValue)
    }
}
