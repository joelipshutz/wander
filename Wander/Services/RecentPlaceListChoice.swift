import Foundation

/// A convenience for the current browsing session, never a saved account preference.
/// Thirty minutes is an explicit Astir policy, not a universal platform timeout.
@MainActor
final class RecentPlaceListChoice {
    static let shared = RecentPlaceListChoice()
    static let lifetime: TimeInterval = 30 * 60
    private(set) var accountID: String?
    private(set) var listLocalID: String?
    private(set) var chosenAt: Date?
    private(set) var notificationPolicy: SenderNotificationPolicy = .standard

    func remember(_ list: LocalPlaceList, accountID: String,
                  notificationPolicy: SenderNotificationPolicy, now: Date = .now) {
        self.accountID = accountID
        listLocalID = list.localID
        chosenAt = now
        self.notificationPolicy = notificationPolicy
    }

    func resolve(accountID: String, lists: [LocalPlaceList], now: Date = .now) -> LocalPlaceList? {
        guard self.accountID == accountID, let chosenAt,
              now >= chosenAt, now.timeIntervalSince(chosenAt) < Self.lifetime,
              let listLocalID,
              let list = lists.first(where: { $0.localID == listLocalID && $0.deletedAt == nil }) else {
            clear()
            return nil
        }
        return list
    }

    func clear() {
        accountID = nil; listLocalID = nil; chosenAt = nil; notificationPolicy = .standard
    }
}


/// A local `.added` result is not a remote acknowledgement. Change must retain
/// the previous membership until the replacement is actually synchronized.
enum RecentPlaceListMembershipState {
    case synced, pending, failed, missing

    static func resolve(list: LocalPlaceList, items: [LocalPlaceListItem]) -> Self {
        let active = items.filter { $0.deletedAt == nil }
        guard !active.isEmpty else { return .missing }
        if list.serverID != nil, active.contains(where: { $0.serverID != nil && $0.syncState == .synced }) {
            return .synced
        }
        if list.syncState == .failed || active.contains(where: { $0.syncState == .failed }) { return .failed }
        return .pending
    }
}

/// A Change action owns its newly inserted membership, not any destination
/// that happened to contain the place already or a multi-list selection.
enum RecentPlaceListReplacementPolicy {
    static func replaceableDestinationID(destinationIDs: [String], newlyAddedIDs: Set<String>) -> String? {
        let destinations = Set(destinationIDs)
        guard destinations.count == 1, let id = destinations.first, newlyAddedIDs.contains(id) else { return nil }
        return id
    }
}
