import Combine
import Foundation

/// The server owns persistence and authorization; this cache belongs to one
/// validated profile at a time and never persists invitation contents on disk.
@MainActor final class PlacePlanInvitationInbox: ObservableObject {
    @Published private(set) var invitations: [ReceivedPlacePlanInvitation] = []
    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var requestID = UUID()

    func reset(for userID: String?) {
        guard self.userID != userID else { return }
        requestID = UUID()
        self.userID = userID
        invitations = []
        isLoading = false
        failed = false
    }

    func unreadCount(for userID: String) -> Int {
        self.userID == userID ? invitations.filter(\.isUnread).count : 0
    }

    func refresh(userID: String, repository: (any PlacePlanInvitationRepository)?) async {
        reset(for: userID)
        let request = UUID()
        requestID = request
        isLoading = true
        failed = false
        defer {
            if self.userID == userID, requestID == request { isLoading = false }
        }
        do {
            guard let repository else { throw WanderRemoteError.notConfigured }
            let rows = try await repository.receivedInvitations()
            guard self.userID == userID, requestID == request, !Task.isCancelled else { return }
            invitations = rows
        } catch {
            guard self.userID == userID, requestID == request, !Task.isCancelled else { return }
            // A failed refresh is not evidence that cached access remains valid.
            invitations = []
            failed = true
        }
    }

    func markOpened(id: UUID, userID: String, analytics: AnalyticsClient) {
        guard self.userID == userID, let index = invitations.firstIndex(where: { $0.id == id }) else { return }
        requestID = UUID()
        isLoading = false
        invitations[index].readAt = invitations[index].readAt ?? .now
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.notificationOpened, properties: [
            "notification_type": "place_plan_invitation", "delivery_channel": "in_app", "route": "place_plan"
        ]))
    }
}
