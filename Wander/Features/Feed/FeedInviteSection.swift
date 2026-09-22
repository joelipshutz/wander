import SwiftUI

struct FeedInviteSection: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @State private var isPresentingContactInvites = false

    var body: some View {
        InviteEntryPointButton(surface: .feedPeople) {
            walkthroughs.perform(.feedInvite)
            isPresentingContactInvites = true
        }
        .walkthroughTarget(.feedInvite)
        .onChange(of: walkthroughs.isRequestingContactInvite, initial: true) { _, requested in
            if requested { isPresentingContactInvites = true }
        }
        .sheet(isPresented: $isPresentingContactInvites, onDismiss: {
            walkthroughs.completeContactInviteRequest()
        }) {
            ContactInviteSheet(
                surface: .feedPeople,
                contactProvider: store.contactProvider,
                senderProfileID: store.currentUser.id,
                canDismiss: !walkthroughs.isRequestingContactInvite,
                walkthroughSelectionGoal: walkthroughs.isRequestingContactInvite ? 5 : nil,
                onPermissionDenied: walkthroughs.isRequestingContactInvite ? { isPresentingContactInvites = false } : nil,
                selectedContactIDs: walkthroughs.tutorialInvitedContactIDs,
                onWalkthroughSelectionChange: walkthroughs.recordTutorialInvitedContactIDs,
                analytics: store.productAnalytics
            )
            .interactiveDismissDisabled(walkthroughs.isRequestingContactInvite)
        }
    }
}
