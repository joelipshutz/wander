import SwiftUI

/// Profile owns the inbox; contextual replies remain attached to their Feed activity.
struct ProfilePrivateMessagesPresentation: ViewModifier {
    @Environment(\.liveExperienceEnabled) private var liveExperienceEnabled
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var queuedDestination: NotificationDestination?
    @Environment(\.liveMessageSession) private var demoMessageSession

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                if let destination = queuedDestination {
                    queuedDestination = nil
                    pushNotifications.route(to: destination)
                }
            }) {
                NavigationStack {
                    PrivateMessageInboxScreen(userID: store.currentUser.id,
                        repository: demoMessageSession?.repository ?? backend.privateMessageRepository,
                        analytics: store.productAnalytics,
                        onOpenContext: { context in
                            queuedDestination = context.kind == .activity
                                ? .activityComments(id: context.id) : .place(id: context.id)
                            isPresented = false
                        }, onOpenProfile: { id in
                            queuedDestination = .profile(id: id)
                            isPresented = false
                        })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
            }
            .onChange(of: store.currentUser.id) { _, _ in
                isPresented = false; queuedDestination = nil
            }

    }
}
