import Combine
import Foundation

/// Identifies notification deliveries, not places. Re-inviting someone to the
/// same check-in creates a new generation and must show a new badge.
struct NotificationBadgeSnapshot: Equatable {
    let userID: String
    let notificationIDs: Set<String>

    init(userID: String, plans: [ReceivedPlacePlanInvitation], checkIns: [SharedVisitInvitation], follows: [FollowNotification] = []) {
        self.userID = userID
        notificationIDs = Set(plans.filter(\.isUnread).map { "plan:\($0.id.uuidString)" })
            .union(checkIns.filter { $0.status == .pending }.map {
                "check-in:\($0.participantID):\($0.invitationGeneration)"
            })
            .union(follows.map { "follow:\($0.id.uuidString)" })
    }
}

/// Visiting the inbox acknowledges its badge without accepting a check-in or
/// marking a plan opened. Only opaque IDs are persisted, scoped to the account
/// on this device; invitation contents and access remain server-owned.
@MainActor final class NotificationBadgeStore: ObservableObject {
    @Published private var seenByUser: [String: Set<String>]
    private let defaults: UserDefaults
    private let storageKey = "wander.notifications.seenIDs.v1"
    private var visibleUserID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-WanderAuthenticatedUITest"), arguments.contains("-WanderResetNotificationBadge") {
            defaults.removeObject(forKey: storageKey)
        }
        #endif
        let stored = defaults.dictionary(forKey: storageKey) as? [String: [String]] ?? [:]
        seenByUser = stored.mapValues { Set($0) }
    }

    func count(for snapshot: NotificationBadgeSnapshot) -> Int {
        snapshot.notificationIDs.subtracting(seenByUser[snapshot.userID] ?? []).count
    }

    func open(_ snapshot: NotificationBadgeSnapshot) {
        visibleUserID = snapshot.userID
        markSeen(snapshot)
    }

    /// A refresh may finish after navigation has left the inbox. Only consume
    /// those deliveries while the same account's inbox is still visible.
    func updateVisibleInbox(_ snapshot: NotificationBadgeSnapshot) {
        guard visibleUserID == snapshot.userID else { return }
        markSeen(snapshot)
    }

    func close() {
        visibleUserID = nil
    }

    private func markSeen(_ snapshot: NotificationBadgeSnapshot) {
        let previous = seenByUser[snapshot.userID] ?? []
        let updated = previous.union(snapshot.notificationIDs)
        guard updated != previous else { return }
        seenByUser[snapshot.userID] = updated
        defaults.set(seenByUser.mapValues { $0.sorted() }, forKey: storageKey)
    }
}
