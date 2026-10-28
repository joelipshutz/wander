import Combine
import Foundation

/// Recipient-owned history. Server RLS rechecks source visibility on every read.
struct ActivityNotification: Identifiable, Decodable, Equatable {
    let id: UUID
    let actorID: String?
    let notificationType: String
    let title: String
    let body: String
    let createdAt: Date
    let data: [String: JSONValue]

    static let supportedTypes = ["activity_liked", "activity_commented", "followed_place_visit",
                                 "place_saved_from_your_map", "list_collaborator_added", "list_place_added",
                                 "followed_activity_digest"]

    enum CodingKeys: String, CodingKey {
        case id, title, body, data
        case actorID = "actor_user_id", notificationType = "notification_type", createdAt = "created_at"
    }

    private func string(_ key: String) -> String? {
        guard case .string(let value) = data[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    var isGroupedImport: Bool { string("sender_import_id") != nil }

    // Grouped imports can lose access to individual places after delivery. Never
    // show the stored snapshot's names/count or navigate to its stale first place.
    var displayTitle: String { isGroupedImport ? "New Places From Your People" : title }
    var displayBody: String { isGroupedImport ? "Open To See Their Available Activity." : body }

    var symbol: String {
        switch notificationType {
        case "activity_liked": "heart"
        case "activity_commented": "bubble.left"
        case "followed_place_visit": "mappin.and.ellipse"
        case "place_saved_from_your_map": "bookmark"
        case "list_collaborator_added", "list_place_added": "list.bullet"
        default: "bell"
        }
    }

    var destination: NotificationDestination? {
        guard Self.supportedTypes.contains(notificationType) else { return nil }
        if isGroupedImport { return .discover }
        if ["activity_liked", "activity_commented", "followed_place_visit", "place_saved_from_your_map"].contains(notificationType),
           let activityID = string("activity_id") { return .activityComments(id: activityID) }
        switch notificationType {
        case "followed_place_visit":
            if let userPlaceID = string("user_place_id"), let visitID = string("visit_id"),
               UUID(uuidString: userPlaceID) != nil, UUID(uuidString: visitID) != nil {
                return .checkInComments(userPlaceID: userPlaceID, visitID: visitID)
            }
            return string("place_id").map { .place(id: $0) }
        case "place_saved_from_your_map": return string("place_id").map { .place(id: $0) }
        case "list_collaborator_added", "list_place_added": return string("list_id").map { .list(id: $0) }
        case "followed_activity_digest": return .discover
        default: return nil
        }
    }

    var openedEvent: AnalyticsEvent? {
        guard destination != nil else { return nil }
        return AnalyticsEvent(name: WanderAnalyticsEvents.notificationOpened, properties: [
            "notification_type": notificationType, "delivery_channel": "in_app", "route": analyticsRoute
        ])
    }

    var analyticsRoute: String {
        switch destination {
        case .activityComments, .checkInComments: "activity_comments"
        case .place: "place"
        case .list: "list"
        default: "discover"
        }
    }
}

@MainActor protocol ActivityNotificationRepository {
    func receivedActivity(userID: String) async throws -> [ActivityNotification]
}

@MainActor struct SupabaseActivityNotificationRepository: ActivityNotificationRepository {
    let table: any RemoteTableCalling

    func receivedActivity(userID: String) async throws -> [ActivityNotification] {
        // Recipient filter is defense in depth; server RLS is authoritative.
        // APNs acceptance is not a prerequisite for reading an existing event.
        // Suppressed events stay suppressed, and delayed events wait until due.
        try await table.select(table: "notification_events", queryItems: [
            URLQueryItem(name: "select", value: "id,actor_user_id,notification_type,title,body,created_at,data"),
            URLQueryItem(name: "recipient_user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "notification_type", value: "in.(\(ActivityNotification.supportedTypes.joined(separator: ",")))"),
            URLQueryItem(name: "status", value: "in.(pending,claimed,sent,failed)"),
            URLQueryItem(name: "not_before", value: "lte.\(ISO8601DateFormatter().string(from: .now))"),
            URLQueryItem(name: "order", value: "created_at.desc,id.desc"),
            URLQueryItem(name: "limit", value: "100")
        ])
    }
}

/// Session memory only. Failure clears stale social content; retry restores it.
@MainActor final class ActivityNotificationInbox: ObservableObject {
    @Published private(set) var notifications: [ActivityNotification] = []
    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var generation = UUID()

    func reset(for userID: String?) {
        guard self.userID != userID else { return }
        generation = UUID()
        self.userID = userID
        notifications = []
        isLoading = false
        failed = false
    }

    func visibleNotifications(userID: String, isBlocked: (String) -> Bool) -> [ActivityNotification] {
        guard self.userID == userID else { return [] }
        return notifications.filter { $0.actorID.map { !isBlocked($0) } ?? true }
    }

    func refresh(userID: String, repository: (any ActivityNotificationRepository)?) async {
        guard !Task.isCancelled else { return }
        reset(for: userID)
        let request = UUID()
        generation = request
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            guard let repository else { throw WanderRemoteError.notConfigured }
            let rows = try await repository.receivedActivity(userID: userID)
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            var seen: Set<UUID> = []
            notifications = rows.filter { $0.destination != nil && seen.insert($0.id).inserted }
                .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
            failed = false
        } catch {
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            notifications = []
            failed = true
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
struct SimulatorActivityNotificationRepository: ActivityNotificationRepository {
    var includesNotifications = false

    func receivedActivity(userID: String) async throws -> [ActivityNotification] {
        guard includesNotifications else { return [] }
        return [ActivityNotification(id: UUID(uuidString: "65300000-0000-0000-0000-000000000001")!,
            actorID: "user_ryan", notificationType: "activity_commented", title: "Ryan Commented On Your Activity",
            body: "Open The Conversation", createdAt: .now.addingTimeInterval(-60),
            data: ["activity_id": .string("fixture-feed-maya-been-bar-nido")]),
            ActivityNotification(id: UUID(uuidString: "65300000-0000-0000-0000-000000000002")!,
                actorID: "user_ryan", notificationType: "followed_place_visit", title: "Stored Import Summary",
                body: "Stored Import Details", createdAt: .now.addingTimeInterval(-120),
                data: ["sender_import_id": .string("synthetic-import"), "place_id": .string("stale-place")])]
    }
}
#endif
