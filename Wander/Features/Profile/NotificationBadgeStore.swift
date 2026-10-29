import Combine
import Foundation
import CoreGraphics

/// Identifies notification deliveries, not places. Re-inviting someone to the
/// same check-in creates a new generation and must show a new badge.
struct NotificationBadgeSnapshot: Equatable {
    let userID: String
    let notificationIDs: Set<String>
    let aliases: [String: Set<String>]

    init(userID: String, plans: [ReceivedPlacePlanInvitation], checkIns: [SharedVisitInvitation], follows: [FollowNotification] = [], activity: [ActivityNotification] = []) {
        self.userID = userID
        notificationIDs = Set(plans.filter(\.isUnread).map { "plan:\($0.id.uuidString)" })
            .union(checkIns.filter { $0.status == .pending }.map {
                "check-in:\($0.participantID):\($0.invitationGeneration)"
            })
            .union(follows.map { "follow:\($0.id.uuidString)" })
            .union(activity.map(\.badgeID))
        aliases = Dictionary(activity.map { ($0.badgeID, $0.badgeAliases) },
                             uniquingKeysWith: { $0.union($1) })
    }
}

/// Only rows actually encountered in the viewport are acknowledged, without
/// accepting a check-in or marking a plan opened. Only opaque IDs are persisted,
/// scoped to the account on this device; invitation contents and access remain server-owned.
@MainActor final class NotificationBadgeStore: ObservableObject {
    @Published private var seenByUser: [String: Set<String>]
    private let defaults: UserDefaults
    private let storageKey = "wander.notifications.seenIDs.v1"
    private var visibleSnapshot: NotificationBadgeSnapshot?
    private var exposedIDs: Set<String> = []
    private var visibleIDs: Set<String> = []
    private var hasScrolled = false

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
        snapshot.notificationIDs.filter { isUnseen($0, in: snapshot) }.count
    }

    func isUnseen(_ id: String, in snapshot: NotificationBadgeSnapshot) -> Bool {
        let identities = (snapshot.aliases[id] ?? []).union([id])
        return snapshot.notificationIDs.contains(id)
            && identities.isDisjoint(with: seenByUser[snapshot.userID] ?? [])
    }

    func open(_ snapshot: NotificationBadgeSnapshot) {
        if visibleSnapshot?.userID != snapshot.userID {
            exposedIDs = []
            visibleIDs = []
            hasScrolled = false
        }
        visibleSnapshot = snapshot
    }

    /// Loading or refreshing alone never consumes an offscreen notification.
    func updateVisibleInbox(_ snapshot: NotificationBadgeSnapshot) {
        guard visibleSnapshot?.userID == snapshot.userID else { return }
        visibleSnapshot = snapshot
        exposedIDs.formIntersection(snapshot.notificationIDs)
        visibleIDs.formIntersection(snapshot.notificationIDs)
    }

    /// Lazy stacks can mount rows beyond the viewport. Use actual intersections
    /// instead of onAppear. Keep dots while reading; clear them after scrolling
    /// past the row, or on leaving after it was visible.
    func observe(frames: [String: CGRect], viewport: CGRect, userID: String) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let laidOutFrames = frames.filter { _, frame in
            !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
        }
        let visible = Set(laidOutFrames.compactMap { id, frame -> String? in
            let intersection = frame.intersection(viewport)
            guard !intersection.isNull,
                  intersection.width >= min(frame.width, viewport.width) * 0.5,
                  intersection.height >= min(frame.height, viewport.height) * 0.5 else { return nil }
            return id
        })
        observeVisibleIDs(visible, userID: userID)
    }

    /// Native scroll visibility excludes preloaded rows and content insets.
    /// Layout changes during navigation are not evidence of scrolling past a row.
    func observeVisibleIDs(_ ids: Set<String>, userID: String) {
        guard let snapshot = visibleSnapshot, snapshot.userID == userID else { return }
        visibleIDs = ids.intersection(snapshot.notificationIDs)
        exposedIDs.formUnion(visibleIDs)
        if hasScrolled { acknowledgePassedRows(in: snapshot) }
    }

    func scrolled(userID: String) {
        guard let snapshot = visibleSnapshot, snapshot.userID == userID else { return }
        hasScrolled = true
        acknowledgePassedRows(in: snapshot)
    }

    private func acknowledgePassedRows(in snapshot: NotificationBadgeSnapshot) {
        markSeen(exposedIDs.subtracting(visibleIDs), in: snapshot)
        exposedIDs.formIntersection(visibleIDs)
    }

    func acknowledge(_ id: String, userID: String) {
        guard let snapshot = visibleSnapshot, snapshot.userID == userID else { return }
        markSeen([id], in: snapshot)
    }

    func close() {
        if let snapshot = visibleSnapshot { markSeen(exposedIDs, in: snapshot) }
        visibleSnapshot = nil
        exposedIDs = []
        visibleIDs = []
        hasScrolled = false
    }

    private func markSeen(_ ids: Set<String>, in snapshot: NotificationBadgeSnapshot) {
        let previous = seenByUser[snapshot.userID] ?? []
        let identities = ids.intersection(snapshot.notificationIDs).reduce(into: Set<String>()) { result, id in
            result.insert(id)
            result.formUnion(snapshot.aliases[id] ?? [])
        }
        let updated = previous.union(identities)
        guard updated != previous else { return }
        seenByUser[snapshot.userID] = updated
        defaults.set(seenByUser.mapValues { $0.sorted() }, forKey: storageKey)
    }
}
