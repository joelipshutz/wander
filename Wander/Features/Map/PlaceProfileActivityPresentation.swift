import SwiftUI

/// History actions belong to the visible place profile. Sending them to the
/// root Feed coordinator pushes a destination behind the presented profile.
struct PlaceProfileActivityPresentation: ViewModifier {
    @Environment(\.activityPresentationHandoff) private var handoff
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @StateObject private var navigation = ActivityNavigationCoordinator()
    @State private var selectedProfile: ProfileShell?
    let onLeavePlace: () -> Void

    func body(content: Content) -> some View {
        content
            .environmentObject(navigation)
            .fullScreenCover(item: routeBinding, onDismiss: { handoff.onDidDismiss(.activityComments) }) { route in
                WanderRootPresentationLifecycle(
                    surface: .activityComments, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
                ) {
                    NavigationStack {
                        ActivityCommentsRouteScreen(
                            requestID: route.id,
                            retry: { _ = await navigation.resolveCurrentRoute(store: store, auth: auth, backend: backend) },
                            openProfile: { selectedProfile = $0 },
                            openPlace: { _ in navigation.dismiss(requestID: route.id) },
                            openList: { listID in
                                navigation.dismiss(requestID: route.id)
                                onLeavePlace()
                                pushNotifications.route(to: .list(id: listID))
                            }
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Back", systemImage: "chevron.left") {
                                    navigation.dismiss(requestID: route.id)
                                }
                                .accessibilityIdentifier("place-activity.comments.back")
                            }
                        }
                    }
                    .environmentObject(navigation)
                    .environment(\.activityPostcardVisualStyle, .astir)
                    .blocksProductUpsells(while: true, preservesForegroundEntry: true)
                    .fullScreenCover(item: $selectedProfile, onDismiss: { handoff.onDidDismiss(.activityProfile) }) { profile in
                        WanderRootPresentationLifecycle(
                            surface: .activityProfile, onPresent: handoff.onPresent, onDismiss: handoff.onWillDismiss
                        ) {
                            ProfileDetailView(profileID: profile.id)
                        }
                    }
                }
            }
            .onChange(of: store.currentUser.id) { _, _ in reset() }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if !isSignedIn { reset() }
            }
            .onChange(of: handoff.resetID) { _, resetID in
                if resetID != nil { reset() }
            }
    }

    private var routeBinding: Binding<ActivityCommentsRoute?> {
        Binding(get: { navigation.commentsRoute }, set: { route in
            guard route == nil, let requestID = navigation.commentsRoute?.id else { return }
            navigation.dismiss(requestID: requestID)
        })
    }

    private func reset() {
        selectedProfile = nil
        navigation.reset()
    }
}
